package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import "core:thread"
import "core:sync"
import "core:math"
import "core:slice"
import "core:strings"
import stbi "vendor:stb/image"

// Image struct is defined in main.odin

IntegralImage :: struct {
    sum:    []f32,
    sum_sq: []f32,
    width:  int,
    height: int,
}

KuwaharaWorkerContext :: struct {
    src:       ^Image,
    dst:       ^Image,
    integral:  ^IntegralImage,
    radius:    int,
    start_row: int,
    end_row:   int,
}

create_integral_image :: proc(width, height: int) -> ^IntegralImage {
    size := (width + 1) * (height + 1) * 3
    integral := new(IntegralImage)
    integral.sum = make([]f32, size)
    integral.sum_sq = make([]f32, size)
    integral.width = width
    integral.height = height
    return integral
}

destroy_integral_image :: proc(integral: ^IntegralImage) {
    delete(integral.sum)
    delete(integral.sum_sq)
    free(integral)
}

build_integral_images :: proc(src: ^Image, integral: ^IntegralImage) {
    w := src.width
    h := src.height
    iw := integral.width + 1

    slice.zero(integral.sum)
    slice.zero(integral.sum_sq)

    for y in 1..=h {
        for x in 1..=w {
            for ch in 0..<3 {
                src_idx := ((y - 1) * w + (x - 1)) * 4 + ch
                val := f32(src.data[src_idx])

                idx := (y * iw + x) * 3 + ch
                idx_up := ((y - 1) * iw + x) * 3 + ch
                idx_left := (y * iw + (x - 1)) * 3 + ch
                idx_diag := ((y - 1) * iw + (x - 1)) * 3 + ch

                integral.sum[idx] = val + 
                    integral.sum[idx_up] + 
                    integral.sum[idx_left] - 
                    integral.sum[idx_diag]

                integral.sum_sq[idx] = val * val + 
                    integral.sum_sq[idx_up] + 
                    integral.sum_sq[idx_left] - 
                    integral.sum_sq[idx_diag]
            }
        }
    }
}

get_region_stats :: proc(
    integral: ^IntegralImage,
    x1_in, y1_in, x2_in, y2_in: int,
) -> (mean: [3]f32, variance: [3]f32) {
    iw := integral.width + 1

    x1 := max(0, x1_in)
    y1 := max(0, y1_in)
    x2 := min(integral.width - 1, x2_in)
    y2 := min(integral.height - 1, y2_in)

    x1 += 1; y1 += 1; x2 += 1; y2 += 1

    area := f32((x2 - x1 + 1) * (y2 - y1 + 1))

    if area > 0 {
        for ch in 0..<3 {
            idx_br := (y2 * iw + x2) * 3 + ch
            idx_bl := (y2 * iw + x1 - 1) * 3 + ch
            idx_tr := ((y1 - 1) * iw + x2) * 3 + ch
            idx_tl := ((y1 - 1) * iw + x1 - 1) * 3 + ch

            sum := integral.sum[idx_br] - integral.sum[idx_bl] - 
                   integral.sum[idx_tr] + integral.sum[idx_tl]
            sum_sq := integral.sum_sq[idx_br] - integral.sum_sq[idx_bl] - 
                      integral.sum_sq[idx_tr] + integral.sum_sq[idx_tl]

            mean[ch] = sum / area
            variance[ch] = (sum_sq / area) - (mean[ch] * mean[ch])
            if variance[ch] < 0 do variance[ch] = 0
        }
    }

    return mean, variance
}

kuwahara_filter_pixel :: proc(
    src: ^Image,
    dst: ^Image,
    integral: ^IntegralImage,
    x, y: int,
    radius: int,
) {
    min_variance: f32 = math.F32_MAX
    best_mean: [3]f32

    quadrants := [4][4]int{
        {x - radius, y - radius, x, y},
        {x, y - radius, x + radius, y},
        {x - radius, y, x, y + radius},
        {x, y, x + radius, y + radius},
    }

    for quad in quadrants {
        mean, variance := get_region_stats(integral, quad[0], quad[1], quad[2], quad[3])
        total_variance := variance[0] + variance[1] + variance[2]

        if total_variance < min_variance {
            min_variance = total_variance
            best_mean = mean
        }
    }

    dst_idx := (y * dst.width + x) * 4
    dst.data[dst_idx] = u8(clamp(best_mean[0], 0, 255))
    dst.data[dst_idx + 1] = u8(clamp(best_mean[1], 0, 255))
    dst.data[dst_idx + 2] = u8(clamp(best_mean[2], 0, 255))
    dst.data[dst_idx + 3] = src.data[(y * src.width + x) * 4 + 3]
}

kuwahara_worker :: proc(task: thread.Task) {
    ctx := cast(^KuwaharaWorkerContext)task.data

    for y in ctx.start_row..<ctx.end_row {
        for x in 0..<ctx.src.width {
            kuwahara_filter_pixel(ctx.src, ctx.dst, ctx.integral, x, y, ctx.radius)
        }
    }
}

apply_kuwahara_filter :: proc(src: ^Image, dst: ^Image, radius: int, num_workers: int) {
    integral := create_integral_image(src.width, src.height)
    defer destroy_integral_image(integral)

    start_time := time.now()
    build_integral_images(src, integral)
    sat_time := time.diff(start_time, time.now())
    fmt.printf("SAT build time: %.2fms\n", time.duration_milliseconds(sat_time))

    contexts := make([]KuwaharaWorkerContext, num_workers)
    defer delete(contexts)

    pool: thread.Pool
    thread.pool_init(&pool, context.allocator, num_workers)
    defer thread.pool_destroy(&pool)

    rows_per_worker := src.height / num_workers

    for i in 0..<num_workers {
        contexts[i] = KuwaharaWorkerContext{
            src = src,
            dst = dst,
            integral = integral,
            radius = radius,
            start_row = i * rows_per_worker,
            end_row = (i == num_workers - 1) ? src.height : (i + 1) * rows_per_worker,
        }

        thread.pool_add_task(&pool, context.allocator, kuwahara_worker, &contexts[i])
    }

    thread.pool_start(&pool)
    thread.pool_finish(&pool)
}

// load_image, save_image, and free_image are defined in main.odin

kuwahara_main_old :: proc() {
    if len(os.args) != 5 {
        fmt.eprintf("Usage: %s <input_image> <output_image> <radius> <workers>\n", os.args[0])
        os.exit(1)
    }

    input_path := os.args[1]
    output_path := os.args[2]
    radius := strconv.atoi(os.args[3])
    num_workers := strconv.atoi(os.args[4])

    start_time := time.now()
    src, ok := load_image(input_path)
    if !ok {
        fmt.eprintf("Failed to load image: %s\n", input_path)
        os.exit(1)
    }
    defer free_image(src)
    load_time := time.diff(start_time, time.now())

    fmt.printf("Image loaded: %dx%d pixels, %d channels\n", src.width, src.height, src.channels)
    fmt.printf("Load time: %dms\n", time.duration_milliseconds(load_time))

    dst := new(Image)
    dst.width = src.width
    dst.height = src.height
    dst.channels = src.channels
    dst.data = make([]u8, src.width * src.height * 4)
    defer delete(dst.data)
    defer free(dst)

    start_time = time.now()
    apply_kuwahara_filter(src, dst, radius, num_workers)
    filter_time := time.diff(start_time, time.now())
    fmt.printf("Kuwahara filter time: %dms\n", time.duration_milliseconds(filter_time))

    start_time = time.now()
    if !save_image(output_path, dst) {
        fmt.eprintf("Failed to save image: %s\n", output_path)
        os.exit(1)
    }
    save_time := time.diff(start_time, time.now())

    fmt.printf("Save time: %dms\n", time.duration_milliseconds(save_time))
    fmt.printf("Total time: %dms\n", 
        time.duration_milliseconds(load_time) + 
        time.duration_milliseconds(filter_time) + 
        time.duration_milliseconds(save_time))
}