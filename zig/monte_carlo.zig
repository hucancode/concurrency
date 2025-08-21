const std = @import("std");

const ThreadData = struct {
    samples: usize,
    seed: u32,
    inside: usize,
};

// Linear Congruential Generator - same formula across all languages
fn lcgRandom(seed: *u32) f64 {
    seed.* = seed.* *% 1664525 +% 1013904223;
    return @as(f64, @floatFromInt(seed.* & 0x7FFFFFFF)) / @as(f64, @floatFromInt(0x7FFFFFFF));
}

fn monteCarloWorker(data: *ThreadData) void {
    data.inside = 0;
    
    var i: usize = 0;
    while (i < data.samples) : (i += 1) {
        const x = lcgRandom(&data.seed);
        const y = lcgRandom(&data.seed);
        if (x * x + y * y <= 1.0) {
            data.inside += 1;
        }
    }
}

pub fn monteCarloOperation(total_samples: usize, num_workers: usize) !void {
    const workers = if (num_workers > 0) num_workers else 1;
    
    const allocator = std.heap.page_allocator;
    var threads = try allocator.alloc(std.Thread, workers);
    defer allocator.free(threads);
    
    var thread_data = try allocator.alloc(ThreadData, workers);
    defer allocator.free(thread_data);
    
    const samples_per_worker = total_samples / workers;
    const remainder = total_samples % workers;
    
    for (0..workers) |i| {
        thread_data[i].samples = samples_per_worker;
        if (i == workers - 1) {
            thread_data[i].samples += remainder;
        }
        thread_data[i].seed = @intCast(12345 + i * 67890);  // Consistent seed pattern
        
        threads[i] = try std.Thread.spawn(.{}, monteCarloWorker, .{&thread_data[i]});
    }
    
    var total_inside: usize = 0;
    for (0..workers) |i| {
        threads[i].join();
        total_inside += thread_data[i].inside;
    }
    
    const pi_estimate: f64 = 4.0 * @as(f64, @floatFromInt(total_inside)) / @as(f64, @floatFromInt(total_samples));
    
    std.debug.print("Monte Carlo Pi Estimation\n", .{});
    std.debug.print("Total samples: {}\n", .{total_samples});
    std.debug.print("Points inside circle: {}\n", .{total_inside});
    std.debug.print("Pi estimate: {d:.6}\n", .{pi_estimate});
    std.debug.print("Error: {d:.6}\n", .{3.141592653589793 - pi_estimate});
}