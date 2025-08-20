package main

import (
	"image"
	"image/color"
	"math"
	"sync"
)

func generateGaussianKernel(radius int) []float64 {
	size := 2*radius + 1
	kernel := make([]float64, size)
	sigma := float64(radius) / 3.0
	sum := 0.0

	for i := range size {
		x := float64(i - radius)
		kernel[i] = math.Exp(-(x * x) / (2.0 * sigma * sigma))
		sum += kernel[i]
	}

	for i := range kernel {
		kernel[i] /= sum
	}

	return kernel
}

func blurHorizontal(srcImg image.Image, dstImg *image.RGBA, kernel []float64, radius int, startY, endY int) {
	bounds := srcImg.Bounds()
	for y := startY; y < endY; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			var rSum, gSum, bSum, aSum float64

			for k := -radius; k <= radius; k++ {
				sx := x + k
				if sx < bounds.Min.X {
					sx = bounds.Min.X
				} else if sx >= bounds.Max.X {
					sx = bounds.Max.X - 1
				}

				weight := kernel[k+radius]
				r, g, b, a := srcImg.At(sx, y).RGBA()
				rSum += float64(r>>8) * weight
				gSum += float64(g>>8) * weight
				bSum += float64(b>>8) * weight
				aSum += float64(a>>8) * weight
			}

			dstImg.Set(x, y, color.RGBA{
				R: uint8(math.Round(rSum)),
				G: uint8(math.Round(gSum)),
				B: uint8(math.Round(bSum)),
				A: uint8(math.Round(aSum)),
			})
		}
	}
}

func transposeImage(src *image.RGBA) *image.RGBA {
	bounds := src.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y

	dst := image.NewRGBA(image.Rect(0, 0, height, width))

	for y := range height {
		for x := range width {
			pixel := src.At(x, y)
			dst.Set(y, x, pixel)
		}
	}

	return dst
}

func applyGaussianBlur(srcImg image.Image, radius int, numWorkers int) *image.RGBA {
	bounds := srcImg.Bounds()
	kernel := generateGaussianKernel(radius)

	// Phase 1: Horizontal blur
	horizontal := image.NewRGBA(bounds)

	var wg sync.WaitGroup
	rowsPerWorker := bounds.Max.Y / numWorkers

	for i := range numWorkers {
		startY := i * rowsPerWorker
		endY := startY + rowsPerWorker
		if i == numWorkers-1 {
			endY = bounds.Max.Y
		}

		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			blurHorizontal(srcImg, horizontal, kernel, radius, start, end)
		}(startY, endY)
	}
	wg.Wait()

	// Transpose for vertical pass
	transposed := transposeImage(horizontal)

	// Phase 2: Vertical blur (horizontal on transposed)
	transposedBounds := transposed.Bounds()
	blurred := image.NewRGBA(transposedBounds)

	rowsPerWorker = transposedBounds.Max.Y / numWorkers

	for i := 0; i < numWorkers; i++ {
		startY := i * rowsPerWorker
		endY := startY + rowsPerWorker
		if i == numWorkers-1 {
			endY = transposedBounds.Max.Y
		}

		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			blurHorizontal(transposed, blurred, kernel, radius, start, end)
		}(startY, endY)
	}
	wg.Wait()

	// Transpose back
	return transposeImage(blurred)
}
