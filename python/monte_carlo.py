from multiprocessing import Pool

# Linear Congruential Generator - same formula across all languages
class LCG:
    def __init__(self, seed):
        self.seed = seed
    
    def random(self):
        self.seed = (self.seed * 1664525 + 1013904223) & 0xFFFFFFFF
        return (self.seed & 0x7FFFFFFF) / 0x7FFFFFFF

def monte_carlo_worker(args):
    samples, seed = args
    rng = LCG(seed)
    inside = 0
    
    for _ in range(samples):
        x = rng.random()
        y = rng.random()
        if x*x + y*y <= 1.0:
            inside += 1
    
    return inside

def monte_carlo_operation(total_samples, num_workers):
    samples_per_worker = total_samples // num_workers
    remainder = total_samples % num_workers
    
    tasks = []
    for i in range(num_workers):
        samples = samples_per_worker
        if i == num_workers - 1:
            samples += remainder
        tasks.append((samples, 12345 + i * 67890))  # Consistent seed pattern
    
    with Pool(processes=num_workers) as pool:
        results = pool.map(monte_carlo_worker, tasks)
    
    total_inside = sum(results)
    pi_estimate = 4.0 * total_inside / total_samples
    
    print(f"Monte Carlo Pi Estimation")
    print(f"Total samples: {total_samples}")
    print(f"Points inside circle: {total_inside}")
    print(f"Pi estimate: {pi_estimate:.6f}")
    print(f"Error: {3.141592653589793 - pi_estimate:.6f}")