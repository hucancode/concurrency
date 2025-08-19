use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};
use std::sync::{Arc, Mutex};
use std::thread;

fn box_blur_threads(img: &DynamicImage, radius: u32, num_threads: usize) -> DynamicImage {
    let (width, height) = img.dimensions();
    let src = img.to_rgba8();
    let dst = Arc::new(Mutex::new(ImageBuffer::<Rgba<u8>, Vec<u8>>::new(width, height)));
    
    let rows_per_thread = height as usize / num_threads;
    let src_arc = Arc::new(src);
    
    let handles: Vec<_> = (0..num_threads)
        .map(|thread_id| {
            let src = Arc::clone(&src_arc);
            let dst = Arc::clone(&dst);
            
            thread::spawn(move || {
                let start_y = thread_id * rows_per_thread;
                let end_y = if thread_id == num_threads - 1 {
                    height as usize
                } else {
                    (thread_id + 1) * rows_per_thread
                };
                
                for y in start_y..end_y {
                    for x in 0..width {
                        let mut r_sum = 0u32;
                        let mut g_sum = 0u32;
                        let mut b_sum = 0u32;
                        let mut a_sum = 0u32;
                        let mut count = 0u32;
                        
                        for dy in -(radius as i32)..=(radius as i32) {
                            for dx in -(radius as i32)..=(radius as i32) {
                                let nx = x as i32 + dx;
                                let ny = y as i32 + dy;
                                
                                if nx >= 0 && nx < width as i32 && ny >= 0 && ny < height as i32 {
                                    let pixel = src.get_pixel(nx as u32, ny as u32);
                                    r_sum += pixel[0] as u32;
                                    g_sum += pixel[1] as u32;
                                    b_sum += pixel[2] as u32;
                                    a_sum += pixel[3] as u32;
                                    count += 1;
                                }
                            }
                        }
                        
                        if count > 0 {
                            let pixel = Rgba([
                                (r_sum / count) as u8,
                                (g_sum / count) as u8,
                                (b_sum / count) as u8,
                                (a_sum / count) as u8,
                            ]);
                            
                            let mut dst = dst.lock().unwrap();
                            dst.put_pixel(x, y as u32, pixel);
                        }
                    }
                }
            })
        })
        .collect();
    
    for handle in handles {
        handle.join().unwrap();
    }
    
    let result = Arc::try_unwrap(dst).unwrap().into_inner().unwrap();
    DynamicImage::ImageRgba8(result)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        eprintln!("Usage: {} <input_image> [output_image] [radius] [threads]", args[0]);
        std::process::exit(1);
    }
    
    let input_path = &args[1];
    let output_path = args.get(2).map(|s| s.as_str()).unwrap_or("blurred.png");
    let radius: u32 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(5);
    let num_threads = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(4);
    
    println!("Loading image: {}", input_path);
    let img = image::open(input_path).expect("Failed to open image");
    
    println!("Applying box blur with radius {} using {} threads...", radius, num_threads);
    let start = std::time::Instant::now();
    
    let blurred = box_blur_threads(&img, radius, num_threads);
    
    let duration = start.elapsed();
    println!("Blur completed in {:?}", duration);
    
    println!("Saving to: {}", output_path);
    blurred.save(output_path).expect("Failed to save image");
    
    println!("Done!");
}