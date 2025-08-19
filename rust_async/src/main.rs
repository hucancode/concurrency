use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task;

async fn box_blur_async(img: &DynamicImage, radius: u32, num_tasks: usize) -> DynamicImage {
    let (width, height) = img.dimensions();
    let src = Arc::new(img.to_rgba8());
    let dst = Arc::new(Mutex::new(ImageBuffer::<Rgba<u8>, Vec<u8>>::new(width, height)));
    
    let rows_per_task = height as usize / num_tasks;
    
    let mut tasks = Vec::new();
    
    for task_id in 0..num_tasks {
        let src = Arc::clone(&src);
        let dst = Arc::clone(&dst);
        
        let task = task::spawn(async move {
            let start_y = task_id * rows_per_task;
            let end_y = if task_id == num_tasks - 1 {
                height as usize
            } else {
                (task_id + 1) * rows_per_task
            };
            
            let mut local_pixels = Vec::new();
            
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
                        local_pixels.push((x, y as u32, pixel));
                    }
                }
            }
            
            // Write all pixels at once to minimize lock contention
            let mut dst = dst.lock().await;
            for (x, y, pixel) in local_pixels {
                dst.put_pixel(x, y, pixel);
            }
        });
        
        tasks.push(task);
    }
    
    // Wait for all tasks to complete
    for task in tasks {
        task.await.unwrap();
    }
    
    let result = Arc::try_unwrap(dst).unwrap().into_inner();
    DynamicImage::ImageRgba8(result)
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 2 {
        eprintln!("Usage: {} <input_image> [output_image] [radius] [tasks]", args[0]);
        std::process::exit(1);
    }
    
    let input_path = &args[1];
    let output_path = args.get(2).map(|s| s.as_str()).unwrap_or("blurred.png");
    let radius: u32 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(5);
    let num_tasks = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(4);
    
    println!("Loading image: {}", input_path);
    let img = image::open(input_path).expect("Failed to open image");
    
    println!("Applying box blur with radius {} using {} async tasks...", radius, num_tasks);
    let start = std::time::Instant::now();
    
    let blurred = box_blur_async(&img, radius, num_tasks).await;
    
    let duration = start.elapsed();
    println!("Blur completed in {:?}", duration);
    
    println!("Saving to: {}", output_path);
    blurred.save(output_path).expect("Failed to save image");
    
    println!("Done!");
}