const std = @import("std");
const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const Image = struct {
    data: []u8,
    width: usize,
    height: usize,
    channels: usize,

    fn deinit(self: *Image, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const WorkItem = struct {
    start_row: usize,
    end_row: usize,
};

fn loadImage(path: []const u8, allocator: std.mem.Allocator) !Image {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;
    
    const c_path = try allocator.dupeZ(u8, path);
    defer allocator.free(c_path);
    
    const raw_data = stb.stbi_load(c_path.ptr, &width, &height, &channels, 0);
    if (raw_data == null) {
        return error.ImageLoadFailed;
    }
    defer stb.stbi_image_free(raw_data);
    
    const size = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * @as(usize, @intCast(channels));
    const data = try allocator.alloc(u8, size);
    @memcpy(data, raw_data[0..size]);
    
    return Image{
        .data = data,
        .width = @intCast(width),
        .height = @intCast(height),
        .channels = @intCast(channels),
    };
}

fn saveImage(image: *const Image, path: []const u8, allocator: std.mem.Allocator) !void {
    const c_path = try allocator.dupeZ(u8, path);
    defer allocator.free(c_path);
    
    const result = stb.stbi_write_png(
        c_path.ptr,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.channels),
        image.data.ptr,
        @intCast(image.width * image.channels),
    );
    
    if (result == 0) {
        return error.ImageSaveFailed;
    }
}

fn generateGaussianKernel(radius: usize, allocator: std.mem.Allocator) ![]f32 {
    const size = 2 * radius + 1;
    var kernel = try allocator.alloc(f32, size);
    
    const sigma = @as(f32, @floatFromInt(radius)) / 3.0;
    const two_sigma_sq = 2.0 * sigma * sigma;
    var sum: f32 = 0.0;
    
    for (0..size) |i| {
        const x = @as(f32, @floatFromInt(i)) - @as(f32, @floatFromInt(radius));
        kernel[i] = @exp(-(x * x) / two_sigma_sq);
        sum += kernel[i];
    }
    
    // Normalize
    for (kernel) |*k| {
        k.* /= sum;
    }
    
    return kernel;
}

fn blurHorizontal(
    src: []const u8,
    dst: []u8,
    width: usize,
    height: usize,
    channels: usize,
    kernel: []const f32,
    radius: usize,
    start_row: usize,
    end_row: usize,
) void {
    _ = height; // Not used but kept for API consistency
    const kernel_size = kernel.len;
    
    for (start_row..end_row) |y| {
        for (0..width) |x| {
            for (0..channels) |ch| {
                var sum: f32 = 0.0;
                var weight_sum: f32 = 0.0;
                
                for (0..kernel_size) |k| {
                    const src_x_signed = @as(i32, @intCast(x)) + @as(i32, @intCast(k)) - @as(i32, @intCast(radius));
                    if (src_x_signed >= 0 and src_x_signed < @as(i32, @intCast(width))) {
                        const src_x = @as(usize, @intCast(src_x_signed));
                        const idx = (y * width + src_x) * channels + ch;
                        sum += @as(f32, @floatFromInt(src[idx])) * kernel[k];
                        weight_sum += kernel[k];
                    }
                }
                
                const dst_idx = (y * width + x) * channels + ch;
                dst[dst_idx] = @intFromFloat(@round(sum / weight_sum));
            }
        }
    }
}

fn transpose(src: []const u8, dst: []u8, width: usize, height: usize, channels: usize) void {
    for (0..height) |y| {
        for (0..width) |x| {
            for (0..channels) |ch| {
                const src_idx = (y * width + x) * channels + ch;
                const dst_idx = (x * height + y) * channels + ch;
                dst[dst_idx] = src[src_idx];
            }
        }
    }
}

fn workerThread(
    id: usize,
    src: []const u8,
    dst: []u8,
    width: usize,
    height: usize,
    channels: usize,
    kernel: []const f32,
    radius: usize,
    work_items: []const WorkItem,
    barrier: *std.Thread.ResetEvent,
    done_count: *std.atomic.Value(usize),
    total_workers: usize,
) void {
    _ = id;
    
    // Process assigned work items
    for (work_items) |item| {
        blurHorizontal(src, dst, width, height, channels, kernel, radius, item.start_row, item.end_row);
    }
    
    // Signal completion
    const count = done_count.fetchAdd(1, .monotonic);
    if (count + 1 == total_workers) {
        barrier.set();
    }
}

fn gaussianBlur(image: *Image, radius: usize, workers: usize, allocator: std.mem.Allocator) !void {
    const kernel = try generateGaussianKernel(radius, allocator);
    defer allocator.free(kernel);
    
    // Allocate intermediate buffers
    const size = image.data.len;
    const temp1 = try allocator.alloc(u8, size);
    defer allocator.free(temp1);
    const temp2 = try allocator.alloc(u8, size);
    defer allocator.free(temp2);
    
    // Distribute work among threads
    const rows_per_worker = (image.height + workers - 1) / workers;
    var work_items = try allocator.alloc([]WorkItem, workers);
    defer {
        for (work_items) |items| {
            allocator.free(items);
        }
        allocator.free(work_items);
    }
    
    // Create work items for each worker
    for (0..workers) |i| {
        const start_row = i * rows_per_worker;
        const end_row = @min(start_row + rows_per_worker, image.height);
        
        if (start_row < image.height) {
            work_items[i] = try allocator.alloc(WorkItem, 1);
            work_items[i][0] = WorkItem{
                .start_row = start_row,
                .end_row = end_row,
            };
        } else {
            work_items[i] = try allocator.alloc(WorkItem, 0);
        }
    }
    
    // Create threads and synchronization primitives
    var threads = try allocator.alloc(std.Thread, workers);
    defer allocator.free(threads);
    
    var barrier = std.Thread.ResetEvent{};
    var done_count = std.atomic.Value(usize).init(0);
    
    // Phase 1: Horizontal blur
    for (0..workers) |i| {
        threads[i] = try std.Thread.spawn(.{}, workerThread, .{
            i, image.data, temp1, image.width, image.height, image.channels,
            kernel, radius, work_items[i], &barrier, &done_count, workers,
        });
    }
    
    // Wait for all threads to complete
    barrier.wait();
    for (threads) |thread| {
        thread.join();
    }
    
    // Transpose for cache-friendly vertical blur
    transpose(temp1, temp2, image.width, image.height, image.channels);
    
    // Update work items for transposed dimensions
    const transposed_rows_per_worker = (image.width + workers - 1) / workers;
    for (0..workers) |i| {
        const start_row = i * transposed_rows_per_worker;
        const end_row = @min(start_row + transposed_rows_per_worker, image.width);
        
        allocator.free(work_items[i]);
        if (start_row < image.width) {
            work_items[i] = try allocator.alloc(WorkItem, 1);
            work_items[i][0] = WorkItem{
                .start_row = start_row,
                .end_row = end_row,
            };
        } else {
            work_items[i] = try allocator.alloc(WorkItem, 0);
        }
    }
    
    // Phase 2: Vertical blur (horizontal on transposed)
    barrier.reset();
    done_count.store(0, .monotonic);
    
    for (0..workers) |i| {
        threads[i] = try std.Thread.spawn(.{}, workerThread, .{
            i, temp2, temp1, image.height, image.width, image.channels,
            kernel, radius, work_items[i], &barrier, &done_count, workers,
        });
    }
    
    barrier.wait();
    for (threads) |thread| {
        thread.join();
    }
    
    // Transpose back
    transpose(temp1, image.data, image.height, image.width, image.channels);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len != 5) {
        std.debug.print("Usage: {s} <input_image> <output_image> <radius> <workers>\n", .{args[0]});
        std.process.exit(1);
    }
    
    const input_path = args[1];
    const output_path = args[2];
    const radius = try std.fmt.parseInt(usize, args[3], 10);
    const workers = try std.fmt.parseInt(usize, args[4], 10);
    
    // Load image
    const start_load = std.time.milliTimestamp();
    var image = try loadImage(input_path, allocator);
    defer image.deinit(allocator);
    const load_time = std.time.milliTimestamp() - start_load;
    
    std.debug.print("Image loaded: {}x{} pixels, {} channels\n", .{ image.width, image.height, image.channels });
    std.debug.print("Load time: {}ms\n", .{load_time});
    
    // Apply blur
    const start_blur = std.time.milliTimestamp();
    try gaussianBlur(&image, radius, workers, allocator);
    const blur_time = std.time.milliTimestamp() - start_blur;
    
    std.debug.print("Blur time: {}ms\n", .{blur_time});
    
    // Save image
    const start_save = std.time.milliTimestamp();
    try saveImage(&image, output_path, allocator);
    const save_time = std.time.milliTimestamp() - start_save;
    
    std.debug.print("Save time: {}ms\n", .{save_time});
    
    const total_time = load_time + blur_time + save_time;
    std.debug.print("Total time: {}ms\n", .{total_time});
}