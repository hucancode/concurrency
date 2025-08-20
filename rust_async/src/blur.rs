use image::{DynamicImage, ImageBuffer, Rgba};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task;

#[derive(Debug, Clone)]
pub struct ImageData {
    pub data: Vec<u8>,
    pub width: usize,
    pub height: usize,
    pub channels: usize,
}

impl ImageData {
    pub fn from_dynamic_image(img: &DynamicImage) -> Self {
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();
        let data = rgba.into_raw();

        ImageData {
            data,
            width: width as usize,
            height: height as usize,
            channels: 4,
        }
    }

    pub fn to_dynamic_image(&self) -> DynamicImage {
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

    for i in 0..size {
        let x = i as f64 - radius as f64;
        kernel[i] = (-x * x / (2.0 * sigma * sigma)).exp();
        sum += kernel[i];
    }

    for i in 0..size {
        kernel[i] /= sum;
    }

    kernel
}

async fn horizontal_gaussian_blur(
    src: Arc<ImageData>,
    dst: Arc<Mutex<ImageData>>,
    kernel: Arc<Vec<f64>>,
    radius: usize,
    start_y: usize,
    end_y: usize,
) {
    let mut local_rows = Vec::new();

    for y in start_y..end_y {
        let mut row_data = vec![0u8; src.width * src.channels];

        for x in 0..src.width {
            let mut r_sum = 0.0;
            let mut g_sum = 0.0;
            let mut b_sum = 0.0;
            let mut a_sum = 0.0;

            for k in -(radius as i32)..=(radius as i32) {
                let sx = (x as i32 + k).clamp(0, src.width as i32 - 1) as usize;
                let idx = (y * src.width + sx) * src.channels;
                let weight = kernel[(k + radius as i32) as usize];

                r_sum += src.data[idx] as f64 * weight;
                g_sum += src.data[idx + 1] as f64 * weight;
                b_sum += src.data[idx + 2] as f64 * weight;
                a_sum += src.data[idx + 3] as f64 * weight;
            }

            let row_idx = x * src.channels;
            row_data[row_idx] = r_sum.round() as u8;
            row_data[row_idx + 1] = g_sum.round() as u8;
            row_data[row_idx + 2] = b_sum.round() as u8;
            row_data[row_idx + 3] = a_sum.round() as u8;
        }

        local_rows.push((y, row_data));
    }

    let mut dst_locked = dst.lock().await;
    for (y, row_data) in local_rows {
        let row_start = y * src.width * src.channels;
        let row_end = row_start + src.width * src.channels;
        dst_locked.data[row_start..row_end].copy_from_slice(&row_data);
    }
}

pub async fn apply_gaussian_blur_async(img: &DynamicImage, radius: u32, num_tasks: usize) -> DynamicImage {
    let src = ImageData::from_dynamic_image(img);
    let radius = radius as usize;
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

    let vertical_result = Arc::try_unwrap(dst_vertical)
        .unwrap()
        .into_inner();
    let final_result = vertical_result.transpose();

    final_result.to_dynamic_image()
}