mod blur;
mod kuwahara;

use blur::apply_gaussian_blur_async;
use kuwahara::apply_kuwahara_filter_async;
use image::GenericImageView;
use std::env;
use std::time::Instant;

fn print_usage(program: &str) {
    eprintln!("Usage: {} <operation> <input_image> <output_image> <radius> [tasks]", program);
    eprintln!("  operation: 'blur' or 'kuwahara'");
    eprintln!("  tasks: optional, defaults to 4");
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();
    
    if args.len() < 5 {
        print_usage(&args[0]);
        std::process::exit(1);
    }

    let operation = &args[1];
    let input_path = &args[2];
    let output_path = &args[3];
    let radius: i32 = args[4].parse().expect("Invalid radius");
    let num_tasks: usize = args.get(5)
        .and_then(|s| s.parse().ok())
        .unwrap_or(4);

    let start = Instant::now();
    let img = image::open(input_path).expect("Failed to load image");
    let load_time = start.elapsed();

    let (width, height) = img.dimensions();
    println!("Image loaded: {}x{} pixels", width, height);
    println!("Load time: {}ms", load_time.as_millis());

    let start = Instant::now();
    let result = match operation.as_str() {
        "blur" => {
            println!("Applying Gaussian blur with radius {} using {} async tasks", radius, num_tasks);
            apply_gaussian_blur_async(&img, radius as u32, num_tasks).await
        },
        "kuwahara" => {
            println!("Applying Kuwahara filter with radius {} using {} async tasks", radius, num_tasks);
            apply_kuwahara_filter_async(&img, radius, num_tasks).await
        },
        _ => {
            eprintln!("Unknown operation: {}. Use 'blur' or 'kuwahara'", operation);
            std::process::exit(1);
        }
    };
    let filter_time = start.elapsed();
    println!("Filter time: {}ms", filter_time.as_millis());

    let start = Instant::now();
    result.save(output_path).expect("Failed to save image");
    let save_time = start.elapsed();

    println!("Save time: {}ms", save_time.as_millis());
    println!("Total time: {}ms", (load_time + filter_time + save_time).as_millis());
}