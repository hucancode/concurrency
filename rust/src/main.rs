mod blur;
mod kuwahara;

use std::env;
use std::time::Instant;

fn print_usage(program: &str) {
    eprintln!("Usage: {} <operation> <input_image> <output_image> <radius> [threads]", program);
    eprintln!("  operation: 'blur' or 'kuwahara'");
    eprintln!("  threads: optional, defaults to 4");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 5 {
        print_usage(&args[0]);
        std::process::exit(1);
    }

    let operation = &args[1];
    let input_path = &args[2];
    let output_path = &args[3];
    let radius: i32 = args[4].parse().expect("Invalid radius");
    let num_threads: usize = args.get(5)
        .and_then(|s| s.parse().ok())
        .unwrap_or(4);

    let start = Instant::now();
    let img = image::open(input_path).expect("Failed to load image").to_rgba8();
    let load_time = start.elapsed();

    let (width, height) = img.dimensions();
    println!("Image loaded: {}x{} pixels", width, height);
    println!("Load time: {}ms", load_time.as_millis());

    let start = Instant::now();
    let result = match operation.as_str() {
        "blur" => {
            println!("Applying Gaussian blur with radius {} using {} threads", radius, num_threads);
            blur::apply_gaussian_blur(&img, radius, num_threads)
        },
        "kuwahara" => {
            println!("Applying Kuwahara filter with radius {} using {} threads", radius, num_threads);
            kuwahara::apply_kuwahara_filter(&img, radius, num_threads)
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
