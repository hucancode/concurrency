const std = @import("std");
const c = @cImport({
    @cInclude("../stb/stb_image.h");
    @cInclude("../stb/stb_image_write.h");
});
const monte_carlo = @import("monte_carlo.zig");

pub const Image = struct {
    data: []u8,
    width: usize,
    height: usize,
    channels: usize,
};


pub fn loadImage(allocator: std.mem.Allocator, path: []const u8) !Image {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const data = c.stbi_load(path_z.ptr, &width, &height, &channels, 4);
    if (data == null) {
        return error.ImageLoadFailed;
    }

    const size = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 4;
    const slice = data[0..size];

    return Image{
        .data = slice,
        .width = @intCast(width),
        .height = @intCast(height),
        .channels = 4,
    };
}

pub fn saveImage(allocator: std.mem.Allocator, path: []const u8, img: *const Image) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const result = c.stbi_write_png(
        path_z.ptr,
        @intCast(img.width),
        @intCast(img.height),
        @intCast(img.channels),
        img.data.ptr,
        @intCast(img.width * img.channels),
    );

    if (result == 0) {
        return error.ImageSaveFailed;
    }
}

pub fn freeImage(img: *Image) void {
    c.stbi_image_free(img.data.ptr);
}

fn printUsage(program: []const u8) void {
    std.debug.print("Usage: {s} <operation> <input_image> <output_image> <radius> <workers>\n", .{program});
    std.debug.print("  operation: 'blur', 'kuwahara', or 'monte_carlo'\n", .{});
    std.debug.print("  For monte_carlo: radius represents number of samples\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 6) {
        printUsage(args[0]);
        return;
    }

    const operation = args[1];
    const input_path = args[2];
    const output_path = args[3];
    const radius = try std.fmt.parseInt(i32, args[4], 10);
    const num_workers = try std.fmt.parseInt(usize, args[5], 10);

    if (std.mem.eql(u8, operation, "monte_carlo")) {
        const samples: usize = @intCast(radius);
        std.debug.print("Monte Carlo Pi estimation with {} samples using {} workers\n", .{ samples, num_workers });
        var timer = try std.time.Timer.start();
        try monte_carlo.monteCarloOperation(samples, num_workers);
        const elapsed = timer.read();
        std.debug.print("Time: {}ms\n", .{elapsed / 1_000_000});
        return;
    }

    var timer = try std.time.Timer.start();

    var src = try loadImage(allocator, input_path);
    defer freeImage(&src);
    const load_time = timer.lap();

    std.debug.print("Image loaded: {}x{} pixels, {} channels\n", .{ src.width, src.height, src.channels });
    std.debug.print("Load time: {}ms\n", .{load_time / 1_000_000});

    const dst_data = try allocator.alloc(u8, src.width * src.height * 4);
    defer allocator.free(dst_data);

    var dst = Image{
        .data = dst_data,
        .width = src.width,
        .height = src.height,
        .channels = src.channels,
    };

    timer.reset();

    if (std.mem.eql(u8, operation, "blur")) {
        std.debug.print("Applying Gaussian blur with radius {} using {} workers\n", .{ radius, num_workers });
        try @import("blur.zig").gaussianBlur(allocator, &src, &dst, @intCast(radius), num_workers);
    } else if (std.mem.eql(u8, operation, "kuwahara")) {
        std.debug.print("Applying Kuwahara filter with radius {} using {} workers\n", .{ radius, num_workers });
        try @import("kuwahara.zig").applyKuwaharaFilter(allocator, &src, &dst, radius, num_workers);
    } else {
        std.debug.print("Unknown operation: {s}. Use 'blur', 'kuwahara', or 'monte_carlo'\n", .{operation});
        return;
    }

    const filter_time = timer.lap();
    std.debug.print("Filter time: {}ms\n", .{filter_time / 1_000_000});

    timer.reset();
    try saveImage(allocator, output_path, &dst);
    const save_time = timer.lap();

    std.debug.print("Save time: {}ms\n", .{save_time / 1_000_000});
    std.debug.print("Total time: {}ms\n", .{(load_time + filter_time + save_time) / 1_000_000});
}
