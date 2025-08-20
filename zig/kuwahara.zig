const std = @import("std");
const main = @import("main.zig");
const Image = main.Image;

const IntegralImage = struct {
    sum: []f32,
    sum_sq: []f32,
    width: usize,
    height: usize,

    fn init(allocator: std.mem.Allocator, width: usize, height: usize) !IntegralImage {
        const size = (width + 1) * (height + 1) * 3;
        return IntegralImage{
            .sum = try allocator.alloc(f32, size),
            .sum_sq = try allocator.alloc(f32, size),
            .width = width,
            .height = height,
        };
    }

    fn deinit(self: *IntegralImage, allocator: std.mem.Allocator) void {
        allocator.free(self.sum);
        allocator.free(self.sum_sq);
    }
};

fn buildIntegralImages(src: *const Image, integral: *IntegralImage) void {
    const w = src.width;
    const h = src.height;
    const iw = integral.width + 1;

    @memset(integral.sum, 0);
    @memset(integral.sum_sq, 0);

    for (1..h + 1) |y| {
        for (1..w + 1) |x| {
            const vec = @Vector(4, f32);
            const src_idx = ((y - 1) * w + (x - 1)) * 4;
            
            const pixel: vec = .{
                @floatFromInt(src.data[src_idx]),
                @floatFromInt(src.data[src_idx + 1]),
                @floatFromInt(src.data[src_idx + 2]),
                0,
            };

            for (0..3) |ch| {
                const val = pixel[ch];
                const idx = (y * iw + x) * 3 + ch;
                const idx_up = ((y - 1) * iw + x) * 3 + ch;
                const idx_left = (y * iw + (x - 1)) * 3 + ch;
                const idx_diag = ((y - 1) * iw + (x - 1)) * 3 + ch;

                integral.sum[idx] = val + 
                    integral.sum[idx_up] + 
                    integral.sum[idx_left] - 
                    integral.sum[idx_diag];

                integral.sum_sq[idx] = val * val + 
                    integral.sum_sq[idx_up] + 
                    integral.sum_sq[idx_left] - 
                    integral.sum_sq[idx_diag];
            }
        }
    }
}

fn getRegionStats(
    integral: *const IntegralImage,
    x1_in: i32,
    y1_in: i32,
    x2_in: i32,
    y2_in: i32,
    mean: *[3]f32,
    variance: *[3]f32,
) void {
    const iw = integral.width + 1;

    const x1 = @max(0, x1_in);
    const y1 = @max(0, y1_in);
    const x2 = @min(@as(i32, @intCast(integral.width - 1)), x2_in);
    const y2 = @min(@as(i32, @intCast(integral.height - 1)), y2_in);

    const x1u = @as(usize, @intCast(x1 + 1));
    const y1u = @as(usize, @intCast(y1 + 1));
    const x2u = @as(usize, @intCast(x2 + 1));
    const y2u = @as(usize, @intCast(y2 + 1));

    const area = @as(f32, @floatFromInt((x2 - x1 + 1) * (y2 - y1 + 1)));

    if (area > 0) {
        const vec = @Vector(4, f32);
        var sum_vec: vec = @splat(0);
        var sum_sq_vec: vec = @splat(0);

        for (0..3) |ch| {
            const idx_br = (y2u * iw + x2u) * 3 + ch;
            const idx_bl = (y2u * iw + x1u - 1) * 3 + ch;
            const idx_tr = ((y1u - 1) * iw + x2u) * 3 + ch;
            const idx_tl = ((y1u - 1) * iw + x1u - 1) * 3 + ch;

            const sum = integral.sum[idx_br] - integral.sum[idx_bl] - 
                       integral.sum[idx_tr] + integral.sum[idx_tl];
            const sum_sq = integral.sum_sq[idx_br] - integral.sum_sq[idx_bl] - 
                          integral.sum_sq[idx_tr] + integral.sum_sq[idx_tl];

            sum_vec[ch] = sum;
            sum_sq_vec[ch] = sum_sq;
        }

        const mean_vec = sum_vec / @as(vec, @splat(area));
        const variance_vec = (sum_sq_vec / @as(vec, @splat(area))) - mean_vec * mean_vec;

        for (0..3) |ch| {
            mean[ch] = mean_vec[ch];
            variance[ch] = @max(0, variance_vec[ch]);
        }
    } else {
        @memset(mean, 0);
        @memset(variance, 0);
    }
}

fn kuwaharaFilterPixel(
    src: *const Image,
    dst: *Image,
    integral: *const IntegralImage,
    x: usize,
    y: usize,
    radius: i32,
) void {
    var min_variance: f32 = std.math.floatMax(f32);
    var best_mean = [3]f32{ 0, 0, 0 };

    const xi = @as(i32, @intCast(x));
    const yi = @as(i32, @intCast(y));

    const quadrants = [4][4]i32{
        .{ xi - radius, yi - radius, xi, yi },
        .{ xi, yi - radius, xi + radius, yi },
        .{ xi - radius, yi, xi, yi + radius },
        .{ xi, yi, xi + radius, yi + radius },
    };

    for (quadrants) |quad| {
        var mean = [3]f32{ 0, 0, 0 };
        var variance = [3]f32{ 0, 0, 0 };

        getRegionStats(integral, quad[0], quad[1], quad[2], quad[3], &mean, &variance);

        const total_variance = variance[0] + variance[1] + variance[2];

        if (total_variance < min_variance) {
            min_variance = total_variance;
            best_mean = mean;
        }
    }

    const dst_idx = (y * dst.width + x) * 4;
    const vec = @Vector(4, f32){
        best_mean[0],
        best_mean[1],
        best_mean[2],
        @floatFromInt(src.data[(y * src.width + x) * 4 + 3]),
    };

    const clamped = @min(@as(@Vector(4, f32), @splat(255)), @max(@as(@Vector(4, f32), @splat(0)), vec));
    
    dst.data[dst_idx] = @intFromFloat(clamped[0]);
    dst.data[dst_idx + 1] = @intFromFloat(clamped[1]);
    dst.data[dst_idx + 2] = @intFromFloat(clamped[2]);
    dst.data[dst_idx + 3] = @intFromFloat(clamped[3]);
}

const WorkerContext = struct {
    src: *const Image,
    dst: *Image,
    integral: *const IntegralImage,
    radius: i32,
    start_row: usize,
    end_row: usize,
};

fn kuwaharaWorker(ctx: *WorkerContext) void {
    for (ctx.start_row..ctx.end_row) |y| {
        for (0..ctx.src.width) |x| {
            kuwaharaFilterPixel(ctx.src, ctx.dst, ctx.integral, x, y, ctx.radius);
        }
    }
}

pub fn applyKuwaharaFilter(
    allocator: std.mem.Allocator,
    src: *const Image,
    dst: *Image,
    radius: i32,
    num_workers: usize,
) !void {
    var integral = try IntegralImage.init(allocator, src.width, src.height);
    defer integral.deinit(allocator);

    var timer = try std.time.Timer.start();
    buildIntegralImages(src, &integral);
    const sat_time = timer.lap();
    std.debug.print("SAT build time: {}ms\n", .{sat_time / 1_000_000});

    var contexts = try allocator.alloc(WorkerContext, num_workers);
    defer allocator.free(contexts);

    var threads = try allocator.alloc(std.Thread, num_workers);
    defer allocator.free(threads);

    const rows_per_worker = src.height / num_workers;

    for (0..num_workers) |i| {
        contexts[i] = WorkerContext{
            .src = src,
            .dst = dst,
            .integral = &integral,
            .radius = radius,
            .start_row = i * rows_per_worker,
            .end_row = if (i == num_workers - 1) src.height else (i + 1) * rows_per_worker,
        };

        threads[i] = try std.Thread.spawn(.{}, kuwaharaWorker, .{&contexts[i]});
    }

    for (threads) |thread| {
        thread.join();
    }
}