package main

import "core:fmt"
import "core:math"
import "core:thread"
import "core:sync"

// Linear Congruential Generator - same formula across all languages
lcg_random :: proc(seed: ^u32) -> f64 {
    seed^ = seed^ * 1664525 + 1013904223
    return f64(seed^ & 0x7FFFFFFF) / f64(0x7FFFFFFF)
}

ThreadData :: struct {
    samples: int,
    seed: u32,
    inside: int,
}

monte_carlo_worker :: proc(t: ^thread.Thread) {
    td := cast(^ThreadData)t.data
    
    inside_count := 0
    for i in 0..<td.samples {
        x := lcg_random(&td.seed)
        y := lcg_random(&td.seed)
        
        if x*x + y*y <= 1.0 {
            inside_count += 1
        }
    }
    
    td.inside = inside_count
}

monte_carlo_operation :: proc(total_samples: int, num_workers: int) {
    workers := num_workers if num_workers > 0 else 1

    // Special case for single worker - run directly without threading
    if workers == 1 {
        seed: u32 = 12345
        
        inside := 0
        for i in 0..<total_samples {
            x := lcg_random(&seed)
            y := lcg_random(&seed)
            
            if x*x + y*y <= 1.0 {
                inside += 1
            }
        }
        
        pi_estimate := 4.0 * f64(inside) / f64(total_samples)
        fmt.printf("Monte Carlo Pi Estimation\n")
        fmt.printf("Total samples: %d\n", total_samples)
        fmt.printf("Points inside circle: %d\n", inside)
        fmt.printf("Pi estimate: %.6f\n", pi_estimate)
        fmt.printf("Error: %.6f\n", math.PI - pi_estimate)
        return
    }

    samples_per_worker := total_samples / workers
    remainder := total_samples % workers

    threads := make([]^thread.Thread, workers)
    defer delete(threads)

    thread_data := make([]ThreadData, workers)
    defer delete(thread_data)

    for i in 0..<workers {
        thread_data[i].samples = samples_per_worker
        if i == workers - 1 {
            thread_data[i].samples += remainder
        }
        thread_data[i].seed = u32(12345 + i * 67890)  // Consistent seed pattern

        threads[i] = thread.create(monte_carlo_worker)
        threads[i].data = &thread_data[i]
        thread.start(threads[i])
    }

    for i in 0..<workers {
        thread.join(threads[i])
        thread.destroy(threads[i])
    }

    total_inside := 0
    for i in 0..<workers {
        total_inside += thread_data[i].inside
    }

    pi_estimate := 4.0 * f64(total_inside) / f64(total_samples)

    fmt.printf("Monte Carlo Pi Estimation\n")
    fmt.printf("Total samples: %d\n", total_samples)
    fmt.printf("Points inside circle: %d\n", total_inside)
    fmt.printf("Pi estimate: %.6f\n", pi_estimate)
    fmt.printf("Error: %.6f\n", math.PI - pi_estimate)
}
