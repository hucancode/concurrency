package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import "core:strings"
import "core:slice"
import stbi "vendor:stb/image"

Image :: struct {
    data:     []u8,
    width:    int,
    height:   int,
    channels: int,
}

load_image :: proc(path: string) -> (^Image, bool) {
    width, height, channels: i32
    c_path := strings.clone_to_cstring(path)
    defer delete(c_path)
    data := stbi.load(c_path, &width, &height, &channels, 4)
    
    if data == nil {
        return nil, false
    }

    img := new(Image)
    img.width = int(width)
    img.height = int(height)
    img.channels = 4  // Always force 4 channels (RGBA)
    
    size := img.width * img.height * 4
    img.data = slice.from_ptr(data, size)

    return img, true
}

save_image :: proc(path: string, img: ^Image) -> bool {
    c_path := strings.clone_to_cstring(path)
    defer delete(c_path)
    result := stbi.write_png(
        c_path,
        i32(img.width),
        i32(img.height),
        i32(img.channels),
        raw_data(img.data),
        i32(img.width * img.channels),
    )
    return result != 0
}

free_image :: proc(img: ^Image) {
    if img != nil {
        if img.data != nil {
            stbi.image_free(raw_data(img.data))
        }
        free(img)
    }
}

print_usage :: proc(program: string) {
    fmt.eprintf("Usage: %s <operation> <input_image> <output_image> <radius> <workers>\n", program)
    fmt.eprintf("  operation: 'blur' or 'kuwahara'\n")
}

main :: proc() {
    if len(os.args) != 6 {
        print_usage(os.args[0])
        os.exit(1)
    }

    operation := os.args[1]
    input_path := os.args[2]
    output_path := os.args[3]
    radius := strconv.atoi(os.args[4])
    num_workers := strconv.atoi(os.args[5])

    start_time := time.now()
    src, ok := load_image(input_path)
    if !ok {
        fmt.eprintf("Failed to load image: %s\n", input_path)
        os.exit(1)
    }
    defer free_image(src)
    load_time := time.diff(start_time, time.now())

    fmt.printf("Image loaded: %dx%d pixels, %d channels\n", src.width, src.height, src.channels)
    fmt.printf("Load time: %.2fms\n", time.duration_milliseconds(load_time))

    dst_data := make([]u8, src.width * src.height * 4)
    defer delete(dst_data)
    
    dst := Image{
        width = src.width,
        height = src.height,
        channels = src.channels,
        data = dst_data,
    }

    start_time = time.now()

    if operation == "blur" {
        fmt.printf("Applying Gaussian blur with radius %d using %d workers\n", radius, num_workers)
        gaussian_blur(src, &dst, radius, num_workers)
    } else if operation == "kuwahara" {
        fmt.printf("Applying Kuwahara filter with radius %d using %d workers\n", radius, num_workers)
        apply_kuwahara_filter(src, &dst, radius, num_workers)
    } else {
        fmt.eprintf("Unknown operation: %s. Use 'blur' or 'kuwahara'\n", operation)
        os.exit(1)
    }

    filter_time := time.diff(start_time, time.now())
    fmt.printf("Filter time: %.2fms\n", time.duration_milliseconds(filter_time))

    start_time = time.now()
    if !save_image(output_path, &dst) {
        fmt.eprintf("Failed to save image: %s\n", output_path)
        os.exit(1)
    }
    save_time := time.diff(start_time, time.now())

    fmt.printf("Save time: %.2fms\n", time.duration_milliseconds(save_time))
    fmt.printf("Total time: %.2fms\n",
        time.duration_milliseconds(load_time) +
        time.duration_milliseconds(filter_time) +
        time.duration_milliseconds(save_time))
}
