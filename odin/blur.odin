package main

import "base:intrinsics"
import "core:log"
import "core:os"
import "core:strconv"
import "core:thread"
import "core:sync"
import "core:time"
import "core:math"
import "core:math/linalg"
import "core:simd"
import stbi "vendor:stb/image"
import "core:strings"
import "core:mem"

// Image struct is defined in common.odin

BlurWorkerContext :: struct {
    src: ^Image,
    src_transposed: ^Image,
    dst: ^Image,
    dst_transposed: ^Image,
    kernel: []f32,  // Changed to f32 for SIMD
    radius: int,
    start_y: int,
    end_y: int,
}

// Generate Gaussian kernel (using f32 for SIMD compatibility)
generate_gaussian_kernel :: proc(radius: int) -> []f32 {
    size := 2 * radius + 1
    kernel := make([]f32, size)
    sigma := f32(radius) / 3.0
    sum: f32 = 0.0

    for i := 0; i < size; i += 1 {
        x := f32(i - radius)
        kernel[i] = math.exp_f32(-(x * x) / (2.0 * sigma * sigma))
        sum += kernel[i]
    }

    // Normalize
    for i := 0; i < size; i += 1 {
        kernel[i] /= sum
    }

    return kernel
}

// Transpose image data for better cache locality
transpose_image :: proc(src: ^Image, dst: ^Image) {
    for y := 0; y < src.height; y += 1 {
        for x := 0; x < src.width; x += 1 {
            src_idx := (y * src.width + x) * src.channels
            dst_idx := (x * src.height + y) * src.channels
            dst.data[dst_idx] = src.data[src_idx]
            dst.data[dst_idx + 1] = src.data[src_idx + 1]
            dst.data[dst_idx + 2] = src.data[src_idx + 2]
            dst.data[dst_idx + 3] = src.data[src_idx + 3]
        }
    }
}

// SIMD width - 8 allows processing 2 pixels at once
SIMD_WIDTH :: 64
PIXEL_PER_ITER :: SIMD_WIDTH / 4

// Horizontal Gaussian blur for 4-channel images with SIMD optimization
horizontal_gaussian_blur :: proc(src: ^Image, dst: ^Image, kernel: []f32, radius: int, start_y: int, end_y: int) {
    process_chunk :: proc(src: ^u8, mask: #simd[SIMD_WIDTH]bool, weights: #simd[PIXEL_PER_ITER]f32) -> #simd[PIXEL_PER_ITER]f32 {
        ptr_u8 := cast(^#simd[SIMD_WIDTH]u8)src
        data_masked := simd.masked_load(ptr_u8, cast(#simd[SIMD_WIDTH]u8)0, mask)
        data_u32 := transmute(#simd[PIXEL_PER_ITER]u32)data_masked
        data_f32 := cast(#simd[PIXEL_PER_ITER]f32)data_u32
        return data_f32 * weights
    }
    kernel_size := 2 * radius + 1
    mask : #simd[SIMD_WIDTH]bool
    for i in 0..<PIXEL_PER_ITER {
        mask = simd.replace(mask, i*4, true)
    }
    for y := start_y; y < end_y; y += 1 {
        for x := 0; x < src.width; x += 1 {
            // Accumulators for 4 channels
            r_sum, g_sum, b_sum, a_sum: f32 = 0, 0, 0, 0
            // Apply kernel PIXEL_PER_ITER elements at a time
            k := 0
            for ; k + PIXEL_PER_ITER - 1 < kernel_size; k += PIXEL_PER_ITER {
                weights := intrinsics.unaligned_load(cast(^#simd[PIXEL_PER_ITER]f32)raw_data(kernel[k:]))
                base_x := x - radius + k

                // Check if all pixels are within bounds for fast path
                if base_x >= 0 && base_x + PIXEL_PER_ITER - 1 < src.width {
                    // Fast path: all pixels within bounds
                    // Process PIXEL_PER_ITER pixels at once, accumulating directly
                    idx := (y * src.width + base_x) * 4
                    r_sum += simd.reduce_add_ordered(process_chunk(raw_data(src.data[idx:]), mask, weights))
                    g_sum += simd.reduce_add_ordered(process_chunk(raw_data(src.data[idx+1:]), mask, weights))
                    b_sum += simd.reduce_add_ordered(process_chunk(raw_data(src.data[idx+2:]), mask, weights))
                    a_sum += simd.reduce_add_ordered(process_chunk(raw_data(src.data[idx+3:]), mask, weights))
                } else {
                    // Slow path: need boundary checking - fall back to scalar
                    for i in 0..<PIXEL_PER_ITER {
                        px := base_x + i
                        // Clamp to image bounds
                        if px < 0 { px = 0 }
                        if px >= src.width { px = src.width - 1 }

                        idx := (y * src.width + px) * 4
                        weight := simd.extract(weights, i)
                        r_sum += f32(src.data[idx]) * weight
                        g_sum += f32(src.data[idx + 1]) * weight
                        b_sum += f32(src.data[idx + 2]) * weight
                        a_sum += f32(src.data[idx + 3]) * weight
                    }
                }
            }

            // Handle remaining kernel elements
            for ; k < kernel_size; k += 1 {
                weight := kernel[k]
                px := x - radius + k

                // Clamp to bounds
                if px < 0 { px = 0 }
                if px >= src.width { px = src.width - 1 }

                idx := (y * src.width + px) * 4
                r_sum += f32(src.data[idx]) * weight
                g_sum += f32(src.data[idx + 1]) * weight
                b_sum += f32(src.data[idx + 2]) * weight
                a_sum += f32(src.data[idx + 3]) * weight
            }

            // Write result for this pixel
            dst_idx := (y * dst.width + x) * 4
            dst.data[dst_idx] = u8(math.round_f32(r_sum))
            dst.data[dst_idx + 1] = u8(math.round_f32(g_sum))
            dst.data[dst_idx + 2] = u8(math.round_f32(b_sum))
            dst.data[dst_idx + 3] = u8(math.round_f32(a_sum))
        }
    }
}

worker_horizontal :: proc(t: ^thread.Thread) {
    ctx := cast(^BlurWorkerContext)t.data
    horizontal_gaussian_blur(ctx.src, ctx.dst, ctx.kernel, ctx.radius, ctx.start_y, ctx.end_y)
}

worker_horizontal_transposed :: proc(t: ^thread.Thread) {
    ctx := cast(^BlurWorkerContext)t.data
    horizontal_gaussian_blur(ctx.src_transposed, ctx.dst_transposed, ctx.kernel, ctx.radius, ctx.start_y, ctx.end_y)
}

gaussian_blur :: proc(src: ^Image, dst: ^Image, radius: int, num_workers: int) {
    // Generate Gaussian kernel
    kernel := generate_gaussian_kernel(radius)
    defer delete(kernel)

    // Allocate temporary buffers
    temp := Image{
        data = make([]u8, src.width * src.height * src.channels),
        width = src.width,
        height = src.height,
        channels = src.channels,
    }
    defer delete(temp.data)

    // Pre-transpose source for vertical pass
    src_transposed := Image{
        data = make([]u8, src.width * src.height * src.channels),
        width = src.height,
        height = src.width,
        channels = src.channels,
    }
    defer delete(src_transposed.data)

    // Transposed destination
    dst_transposed := Image{
        data = make([]u8, src.width * src.height * src.channels),
        width = src.height,
        height = src.width,
        channels = src.channels,
    }
    defer delete(dst_transposed.data)

    // Phase 1: Horizontal blur
    rows_per_worker := src.height / num_workers
    workers := make([]^thread.Thread, num_workers)
    contexts := make([]BlurWorkerContext, num_workers)

    for i := 0; i < num_workers; i += 1 {
        contexts[i] = BlurWorkerContext{
            src = src,
            dst = &temp,
            kernel = kernel,
            radius = radius,
            start_y = i * rows_per_worker,
            end_y = (i == num_workers - 1) ? src.height : (i + 1) * rows_per_worker,
        }
        workers[i] = thread.create(worker_horizontal)
        workers[i].data = &contexts[i]
        thread.start(workers[i])
    }

    for i := 0; i < num_workers; i += 1 {
        thread.join(workers[i])
        thread.destroy(workers[i])
    }

    // Transpose for vertical pass
    transpose_image(&temp, &src_transposed)

    // Phase 2: Vertical blur (horizontal on transposed)
    rows_per_worker = src.width / num_workers

    for i := 0; i < num_workers; i += 1 {
        contexts[i] = BlurWorkerContext{
            src_transposed = &src_transposed,
            dst_transposed = &dst_transposed,
            kernel = kernel,
            radius = radius,
            start_y = i * rows_per_worker,
            end_y = (i == num_workers - 1) ? src.width : (i + 1) * rows_per_worker,
        }
        workers[i] = thread.create(worker_horizontal_transposed)
        workers[i].data = &contexts[i]
        thread.start(workers[i])
    }

    for i := 0; i < num_workers; i += 1 {
        thread.join(workers[i])
        thread.destroy(workers[i])
    }

    // Transpose back to original orientation
    transpose_image(&dst_transposed, dst)

    delete(workers)
    delete(contexts)
}

// load_image and save_image are defined in main.odin

blur_main_old :: proc() {
    context.logger = log.create_console_logger()
    args := os.args

    if len(args) < 2 {
        log.error("Usage: {} <input_image> [output_image] [radius] [num_workers]", args[0])
        os.exit(1)
    }

    input_path := args[1]
    output_path := args[2] if len(args) > 2 else "blurred.png"

    radius := 5
    if len(args) > 3 {
        r, ok := strconv.parse_int(args[3])
        if ok {
            radius = r
        }
    }

    num_workers := 4
    if len(args) > 4 {
        w, ok := strconv.parse_int(args[4])
        if ok {
            num_workers = w
        }
    }

    // Load image
    log.info("Loading image:", args[1])
    load_start := time.now()
    src_ptr, ok := load_image(input_path)
    if !ok {
        log.error("Failed to load image")
        os.exit(1)
    }
    defer free_image(src_ptr)
    src := src_ptr^
    load_duration := time.since(load_start)
    log.infof("Image loaded in %v", load_duration)

    log.infof("Image size: %dx%d, channels: %d", src.width, src.height, src.channels)
    log.infof("Applying Gaussian blur with radius %d using %d workers...", radius, num_workers)

    // Allocate destination
    dst := Image{
        data = make([]u8, src.width * src.height * src.channels),
        width = src.width,
        height = src.height,
        channels = src.channels,
    }
    defer delete(dst.data)

    // Apply blur
    blur_start := time.now()
    gaussian_blur(src_ptr, &dst, radius, num_workers)
    blur_duration := time.since(blur_start)
    log.infof("Blur processing completed in %v", blur_duration)

    // Save result
    log.info("Saving to:", args[2] if len(args) > 2 else "blurred.png")
    save_start := time.now()
    if !save_image(output_path, &dst) {
        log.error("Failed to save image")
        os.exit(1)
    }
    save_duration := time.since(save_start)
    log.infof("Image saved in %v", save_duration)

    total_duration := time.since(load_start)
    log.infof("Total time: %v", total_duration)
    log.info("Done!")
}
