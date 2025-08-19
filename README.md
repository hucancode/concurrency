# Concurrency Performance Comparison

This project compares different concurrency models across Go, Rust, and Odin by implementing a CPU-intensive Gaussian blur algorithm for images. *My experience level for each language is different and may influence the result*

- I will try to get this up to date with modern implementation for each language I know.
- I will not try to make the fastest program. I want to see if I were to put in reasonable effort for each language of choice to make a meaningful program, how fast should I expect it to run.

Basically we are taking this in

![input](input.png)

And produce this out

![output](output.png)

## Implementations

- **Go (async)**: Goroutines (async)
- **Rust (threads)**: OS threads
- **Rust (async)**: Tokio async tasks
- **Odin (threads)**: OS threads
- **Zig (threads)**: OS threads

All implementations use the same Gaussian blur algorithm:
- Divides the image into horizontal strips
- Distributes strips to workers/threads/tasks
- Each worker processes pixels independently
- Results are collected into the output image

### Optimizations Applied

- **Separable filter**: Split 2D Gaussian blur into two 1D passes (horizontal then vertical)
- **Image transpose**: Transpose data between passes for cache-friendly memory access patterns
- **Row buffering**: Process entire rows before writing to minimize lock contention
- **Pre-assigned work**: Avoid work-stealing patterns that cause contention
- **SIMD vectorization (Odin only)**: Process 16 pixels at once using `#simd[16]f32` vectors. SIMD is natively supported by Odin and it is easy to write SIMD code in Odin. To my understanding Rust and Go do not have this kind of convenient out of the box. So I will not include SIMD vectorization in Rust and Go implementations.

## Running

You need go, odin, rust, zig compilers installed along with `hyperfine`. Then run `make bench` to run compare all languages. You can run individual benchmark with `make bench-<language>`
```bash
# run all bench
make bench
# run individual bench
make bench-go
make bench-odin
make bench-rust
make bench-rust-async
make bench-zig
# custom parameters
INPUT_IMAGE=large.jpg WORKERS=16 make bench
```

## Benchmark Results

Benchmarks performed on `wave.png` (3000x1688) with radius 5.

### Blur Processing Only (excluding I/O):

| Implementation | 1 Worker | 4 Workers | 16 Workers | 64 Workers | 128 Workers | Best Performance |
|---------------|----------|-----------|------------|------------|-------------|------------------|
| **Go** | 466 ms | 233 ms | 193 ms | 200 ms | 188 ms | 188 ms @ 128 workers |
| **Rust threads** | 328 ms | 106 ms | 67 ms | 58 ms | 68 ms | 58 ms @ 64 workers |
| **Rust async** | 308 ms | 111 ms | 69 ms | 64 ms | 66 ms | 64 ms @ 64 workers |
| **Odin** | 263 ms | 91 ms | 63 ms | 59 ms | 59 ms | 59 ms @ 64-128 workers |
| **Zig** | 396 ms | 109 ms | 59 ms | 54 ms | 56 ms | 54 ms @ 64 workers |

### Total Time (including image load/save):

| Implementation | 4 Workers | 64 Workers | Relative to Best |
|----------------|-----------|------------|------------------|
| **Rust threads** | 190 ms | **145 ms** | 1.00x |
| **Rust async** | 196 ms | 147 ms | 1.01x slower |
| **Zig** | 666 ms | 574 ms | 3.96x slower |
| **Odin** | 805 ms | 774 ms | 5.34x slower |
| **Go** | 1642 ms | 1592 ms | 10.99x slower |

### Timing Breakdown (4 workers on wave.png)

Breaking down where time is spent in each implementation:

| Implementation | Image Load | Blur Processing | Image Save | Total | Processing % |
|----------------|------------|-----------------|------------|-------|--------------|
| **Go** | 160 ms | 231 ms | 1297 ms | 1689 ms | 13.7% |
| **Rust threads** | 47 ms | 119 ms | 37 ms | 202 ms | 58.9% |
| **Rust async** | 48 ms | 120 ms | 35 ms | 202 ms | 59.4% |
| **Zig** | 99 ms | 119 ms | 475 ms | 693 ms | 17.2% |
| **Odin** | 139 ms | 98 ms | 622 ms | 859 ms | 11.4% |

### Key Observations

#### Zig (threads)
**Best blur performance** at 54 ms with 64 threads. Achieves excellent scaling from 396 ms (1 thread) to 54 ms (64 threads), a 7.3x speedup. The implementation shows strong performance matching Rust for blur processing, but suffers from slower I/O operations using STB libraries, adding ~575ms overhead compared to Rust's ~80ms.

#### Odin (threads)
Strong blur processing at 59 ms with 64-128 threads. Excellent scaling from 263 ms (1 thread) to 59 ms (64+ threads), a 4.5x speedup. The SIMD implementation processes 16 pixels simultaneously using masked loads and vector operations, achieving competitive computational performance.

#### Rust (threads)
**Best overall performance** with 58 ms at 64 threads. Shows near-linear scaling from 328 ms (1 thread) to 58 ms (64 threads), a 5.7x speedup. When the thread count goes to 128, performance drops significantly as expected due to increased context switching overhead.

#### Rust (async)
Very similar to threads with 64 ms at 64 tasks. Scales well from 308 ms (1 thread) to 64 ms (64 tasks), a 4.8x speedup. I thought async version would handle context switching more efficiently, but it doesn't seem to be different from the thread-based implementation.

#### Go (async)
**Poorest scaling** with best time of 188 ms at 128 workers. Only achieves 2.5x speedup from 1 to 128 workers (466 ms → 188 ms). The goroutine overhead and channel communication are efficient, but it pales in comparison to other system languages

## And The Winner Is

- **Fastest total time**: Rust threads at 145 ms (including I/O)
- **Fastest blur processing**: Zig at 54 ms, followed by Rust threads at 58 ms
- **Best scaling**: Zig with 7.3x speedup (1→64 threads), Rust threads with 5.7x speedup
- **I/O bottleneck**: Go has 1400+ ms overhead, Odin has 700+ ms, Zig has 520+ ms. Rust excels with only ~80ms I/O overhead due to efficient image library implementation.
