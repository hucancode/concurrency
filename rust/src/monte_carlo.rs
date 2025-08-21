use std::thread;

// Linear Congruential Generator - same formula across all languages
fn lcg_random(seed: &mut u32) -> f64 {
    *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
    (*seed & 0x7FFFFFFF) as f64 / 0x7FFFFFFF as f64
}

pub fn monte_carlo_operation(total_samples: usize, num_workers: usize) {
    let samples_per_worker = total_samples / num_workers;
    let remainder = total_samples % num_workers;
    
    let mut handles = vec![];
    
    for worker_id in 0..num_workers {
        let samples = if worker_id == num_workers - 1 {
            samples_per_worker + remainder
        } else {
            samples_per_worker
        };
        
        let handle = thread::spawn(move || {
            let mut seed = (12345 + worker_id * 67890) as u32; // Consistent seed pattern
            let mut inside = 0;
            
            for _ in 0..samples {
                let x = lcg_random(&mut seed);
                let y = lcg_random(&mut seed);
                if x * x + y * y <= 1.0 {
                    inside += 1;
                }
            }
            
            inside
        });
        
        handles.push(handle);
    }
    
    let mut total_inside = 0;
    for handle in handles {
        total_inside += handle.join().unwrap();
    }
    
    let pi_estimate = 4.0 * total_inside as f64 / total_samples as f64;
    
    println!("Monte Carlo Pi Estimation");
    println!("Total samples: {}", total_samples);
    println!("Points inside circle: {}", total_inside);
    println!("Pi estimate: {:.6}", pi_estimate);
    println!("Error: {:.6}", std::f64::consts::PI - pi_estimate);
}