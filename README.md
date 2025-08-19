# Modern Concurrency Comparison: Image Blur Implementations

This project compares different concurrency models across Go, Rust, and Odin by implementing a CPU-intensive box blur algorithm for images.

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
- **Odin**: OS threads with mutex synchronization

## Algorithm

All implementations use the same box blur algorithm:
- Divides the image into horizontal strips
- Distributes strips to workers/threads/tasks
- Each worker processes pixels independently
- Results are collected into the output image

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

Benchmarks performed on `input.png` (500x500) with radius 5.

### Performance Comparison (8 workers/threads)

| Implementation | Mean Time | Std Dev | Relative Speed |
|---------------|-----------|---------|----------------|
| **Rust async** | 12.2 ms | ±0.5 ms | 1.00x (fastest) |
| **Odin** | 21.9 ms | ±0.6 ms | 1.79x slower |
| **Rust threads** | 37.5 ms | ±0.6 ms | 3.07x slower |
| **Go** | 88.8 ms | ±2.5 ms | 7.26x slower |

### Scaling Analysis

Performance with different worker counts:

| Implementation | 1 Worker | 4 Workers | 8 Workers | Scaling Efficiency |
|---------------|----------|-----------|-----------|-------------------|
| **Go** | 358.5 ms | 112.1 ms | 89.0 ms | Poor (1→4: 3.2x, 4→8: 1.26x) |
| **Rust threads** | 36.8 ms | 14.7 ms | 36.2 ms | Degrades at 8 threads |
| **Rust async** | 41.9 ms | 13.0 ms | 11.4 ms | Good (consistent improvement) |
| **Odin** | 13.7 ms | 20.0 ms | 18.9 ms | Inverse scaling (slower with more threads) |

### Key Observations

#### Rust async (Tokio)
Achieves the best overall performance with 8 tasks, showing excellent scaling and minimal overhead.

#### Odin
Shows interesting behavior - fastest with 1 thread (13.7 ms) but **slower** with more threads. I don't know why, maybe my implementation got some problem.

#### Rust threads
Performs well with 4 threads but degrades at 8, likely due to mutex contention on the shared output buffer.

#### Go
Has the highest baseline overhead but shows reasonable scaling up to 4 workers. The channel-based approach adds communication overhead.

## And The Winner Is

- **Best performance**: Rust + Tokio. Not so suprised.
- **Memory overhead**: Go > Rust async > Rust threads > Odin
- **Context switching**: Rust threads high at 8 threads (114.7 ms system time)
