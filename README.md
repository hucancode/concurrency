# Concurrency Performance Comparison

This project compares different concurrency models across Go, Rust, and Odin by implementing a CPU-intensive Gaussian blur algorithm for images. *My experience level for each language is different and may influence the result*

- I will try to get this up to date with modern implementation for each language I know.
- I will not try to make the fastest program. I want to see if I were to put in reasonable effort for each language of choice to make a meaningful program, how fast should I expect it to run.

Basically we are taking this in

![input](input.png)

And produce this out

![output](output.png)

## Implementations

- **Go**: Goroutines with channels for work distribution
- **Rust (threads)**: OS threads with `Arc<Mutex>` for shared state
- **Rust (async)**: Tokio async tasks with async mutex
- **Odin**: OS threads

## Algorithm

All implementations use the same Gaussian blur algorithm:
- Divides the image into horizontal strips
- Distributes strips to workers/threads/tasks
- Each worker processes pixels independently
- Results are collected into the output image

### Optimizations Applied

- **Gaussian kernel**: Pre-computed weighted kernel based on Gaussian distribution for better image quality
- **Separable filter**: Split 2D Gaussian blur into two 1D passes (horizontal then vertical)
- **Image transpose**: Transpose data between passes for cache-friendly memory access patterns
- **Row buffering**: Process entire rows before writing to minimize lock contention
- **Pre-assigned work**: Avoid work-stealing patterns that cause contention
- **SIMD vectorization (Odin)**: Process 8 pixels at once using `#simd[8]f32` vectors

## Running

You need go, odin, rust compiler installed along with `hyperfine`. Then run `make bench` to run compare all languages. You can run individual benchmark with `make bench-<language>`
```bash
# run all bench
make bench
# run individual bench
make bench-go
make bench-odin
make bench-rust
make bench-rust-async
# custom parameters
INPUT_IMAGE=large.jpg WORKERS=16 make bench
```

## Benchmark Results

Benchmarks performed on `wave.png` (3000x1688) with radius 5. All times include image loading and saving.

### Performance with different worker counts:

| Implementation | 1 Worker | 4 Workers | 16 Workers | 64 Workers | 128 Workers | Best Performance |
|---------------|----------|-----------|------------|------------|-------------|------------------|
| **Go** | 1404 ms | 1364 ms | 1375 ms | 1377 ms | 1376 ms | 4 workers |
| **Rust threads** | 163 ms | 141 ms | 139 ms | 139 ms | 140 ms | 16-64 threads |
| **Rust async** | 163 ms | 141 ms | 138 ms | 137 ms | 137 ms | 64-128 tasks |
| **Odin (SIMD)** | 361 ms | 755 ms | 751 ms | 751 ms | - | 1 thread (!) |

### Head-to-head Comparison at 16 workers

Benchmark command:
```bash
make bench INPUT_IMAGE=wave.png WORKERS=16
```

| Implementation | Time | Relative Speed |
|----------------|------|----------------|
| **Rust async** | 136 ms | 1.00x (fastest) |
| **Rust threads** | 137 ms | 1.01x slower |
| **Odin (SIMD)** | 751 ms | 5.52x slower |
| **Go** | 1350 ms | 9.92x slower |

### Timing Breakdown (16 workers on wave.png)

Breaking down where time is spent in each implementation:

| Implementation | Image Load | Blur Processing | Image Save | Total | Processing % |
|----------------|------------|-----------------|------------|-------|--------------|
| **Go** | 166 ms | 136 ms | 1016 ms | 1318 ms | 10.3% |
| **Rust threads** | 63 ms | 45 ms | 39 ms | 147 ms | 30.6% |
| **Rust async** | 64 ms | 43 ms | 39 ms | 146 ms | 29.5% |
| **Odin (SIMD)** | 148 ms | 37 ms | 582 ms | 767 ms | 4.8% |

- Go spends 90% of its time on I/O (especially saving - 1016 ms!)
- Rust implementations have the most balanced profile (30% processing, 70% I/O)
- Odin with proper SIMD has the fastest blur processing (37 ms) but terrible I/O performance (730 ms total)
- All implementations use the same Gaussian blur algorithm, but Rust has the best overall balance

### Key Observations

#### Rust async (Tokio)
Best overall performance (137 ms at 64-128 tasks). Excellent scaling from 1 to 16 workers, then plateaus with stable performance. The async runtime handles the large image efficiently.

#### Rust threads
Nearly identical to async (139 ms at 16-64 threads). Shows good scaling up to 16 threads, demonstrating effective parallelization of the sliding window algorithm.

#### Odin (with SIMD)
Single-threaded performance (361 ms) is still best. Adding threads makes it over 2x slower (751-755 ms), indicating severe threading overhead or contention issues. The properly implemented SIMD achieves the fastest pure blur processing (37 ms) of all implementations, but poor I/O performance and threading issues prevent it from competing overall.

#### Go
Consistent but slow performance (1350-1404 ms). The Go implementation shows minimal benefit from additional workers, suggesting that the goroutine overhead dominates the computation for this image size.

## And The Winner Is

- **Best overall**: Rust async at 64-128 tasks (137 ms total, 43 ms processing)
- **Close second**: Rust threads at 16-64 threads (139 ms total, 45 ms processing)
- **Fastest processing**: Odin SIMD at 37 ms (but 767 ms total due to poor I/O)
- **Odin observation**: Despite having the fastest blur algorithm with SIMD, threading issues prevent scaling
