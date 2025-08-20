use image::{DynamicImage, ImageBuffer, Rgba};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task;
use std::time::Instant;

pub struct IntegralImage {
    sum: Vec<f32>,
    sum_sq: Vec<f32>,
    width: usize,
    height: usize,
}

impl IntegralImage {
    fn new(width: usize, height: usize) -> Self {
        let size = (width + 1) * (height + 1) * 3;
        IntegralImage {
            sum: vec![0.0; size],
            sum_sq: vec![0.0; size],
            width,
            height,
        }
    }

    fn build(&mut self, img: &ImageBuffer<Rgba<u8>, Vec<u8>>) {
        let w = self.width;
        let h = self.height;
        let iw = self.width + 1;

        for y in 1..=h {
            for x in 1..=w {
                let pixel = img.get_pixel((x - 1) as u32, (y - 1) as u32);
                let channels = [pixel[0] as f32, pixel[1] as f32, pixel[2] as f32];

                for ch in 0..3 {
                    let val = channels[ch];
                    let idx = (y * iw + x) * 3 + ch;
                    let idx_up = ((y - 1) * iw + x) * 3 + ch;
                    let idx_left = (y * iw + (x - 1)) * 3 + ch;
                    let idx_diag = ((y - 1) * iw + (x - 1)) * 3 + ch;

                    self.sum[idx] = val + self.sum[idx_up] + self.sum[idx_left] - self.sum[idx_diag];
                    self.sum_sq[idx] = val * val
                        + self.sum_sq[idx_up]
                        + self.sum_sq[idx_left]
                        - self.sum_sq[idx_diag];
                }
            }
        }
    }

    fn get_region_stats(&self, x1: i32, y1: i32, x2: i32, y2: i32) -> ([f32; 3], [f32; 3]) {
        let iw = self.width + 1;

        let x1 = x1.max(0) as usize;
        let y1 = y1.max(0) as usize;
        let x2 = x2.min(self.width as i32 - 1) as usize;
        let y2 = y2.min(self.height as i32 - 1) as usize;

        let x1 = x1 + 1;
        let y1 = y1 + 1;
        let x2 = x2 + 1;
        let y2 = y2 + 1;

        let area = ((x2 - x1 + 1) * (y2 - y1 + 1)) as f32;
        let mut mean = [0.0; 3];
        let mut variance = [0.0; 3];

        if area > 0.0 {
            for ch in 0..3 {
                let idx_br = (y2 * iw + x2) * 3 + ch;
                let idx_bl = (y2 * iw + x1 - 1) * 3 + ch;
                let idx_tr = ((y1 - 1) * iw + x2) * 3 + ch;
                let idx_tl = ((y1 - 1) * iw + x1 - 1) * 3 + ch;

                let sum = self.sum[idx_br] - self.sum[idx_bl] - self.sum[idx_tr] + self.sum[idx_tl];
                let sum_sq = self.sum_sq[idx_br] - self.sum_sq[idx_bl] - self.sum_sq[idx_tr]
                    + self.sum_sq[idx_tl];

                mean[ch] = sum / area;
                variance[ch] = (sum_sq / area) - (mean[ch] * mean[ch]);
                if variance[ch] < 0.0 {
                    variance[ch] = 0.0;
                }
            }
        }

        (mean, variance)
    }
}

fn kuwahara_filter_pixel(
    src: &ImageBuffer<Rgba<u8>, Vec<u8>>,
    integral: &IntegralImage,
    x: i32,
    y: i32,
    radius: i32,
) -> Rgba<u8> {
    let mut min_variance = f32::MAX;
    let mut best_mean = [0.0; 3];

    let quadrants = [
        [x - radius, y - radius, x, y],
        [x, y - radius, x + radius, y],
        [x - radius, y, x, y + radius],
        [x, y, x + radius, y + radius],
    ];

    for quad in &quadrants {
        let (mean, variance) = integral.get_region_stats(quad[0], quad[1], quad[2], quad[3]);
        let total_variance = variance[0] + variance[1] + variance[2];

        if total_variance < min_variance {
            min_variance = total_variance;
            best_mean = mean;
        }
    }

    let src_pixel = src.get_pixel(x as u32, y as u32);
    Rgba([
        best_mean[0].clamp(0.0, 255.0) as u8,
        best_mean[1].clamp(0.0, 255.0) as u8,
        best_mean[2].clamp(0.0, 255.0) as u8,
        src_pixel[3],
    ])
}

async fn process_kuwahara_rows(
    src: Arc<ImageBuffer<Rgba<u8>, Vec<u8>>>,
    dst: Arc<Mutex<ImageBuffer<Rgba<u8>, Vec<u8>>>>,
    integral: Arc<IntegralImage>,
    radius: i32,
    start_row: u32,
    end_row: u32,
) {
    let width = src.dimensions().0;
    let mut local_pixels = Vec::new();

    for y in start_row..end_row {
        for x in 0..width {
            let pixel = kuwahara_filter_pixel(&src, &integral, x as i32, y as i32, radius);
            local_pixels.push((x, y, pixel));
        }
    }

    let mut dst_locked = dst.lock().await;
    for (x, y, pixel) in local_pixels {
        dst_locked.put_pixel(x, y, pixel);
    }
}

pub async fn apply_kuwahara_filter_async(
    img: &DynamicImage,
    radius: i32,
    num_tasks: usize,
) -> DynamicImage {
    let rgba = img.to_rgba8();
    let (width, height) = rgba.dimensions();
    
    let mut integral = IntegralImage::new(width as usize, height as usize);

    let start = Instant::now();
    integral.build(&rgba);
    let sat_time = start.elapsed();
    println!("SAT build time: {}ms", sat_time.as_millis());

    let src = Arc::new(rgba);
    let dst = Arc::new(Mutex::new(ImageBuffer::new(width, height)));
    let integral = Arc::new(integral);

    let rows_per_task = height / num_tasks as u32;
    let mut tasks = Vec::new();

    for task_id in 0..num_tasks {
        let src = Arc::clone(&src);
        let dst = Arc::clone(&dst);
        let integral = Arc::clone(&integral);

        let task = task::spawn(async move {
            let start_row = task_id as u32 * rows_per_task;
            let end_row = if task_id == num_tasks - 1 {
                height
            } else {
                (task_id as u32 + 1) * rows_per_task
            };

            process_kuwahara_rows(src, dst, integral, radius, start_row, end_row).await;
        });

        tasks.push(task);
    }

    for task in tasks {
        task.await.unwrap();
    }

    let result = Arc::try_unwrap(dst)
        .unwrap()
        .into_inner();

    DynamicImage::ImageRgba8(result)
}