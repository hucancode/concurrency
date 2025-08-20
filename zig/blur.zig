const std = @import("std");
const main = @import("main.zig");
const Image = main.Image;

const WorkItem = struct {
    start_row: usize,
    end_row: usize,
};


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

// SIMD width for processing multiple pixels at once
const SIMD_WIDTH = 16;
const SIMD_BYTES = SIMD_WIDTH * 4;

fn blurHorizontalSIMD(
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
    _ = height; // Unused but kept for API consistency
    _ = channels; // Always 4
    const kernel_size = kernel.len;

    // Create masks for channel extraction once
    var mask: @Vector(SIMD_BYTES, bool) = @splat(false);
    inline for (0..SIMD_WIDTH) |i| {
        mask[i * 4] = true;
    }

    for (start_row..end_row) |y| {
        for (0..width) |x| {
            var r_sum: f32 = 0.0;
            var g_sum: f32 = 0.0;
            var b_sum: f32 = 0.0;
            var a_sum: f32 = 0.0;

            // Process kernel in chunks using SIMD
            var k: usize = 0;
            while (k + SIMD_WIDTH <= kernel_size) : (k += SIMD_WIDTH) {
                const base_x_signed = @as(i32, @intCast(x)) - @as(i32, @intCast(radius)) + @as(i32, @intCast(k));

                // Check if all pixels in this chunk are within bounds for fast path
                if (base_x_signed >= 0 and base_x_signed + SIMD_WIDTH <= @as(i32, @intCast(width))) {
                    // Fast path: all pixels within bounds, use pure SIMD
                    const base_x = @as(usize, @intCast(base_x_signed));
                    const base_idx = (y * width + base_x) * 4;
                    const weights: @Vector(SIMD_WIDTH, f32) = kernel[k..][0..SIMD_WIDTH].*;
                    const pixel_ptr = @as([*]const @Vector(SIMD_BYTES, u8), @ptrCast(@alignCast(&src[base_idx])));
                    const pixel_data = pixel_ptr[0];
                    const zero: @Vector(SIMD_BYTES, u8) = @splat(0);
                    // Extract R channel (bytes 0, 4, 8, 12, ...)
                    const r_masked = @select(u8, mask, pixel_data, zero);
                    // Extract G channel (bytes 1, 5, 9, 13, ...) by shifting pixel_data
                    const g_data = @as(@Vector(SIMD_BYTES, u8), @bitCast(@as(@Vector(SIMD_WIDTH, u32), @bitCast(pixel_data)) >> @splat(8)));
                    const g_masked = @select(u8, mask, g_data, zero);
                    // Extract B channel (bytes 2, 6, 10, 14, ...) by shifting pixel_data
                    const b_data = @as(@Vector(SIMD_BYTES, u8), @bitCast(@as(@Vector(SIMD_WIDTH, u32), @bitCast(pixel_data)) >> @splat(16)));
                    const b_masked = @select(u8, mask, b_data, zero);
                    // Extract A channel (bytes 3, 7, 11, 15, ...) by shifting pixel_data
                    const a_data = @as(@Vector(SIMD_BYTES, u8), @bitCast(@as(@Vector(SIMD_WIDTH, u32), @bitCast(pixel_data)) >> @splat(24)));
                    const a_masked = @select(u8, mask, a_data, zero);
                    // Transmute masked bytes to u32 (4 bytes per u32), then cast to f32
                    const r_u32 = @as(@Vector(SIMD_WIDTH, u32), @bitCast(r_masked));
                    const g_u32 = @as(@Vector(SIMD_WIDTH, u32), @bitCast(g_masked));
                    const b_u32 = @as(@Vector(SIMD_WIDTH, u32), @bitCast(b_masked));
                    const a_u32 = @as(@Vector(SIMD_WIDTH, u32), @bitCast(a_masked));
                    const r_vec = @as(@Vector(SIMD_WIDTH, f32), @floatFromInt(r_u32));
                    const g_vec = @as(@Vector(SIMD_WIDTH, f32), @floatFromInt(g_u32));
                    const b_vec = @as(@Vector(SIMD_WIDTH, f32), @floatFromInt(b_u32));
                    const a_vec = @as(@Vector(SIMD_WIDTH, f32), @floatFromInt(a_u32));
                    // Multiply by weights and accumulate
                    r_sum += @reduce(.Add, r_vec * weights);
                    g_sum += @reduce(.Add, g_vec * weights);
                    b_sum += @reduce(.Add, b_vec * weights);
                    a_sum += @reduce(.Add, a_vec * weights);
                } else {
                    // Slow path: need boundary checking - fall back to scalar for simplicity
                    for (0..SIMD_WIDTH) |i| {
                        const px_signed = base_x_signed + @as(i32, @intCast(i));
                        const px = if (px_signed < 0) 0 else if (px_signed >= @as(i32, @intCast(width))) width - 1 else @as(usize, @intCast(px_signed));
                        const idx = (y * width + px) * 4;
                        const weight = kernel[k + i];
                        // Only accumulate if within valid range
                        if (px_signed >= 0 and px_signed < @as(i32, @intCast(width))) {
                            r_sum += @as(f32, @floatFromInt(src[idx])) * weight;
                            g_sum += @as(f32, @floatFromInt(src[idx + 1])) * weight;
                            b_sum += @as(f32, @floatFromInt(src[idx + 2])) * weight;
                            a_sum += @as(f32, @floatFromInt(src[idx + 3])) * weight;
                        }
                    }
                }
            }

            // Handle remaining kernel elements
            while (k < kernel_size) : (k += 1) {
                const px_signed = @as(i32, @intCast(x)) - @as(i32, @intCast(radius)) + @as(i32, @intCast(k));
                const px = if (px_signed < 0) 0 else if (px_signed >= @as(i32, @intCast(width))) width - 1 else @as(usize, @intCast(px_signed));

                const idx = (y * width + px) * 4;
                const weight = kernel[k];
                r_sum += @as(f32, @floatFromInt(src[idx])) * weight;
                g_sum += @as(f32, @floatFromInt(src[idx + 1])) * weight;
                b_sum += @as(f32, @floatFromInt(src[idx + 2])) * weight;
                a_sum += @as(f32, @floatFromInt(src[idx + 3])) * weight;
            }

            // Write result
            const dst_idx = (y * width + x) * 4;
            dst[dst_idx] = @intFromFloat(@round(r_sum));
            dst[dst_idx + 1] = @intFromFloat(@round(g_sum));
            dst[dst_idx + 2] = @intFromFloat(@round(b_sum));
            dst[dst_idx + 3] = @intFromFloat(@round(a_sum));
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
        blurHorizontalSIMD(src, dst, width, height, channels, kernel, radius, item.start_row, item.end_row);
    }

    // Signal completion
    const count = done_count.fetchAdd(1, .monotonic);
    if (count + 1 == total_workers) {
        barrier.set();
    }
}

pub fn gaussianBlur(allocator: std.mem.Allocator, src: *const Image, dst: *Image, radius: usize, workers: usize) !void {
    // Copy src to dst to work in-place
    @memcpy(dst.data, src.data);
    
    const image = dst;
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
            i,      image.data, temp1,         image.width, image.height, image.channels,
            kernel, radius,     work_items[i], &barrier,    &done_count,  workers,
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
            i,      temp2,  temp1,         image.height, image.width, image.channels,
            kernel, radius, work_items[i], &barrier,     &done_count, workers,
        });
    }

    barrier.wait();
    for (threads) |thread| {
        thread.join();
    }

    // Transpose back
    transpose(temp1, image.data, image.height, image.width, image.channels);
}

