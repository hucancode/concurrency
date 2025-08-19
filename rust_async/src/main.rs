use image::{DynamicImage, GenericImageView, ImageBuffer, Rgba};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task;

#[derive(Debug, Clone)]
struct ImageData {
    data: Vec<u8>,
    width: usize,
    height: usize,
    channels: usize,
}

impl ImageData {
    fn from_dynamic_image(img: &DynamicImage) -> Self {
        let (width, height) = img.dimensions();
        let rgba = img.to_rgba8();
        let data = rgba.into_raw();

        ImageData {
            data,
            width: width as usize,
            height: height as usize,
            channels: 4,
        }
    }

    fn to_dynamic_image(&self) -> DynamicImage {
        let img_buffer = ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(
            self.width as u32,
            self.height as u32,
            self.data.clone(),
        ).expect("Failed to create image buffer");

        DynamicImage::ImageRgba8(img_buffer)
    }

    fn transpose(&self) -> ImageData {
        let mut dst = ImageData {
            data: vec![0; self.data.len()],
            width: self.height,
            height: self.width,
            channels: self.channels,
        };

        for y in 0..self.height {
            for x in 0..self.width {
                let src_idx = (y * self.width + x) * self.channels;
                let dst_idx = (x * self.height + y) * self.channels;

                dst.data[dst_idx..dst_idx + self.channels]
                    .copy_from_slice(&self.data[src_idx..src_idx + self.channels]);
            }
        }

        dst
    }
}

fn generate_gaussian_kernel(radius: usize) -> Vec<f64> {
    let size = 2 * radius + 1;
    let mut kernel = vec![0.0; size];
    let sigma = radius as f64 / 3.0;
    let mut sum = 0.0;

    // Calculate Gaussian values
    for i in 0..size {
        let x = i as f64 - radius as f64;
        kernel[i] = (-x * x / (2.0 * sigma * sigma)).exp();
        sum += kernel[i];
    }

    // Normalize kernel
    for i in 0..size {
        kernel[i] /= sum;
    }

    kernel
}

async fn horizontal_gaussian_blur(src: Arc<ImageData>, dst: Arc<Mutex<ImageData>>, kernel: Arc<Vec<f64>>, radius: usize, start_y: usize, end_y: usize) {
    let mut local_rows = Vec::new();

    for y in start_y..end_y {
        let mut row_data = vec![0u8; src.width * src.channels];

        for x in 0..src.width {
            let mut r_sum = 0.0;
            let mut g_sum = 0.0;
            let mut b_sum = 0.0;
            let mut a_sum = 0.0;

            // Apply Gaussian kernel
            for k in -(radius as i32)..=(radius as i32) {
                let sx = (x as i32 + k).clamp(0, src.width as i32 - 1) as usize;
                let idx = (y * src.width + sx) * src.channels;
                let weight = kernel[(k + radius as i32) as usize];

                r_sum += src.data[idx] as f64 * weight;
                g_sum += src.data[idx + 1] as f64 * weight;
                b_sum += src.data[idx + 2] as f64 * weight;
                a_sum += src.data[idx + 3] as f64 * weight;
            }

            // Write result
            let dst_idx = x * src.channels;
            row_data[dst_idx] = r_sum.round() as u8;
            row_data[dst_idx + 1] = g_sum.round() as u8;
            row_data[dst_idx + 2] = b_sum.round() as u8;
            row_data[dst_idx + 3] = a_sum.round() as u8;
        }

        local_rows.push((y, row_data));
    }

    // Write all rows at once
    let mut dst = dst.lock().await;
    for (y, row_data) in local_rows {
        let row_start = y * src.width * src.channels;
        dst.data[row_start..row_start + src.width * src.channels].copy_from_slice(&row_data);
    }
}

async fn gaussian_blur_async(img: &DynamicImage, radius: u32, num_tasks: usize) -> DynamicImage {
    let src = ImageData::from_dynamic_image(img);
    let radius = radius as usize;

    // Generate Gaussian kernel
    let kernel = Arc::new(generate_gaussian_kernel(radius));

    // Phase 1: Horizontal blur
    let dst_horizontal = Arc::new(Mutex::new(ImageData {
        data: vec![0; src.data.len()],
        width: src.width,
        height: src.height,
        channels: src.channels,
    }));

    let rows_per_task = src.height / num_tasks;
    let src_arc = Arc::new(src);

    let mut tasks = Vec::new();

    for task_id in 0..num_tasks {
        let src = Arc::clone(&src_arc);
        let dst = Arc::clone(&dst_horizontal);
        let kernel = Arc::clone(&kernel);

        let task = task::spawn(async move {
            let start_y = task_id * rows_per_task;
            let end_y = if task_id == num_tasks - 1 {
                src.height
            } else {
                (task_id + 1) * rows_per_task
            };

            horizontal_gaussian_blur(src, dst, kernel, radius, start_y, end_y).await;
        });

        tasks.push(task);
    }

    for task in tasks {
        task.await.unwrap();
    }

    // Get horizontal result and transpose
    let horizontal_result = Arc::try_unwrap(dst_horizontal)
        .unwrap()
        .into_inner();
    let transposed = horizontal_result.transpose();

    // Phase 2: Vertical blur (horizontal on transposed)
    let dst_vertical = Arc::new(Mutex::new(ImageData {
        data: vec![0; transposed.data.len()],
        width: transposed.width,
        height: transposed.height,
        channels: transposed.channels,
    }));

    let rows_per_task = transposed.height / num_tasks;
    let transposed_arc = Arc::new(transposed);

    let mut tasks = Vec::new();

    for task_id in 0..num_tasks {
        let src = Arc::clone(&transposed_arc);
        let dst = Arc::clone(&dst_vertical);
        let kernel = Arc::clone(&kernel);

        let task = task::spawn(async move {
            let start_y = task_id * rows_per_task;
            let end_y = if task_id == num_tasks - 1 {
                src.height
            } else {
                (task_id + 1) * rows_per_task
            };

            horizontal_gaussian_blur(src, dst, kernel, radius, start_y, end_y).await;
        });

        tasks.push(task);
    }

    for task in tasks {
        task.await.unwrap();
    }

    // Get vertical result and transpose back
    let vertical_result = Arc::try_unwrap(dst_vertical)
        .unwrap()
        .into_inner();
    let final_result = vertical_result.transpose();

    final_result.to_dynamic_image()
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
    let load_start = std::time::Instant::now();
    let img = image::open(input_path).expect("Failed to open image");
    let load_duration = load_start.elapsed();
    println!("Image loaded in {:?}", load_duration);

    let (width, height) = img.dimensions();
    println!("Image size: {}x{}", width, height);
    println!("Applying Gaussian blur with radius {} using {} tasks...", radius, num_tasks);
    let blur_start = std::time::Instant::now();

    let blurred = gaussian_blur_async(&img, radius, num_tasks).await;

    let blur_duration = blur_start.elapsed();
    println!("Blur processing completed in {:?}", blur_duration);

    println!("Saving to: {}", output_path);
    let save_start = std::time::Instant::now();
    blurred.save(output_path).expect("Failed to save image");
    let save_duration = save_start.elapsed();
    println!("Image saved in {:?}", save_duration);

    let total_duration = load_start.elapsed();
    println!("Total time: {:?}", total_duration);
    println!("Done!");
}
