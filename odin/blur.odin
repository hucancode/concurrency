package main

import "core:log"
import "core:os"
import "core:strconv"
import "core:thread"
import "core:sync"
import "core:time"
import stbi "vendor:stb/image"
import "core:strings"

Image :: struct {
    data: []u8,
    width: int,
    height: int,
    channels: int,
}

WorkerContext :: struct {
    src: ^Image,
    dst: ^Image,
    radius: int,
    start_y: int,
    end_y: int,
}

box_blur_worker :: proc(ctx: ^WorkerContext) {
    // Process the assigned region directly without mutex
    // Each thread writes to its own region, no overlap
    for y := ctx.start_y; y < ctx.end_y; y += 1 {
        for x := 0; x < ctx.src.width; x += 1 {
            r_sum, g_sum, b_sum, a_sum: u32 = 0, 0, 0, 0
            
            // Calculate actual bounds to eliminate branch in inner loop
            y_start := max(0, y - ctx.radius)
            y_end := min(ctx.src.height - 1, y + ctx.radius)
            x_start := max(0, x - ctx.radius)
            x_end := min(ctx.src.width - 1, x + ctx.radius)
            
            // Pre-calculate count
            count := u32((y_end - y_start + 1) * (x_end - x_start + 1))
            
            // Now we can iterate without boundary checks
            for ny := y_start; ny <= y_end; ny += 1 {
                for nx := x_start; nx <= x_end; nx += 1 {
                    src_idx := (ny * ctx.src.width + nx) * ctx.src.channels
                    r_sum += u32(ctx.src.data[src_idx])
                    g_sum += u32(ctx.src.data[src_idx + 1])
                    b_sum += u32(ctx.src.data[src_idx + 2])
                    if ctx.src.channels == 4 {
                        a_sum += u32(ctx.src.data[src_idx + 3])
                    } else {
                        a_sum += 255
                    }
                }
            }
            
            // Write directly to destination - no mutex needed as regions don't overlap
            dst_idx := (y * ctx.dst.width + x) * ctx.dst.channels
            ctx.dst.data[dst_idx] = u8(r_sum / count)
            ctx.dst.data[dst_idx + 1] = u8(g_sum / count)
            ctx.dst.data[dst_idx + 2] = u8(b_sum / count)
            if ctx.dst.channels == 4 {
                ctx.dst.data[dst_idx + 3] = u8(a_sum / count)
            }
        }
    }
}

box_blur_threads :: proc(src: ^Image, radius: int, num_threads: int) -> Image {
    dst := Image{
        data = make([]u8, len(src.data)),
        width = src.width,
        height = src.height,
        channels = src.channels,
    }
    
    // Pre-calculate work distribution
    rows_per_thread := src.height / num_threads
    
    // Create worker contexts with pre-assigned regions
    contexts := make([]WorkerContext, num_threads)
    for i := 0; i < num_threads; i += 1 {
        contexts[i] = WorkerContext{
            src = src,
            dst = &dst,
            radius = radius,
            start_y = i * rows_per_thread,
            end_y = (i == num_threads - 1) ? src.height : (i + 1) * rows_per_thread,
        }
    }
    
    // Create and start threads with their assigned work
    threads := make([dynamic]^thread.Thread, 0, num_threads)
    defer delete(threads)
    
    for i := 0; i < num_threads; i += 1 {
        t := thread.create_and_start_with_poly_data(&contexts[i], box_blur_worker)
        append(&threads, t)
    }
    
    // Wait for all threads to complete
    for t in threads {
        thread.join(t)
        free(t)
    }
    
    delete(contexts)
    
    return dst
}

load_image :: proc(path: string) -> (Image, bool) {
    width, height, channels: i32
    data := stbi.load(strings.clone_to_cstring(path), &width, &height, &channels, 0)
    
    if data == nil {
        return Image{}, false
    }
    
    img := Image{
        width = int(width),
        height = int(height),
        channels = int(channels),
    }
    
    // Copy data to Odin slice
    data_size := int(width * height * channels)
    img.data = make([]u8, data_size)
    for i := 0; i < data_size; i += 1 {
        img.data[i] = data[i]
    }
    
    stbi.image_free(data)
    return img, true
}

save_image :: proc(img: ^Image, path: string) -> bool {
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    
    result: i32
    if strings.has_suffix(path, ".png") {
        result = stbi.write_png(cpath, i32(img.width), i32(img.height), i32(img.channels), 
                                raw_data(img.data), i32(img.width * img.channels))
    } else if strings.has_suffix(path, ".jpg") || strings.has_suffix(path, ".jpeg") {
        result = stbi.write_jpg(cpath, i32(img.width), i32(img.height), i32(img.channels), 
                                raw_data(img.data), 95)
    } else {
        return false
    }
    
    return result != 0
}

main :: proc() {
    // Create logging context
    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)
    
    args := os.args
    
    if len(args) < 2 {
        log.errorf("Usage: %s <input_image> [output_image] [radius] [threads]\n", args[0])
        os.exit(1)
    }
    
    input_path := args[1]
    output_path := args[2] if len(args) > 2 else "blurred.png"
    radius := strconv.atoi(args[3]) if len(args) > 3 else 5
    num_threads := strconv.atoi(args[4]) if len(args) > 4 else 4
    
    log.infof("Loading image: %s\n", input_path)
    img, ok := load_image(input_path)
    if !ok {
        log.error("Failed to load image")
        os.exit(1)
    }
    defer delete(img.data)
    
    log.infof("Applying box blur with radius %d using %d threads...\n", radius, num_threads)
    start := time.now()
    
    blurred := box_blur_threads(&img, radius, num_threads)
    defer delete(blurred.data)
    
    duration := time.since(start)
    log.infof("Blur completed in %v\n", duration)
    
    log.infof("Saving to: %s\n", output_path)
    if !save_image(&blurred, output_path) {
        log.error("Failed to save image")
        os.exit(1)
    }
    
    log.info("Done!")
}