package main

import "base:intrinsics"
import "core:log"
import "core:os"
import "core:strconv"
import "core:thread"
import "core:sync"
import "core:time"
import "core:math"
import "core:simd"
import stbi "vendor:stb/image"
import "core:strings"
import "core:mem"

Image :: struct {
    data: []u8,
    width: int,
    height: int,
    channels: int,
}

WorkerContext :: struct {
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
            if src.channels == 4 {
                dst.data[dst_idx + 3] = src.data[src_idx + 3]
            }
        }
    }
}

// SIMD width - 8 allows processing 8 pixels at once
SIMD_WIDTH :: 8

// Horizontal Gaussian blur for 4-channel images with SIMD optimization
horizontal_gaussian_blur_simd_4ch :: proc(src: ^Image, dst: ^Image, kernel: []f32, radius: int, start_y: int, end_y: int) {
    for y := start_y; y < end_y; y += 1 {
        x := 0

        // Process SIMD_WIDTH pixels at a time
        for ; x + SIMD_WIDTH - 1 < src.width; x += SIMD_WIDTH {
            // Accumulators for SIMD_WIDTH pixels (4 channels each)
            r_sums := #simd[SIMD_WIDTH]f32{0, 0, 0, 0, 0, 0, 0, 0}
            g_sums := #simd[SIMD_WIDTH]f32{0, 0, 0, 0, 0, 0, 0, 0}
            b_sums := #simd[SIMD_WIDTH]f32{0, 0, 0, 0, 0, 0, 0, 0}
            a_sums := #simd[SIMD_WIDTH]f32{0, 0, 0, 0, 0, 0, 0, 0}

            // Apply Gaussian kernel
            for k := -radius; k <= radius; k += 1 {
                weight := kernel[k + radius]

                // Build arrays for SIMD loading
                r_arr : [SIMD_WIDTH]f32
                g_arr : [SIMD_WIDTH]f32
                b_arr : [SIMD_WIDTH]f32
                a_arr : [SIMD_WIDTH]f32
                
                // Load SIMD_WIDTH pixels into arrays
                for px := 0; px < SIMD_WIDTH; px += 1 {
                    sx := x + px + k
                    // Clamp to bounds
                    if sx < 0 {
                        sx = 0
                    } else if sx >= src.width {
                        sx = src.width - 1
                    }
                    
                    idx := (y * src.width + sx) * 4  // 4 channels
                    r_arr[px] = f32(src.data[idx])
                    g_arr[px] = f32(src.data[idx + 1])
                    b_arr[px] = f32(src.data[idx + 2])
                    a_arr[px] = f32(src.data[idx + 3])
                }
                
                // Cast arrays to SIMD vectors
                r_vec := (cast(^#simd[SIMD_WIDTH]f32)&r_arr[0])^
                g_vec := (cast(^#simd[SIMD_WIDTH]f32)&g_arr[0])^
                b_vec := (cast(^#simd[SIMD_WIDTH]f32)&b_arr[0])^
                a_vec := (cast(^#simd[SIMD_WIDTH]f32)&a_arr[0])^

                // Create weight vector (all elements have same weight)
                weight_vec := #simd[SIMD_WIDTH]f32{weight, weight, weight, weight, weight, weight, weight, weight}

                // Perform SIMD operations
                r_sums += r_vec * weight_vec
                g_sums += g_vec * weight_vec
                b_sums += b_vec * weight_vec
                a_sums += a_vec * weight_vec
            }

            // Write results
            for px := 0; px < SIMD_WIDTH; px += 1 {
                dst_idx := (y * dst.width + x + px) * 4  // 4 channels
                dst.data[dst_idx] = u8(math.round_f32(simd.extract(r_sums, px)))
                dst.data[dst_idx + 1] = u8(math.round_f32(simd.extract(g_sums, px)))
                dst.data[dst_idx + 2] = u8(math.round_f32(simd.extract(b_sums, px)))
                dst.data[dst_idx + 3] = u8(math.round_f32(simd.extract(a_sums, px)))
            }
        }

        // Handle remaining pixels
        for ; x < src.width; x += 1 {
            r_sum, g_sum, b_sum, a_sum: f32 = 0, 0, 0, 0

            // Apply Gaussian kernel
            for k := -radius; k <= radius; k += 1 {
                sx := x + k
                // Clamp to bounds
                if sx < 0 {
                    sx = 0
                } else if sx >= src.width {
                    sx = src.width - 1
                }

                idx := (y * src.width + sx) * 4  // 4 channels
                weight := kernel[k + radius]

                r_sum += f32(src.data[idx]) * weight
                g_sum += f32(src.data[idx + 1]) * weight
                b_sum += f32(src.data[idx + 2]) * weight
                a_sum += f32(src.data[idx + 3]) * weight
            }

            // Write result
            dst_idx := (y * dst.width + x) * 4  // 4 channels
            dst.data[dst_idx] = u8(math.round_f32(r_sum))
            dst.data[dst_idx + 1] = u8(math.round_f32(g_sum))
            dst.data[dst_idx + 2] = u8(math.round_f32(b_sum))
            dst.data[dst_idx + 3] = u8(math.round_f32(a_sum))
        }
    }
}

// Dispatch to appropriate SIMD function based on channels
horizontal_gaussian_blur_simd :: proc(src: ^Image, dst: ^Image, kernel: []f32, radius: int, start_y: int, end_y: int) {
    // For now, we only support 4-channel images with SIMD
    // You can add a 3-channel version if needed
    if src.channels == 4 {
        horizontal_gaussian_blur_simd_4ch(src, dst, kernel, radius, start_y, end_y)
    } else {
        // Fallback to non-SIMD for 3-channel images
        // (not implemented here, but you could add it)
        horizontal_gaussian_blur_simd_4ch(src, dst, kernel, radius, start_y, end_y)
    }
}

worker_horizontal :: proc(t: ^thread.Thread) {
    ctx := cast(^WorkerContext)t.data
    horizontal_gaussian_blur_simd(ctx.src, ctx.dst, ctx.kernel, ctx.radius, ctx.start_y, ctx.end_y)
}

worker_horizontal_transposed :: proc(t: ^thread.Thread) {
    ctx := cast(^WorkerContext)t.data
    horizontal_gaussian_blur_simd(ctx.src_transposed, ctx.dst_transposed, ctx.kernel, ctx.radius, ctx.start_y, ctx.end_y)
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
    contexts := make([]WorkerContext, num_workers)

    for i := 0; i < num_workers; i += 1 {
        contexts[i] = WorkerContext{
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
        contexts[i] = WorkerContext{
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

load_image :: proc(filename: cstring) -> (Image, bool) {
    width, height, channels: i32
    data := stbi.load(filename, &width, &height, &channels, 0)

    if data == nil {
        return Image{}, false
    }

    img := Image{
        width = int(width),
        height = int(height),
        channels = int(channels),
    }

    // Copy data to our slice
    data_size := img.width * img.height * img.channels
    img.data = make([]u8, data_size)
    mem.copy(&img.data[0], data, data_size)

    stbi.image_free(data)

    return img, true
}

save_image :: proc(filename: cstring, img: ^Image) -> bool {
    result := stbi.write_png(filename, i32(img.width), i32(img.height), i32(img.channels), &img.data[0], i32(img.width * img.channels))
    return result != 0
}

main :: proc() {
    context.logger = log.create_console_logger()
    args := os.args

    if len(args) < 2 {
        log.error("Usage: {} <input_image> [output_image] [radius] [num_workers]", args[0])
        os.exit(1)
    }

    input_path := strings.clone_to_cstring(args[1])
    defer delete(input_path)

    output_path := strings.clone_to_cstring(args[2] if len(args) > 2 else "blurred.png")
    defer delete(output_path)

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
    src, ok := load_image(input_path)
    if !ok {
        log.error("Failed to load image")
        os.exit(1)
    }
    defer delete(src.data)
    load_duration := time.since(load_start)
    log.infof("Image loaded in %v", load_duration)

    log.infof("Image size: %dx%d, channels: %d", src.width, src.height, src.channels)
    log.infof("Applying Gaussian blur with radius %d using %d workers (SIMD width: %d)...", radius, num_workers, SIMD_WIDTH)

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
    gaussian_blur(&src, &dst, radius, num_workers)
    blur_duration := time.since(blur_start)
    log.infof("Blur processing completed in %v (includes transpose operations)", blur_duration)

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
