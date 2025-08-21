# Concurrency Performance Comparison

## Abstract

If you ever wonder how multi-threading and asynchronous code speed up your program, wonder no more. This project compares different concurrency models across C, Zig, Go, Rust, and Odin by implementing a CPU-intensive Gaussian blur algorithm for images. I will aim to for the best practices and idioms of each language.
_My experience level for each language is different and may influence the result_

### Pure computation workload (the easy case)
Before going in to the real world example. Let's examine the theoritical pure computation workload.

With pure computation workload, almost everything happens inside the CPU. So the parallelism speed up is significant.
Take a look at the following table where we approximate PI number using Monte-Carlo approximation (500 million samples):

| Implementation   | 1 Worker | 4 Workers | 16 Workers | 64 Workers |
| ---------------- | -------- | --------- | ---------- | ---------- |
| **Rust Async**   | 777 ms   | 212 ms    | 104 ms     | 102 ms     |
| **Rust Threads** | 826 ms   | 219 ms    | 104 ms     | 100 ms     |
| **Go**           | 1468 ms  | 380 ms    | 188 ms     | 185 ms     |
| **C**            | 2506 ms  | 651 ms    | 290 ms     | 274 ms     |
| **Zig**          | 2494 ms  | 642 ms    | 277 ms     | 264 ms     |
| **Odin**         | 3810 ms  | 563 ms    | 332 ms     | 322 ms     |

So our claim is true. Adding more threads is indeed helps! But 100x more threads does not mean 100x more speed. You can read more about the math [here](https://en.wikipedia.org/wiki/Amdahl%27s_law)

In real world applications, pure computational algorithm are rare. We should not expect our code to be always 8x faster like the above table. In the next section we will do some more realistic work load to see what we should expect.

## Real world workload

To simulate a real world application. Let's implement a image processor.
We are taking this in

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
- **Python (threads)**: Multi process

All implementations use the same Gaussian blur algorithm:

- Divides the image into horizontal strips
- Distributes strips to workers/threads/tasks
- Each worker processes pixels independently
- Results are collected into the output image

### Optimizations Applied

- **Separable filter**: Split 2D Gaussian blur into two 1D passes (horizontal then vertical)
- **Image transpose**: Transpose data between passes for cache-friendly memory access patterns
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

| Implementation   | 1 Worker | 4 Workers | 16 Workers | 64 Workers   | 128 Workers |
| ---------------- | -------- | --------- | ---------- | ------------ | ----------- |
| **Rust async**   | 169.4 ms | 82.1 ms   | 65.9 ms    | 65.1 ms      | **64.3 ms** |
| **Rust threads** | 176.7 ms | 86.6 ms   | 68.5 ms    | **66.7 ms**  | 68.4 ms     |
| **Zig**          | 282.7 ms | 262.1 ms  | 256.4 ms   | **253.1 ms** | 256.5 ms    |
| **C**            | 382.6 ms | 293.5 ms  | 271.8 ms   | **269.5 ms** | 271.1 ms    |
| **Odin**         | 363.4 ms | 333.4 ms  | 326.2 ms   | **319.4 ms** | 324.2 ms    |
| **Go**           | 1272 ms  | 807.5 ms  | 721.4 ms   | **707.9 ms** | 716.2 ms    |
| **Python**       | 75.9 s   | 38.9 s    | 21.2 s     | 14.3 s       | 13.0 s      |

### Blur Processing Only (excluding I/O):

Benchmarks performed on `wave.png` (2048x1024) with radius 5 and 64 workers.

| Implementation   | Processing Time |
| ---------------- | --------------- |
| **Odin**         | 25 ms           |
| **Zig**          | 27 ms           |
| **C**            | 28 ms           |
| **Rust threads** | 31 ms           |
| **Rust async**   | 32 ms           |
| **Go**           | 144 ms          |
| **Python**       | 14 s            |

### Key Observations

- `Rust` seems to be the best performer (64.3ms) but if we look closely we can see that raw processing time is not much different between all languages except `Go`. `Rust` just happens to have better image library than `stb_image` used across `Zig` `Odin` `C`.
- Despite having SIMD enabled, `Zig` and `Odin` version doesn't seem to be much faster than `Rust` and `C`.
- And last but not least, eventhough the work load is highly independent, more thread doesn't always mean more performance for our use case. Actually I was expecting more speed up from threads, somewhere like 5x 10x improvement. But look how wrong I was.
