# Concurrency Performance Comparison

This project compares different concurrency models across C, Zig, Go, Rust, and Odin by implementing a CPU-intensive Gaussian blur algorithm for images. I will aim to for the best practices and idioms of each language.
*My experience level for each language is different and may influence the result*

Basically we are taking this in

![input](input.png)

And produce this out

![output](output.png)

## Implementations

- **C (threads)**: OS threads
- **Go (async)**: Goroutines (async)
- **Rust (threads)**: OS threads
- **Rust (async)**: Tokio async tasks
- **Odin (threads)**: OS threads
- **Zig (threads)**: OS threads
- **Python (threads)**: Thread pool

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
- **SIMD vectorization (Odin & Zig)**: Process multiple pixels at once using vector operations. Odin uses `#simd[16]f32` vectors while Zig uses `@Vector(16, f32)`. Technically we can use SIMD on all languages if we try hard enough but to maintain fairness I will not implement SIMD where it is not encouraged by the language design.

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

Benchmarks performed on `wave.png` (2048x1024) with radius 5.

### Total Time (including image load/save):

| Implementation | 1 Worker | 4 Workers | 16 Workers | 64 Workers | 128 Workers | Best Time |
|----------------|----------|-----------|------------|------------|-------------|-----------|
| **Rust async** | 169.4 ms | 82.1 ms | 65.9 ms | 65.1 ms | **64.3 ms** | 64.3 ms @ 128 |
| **Rust threads** | 176.7 ms | 86.6 ms | 68.5 ms | 66.7 ms | 68.4 ms | 66.7 ms @ 64 |
| **Zig** | 282.7 ms | 262.1 ms | 256.4 ms | 253.1 ms | 256.5 ms | 253.1 ms @ 64 |
| **C** | 382.6 ms | 293.5 ms | 271.8 ms | 269.5 ms | 271.1 ms | 269.5 ms @ 64 |
| **Odin** | 363.4 ms | 333.4 ms | 326.2 ms | 319.4 ms | 324.2 ms | 319.4 ms @ 64 |
| **Go** | 1272 ms | 807.5 ms | 721.4 ms | 707.9 ms | 716.2 ms | 707.9 ms @ 64 |
| **Python** | 51 s | 51 s | 52 s | 52 s | 52 s | 51 s @ 1 |

### Blur Processing Only (excluding I/O):

Benchmarks performed on `wave.png` (2048x1024) with radius 5 and 64 workers.

| Implementation | Processing Time | I/O Overhead |
|----------------|----------------|--------------|
| **Odin** | 25 ms | 302 ms |
| **Zig** | 27 ms | 226 ms |
| **C** | 28 ms | 241 ms |
| **Rust threads** | 31 ms | 34 ms |
| **Rust async** | 32 ms | 31 ms |
| **Go** | 144 ms | 570 ms |
| **Python** | 50 s | 495 ms |


### Key Observations

#### Rust (async)
**Best overall performance** at 63.6 ms total time. Minimal I/O overhead (31 ms) thanks to efficient image library. Slightly edges out the threads version.

#### Rust (threads)
Nearly identical performance to async at 65.2 ms. Both Rust implementations show excellent I/O efficiency with only ~30-35 ms overhead.

#### C (threads)
Fast blur processing at 28 ms but significant I/O overhead (241 ms) from STB image library. Total time of 269.5 ms.

#### Zig (threads)
**Fastest blur processing** at 27 ms, demonstrating excellent SIMD optimization. However, I/O overhead (226 ms) limits total performance to 253.5 ms.

#### Odin (threads)
**Second fastest blur processing** at 25 ms with SIMD optimization. Highest I/O overhead (302 ms) results in 327.5 ms total time.

#### Go (async)
Slowest compiled language blur processing (144 ms) and massive I/O overhead (570 ms). Total time of 714 ms is over 11x slower than Rust.

#### Python (threads)
No comment. Only serve as a reference point for comparison

## And The Winner Is

- **Fastest total time**: Rust async at 63.6 ms (including I/O)
- **Fastest blur processing**: Odin at 25 ms, followed by Zig at 27 ms and C at 28 ms, basically the same
- **Best I/O efficiency**: Rust implementations with only ~30-35 ms overhead. Odin, C, Zig has around 200-300 ms. Go has 570 ms overhead
