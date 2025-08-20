package main

import (
	"fmt"
	"image"
	"image/color"
	"math"
	"sync"
	"time"
)

// IntegralImage for Summed-Area Table calculations
type IntegralImage struct {
	sum    []float64
	sumSq  []float64
	width  int
	height int
}

func NewIntegralImage(width, height int) *IntegralImage {
	size := (width + 1) * (height + 1) * 3
	return &IntegralImage{
		sum:    make([]float64, size),
		sumSq:  make([]float64, size),
		width:  width,
		height: height,
	}
}

func buildIntegralImages(img image.Image, integral *IntegralImage) {
	bounds := img.Bounds()
	w := bounds.Max.X
	h := bounds.Max.Y
	iw := integral.width + 1

	for y := 1; y <= h; y++ {
		for x := 1; x <= w; x++ {
			r, g, b, _ := img.At(x-1, y-1).RGBA()
			pixel := [3]float64{
				float64(r >> 8),
				float64(g >> 8),
				float64(b >> 8),
			}

			for ch := range 3 {
				val := pixel[ch]
				idx := (y*iw+x)*3 + ch
				idxUp := ((y-1)*iw+x)*3 + ch
				idxLeft := (y*iw+(x-1))*3 + ch
				idxDiag := ((y-1)*iw+(x-1))*3 + ch

				integral.sum[idx] = val +
					integral.sum[idxUp] +
					integral.sum[idxLeft] -
					integral.sum[idxDiag]

				integral.sumSq[idx] = val*val +
					integral.sumSq[idxUp] +
					integral.sumSq[idxLeft] -
					integral.sumSq[idxDiag]
			}
		}
	}
}

func getRegionStats(integral *IntegralImage, x1, y1, x2, y2 int) ([3]float64, [3]float64) {
	iw := integral.width + 1

	x1 = max(0, x1)
	y1 = max(0, y1)
	x2 = min(integral.width-1, x2)
	y2 = min(integral.height-1, y2)

	x1++
	y1++
	x2++
	y2++

	area := float64((x2 - x1 + 1) * (y2 - y1 + 1))
	var mean, variance [3]float64

	if area > 0 {
		for ch := range 3 {
			idxBR := (y2*iw+x2)*3 + ch
			idxBL := (y2*iw+x1-1)*3 + ch
			idxTR := ((y1-1)*iw+x2)*3 + ch
			idxTL := ((y1-1)*iw+x1-1)*3 + ch

			sum := integral.sum[idxBR] - integral.sum[idxBL] -
				integral.sum[idxTR] + integral.sum[idxTL]
			sumSq := integral.sumSq[idxBR] - integral.sumSq[idxBL] -
				integral.sumSq[idxTR] + integral.sumSq[idxTL]

			mean[ch] = sum / area
			variance[ch] = max((sumSq / area) - (mean[ch] * mean[ch]), 0)
		}
	}

	return mean, variance
}

func kuwaharaFilterPixel(srcImg image.Image, integral *IntegralImage, x, y, radius int) color.RGBA {
	minVariance := math.MaxFloat64
	var bestMean [3]float64

	quadrants := [][4]int{
		{x - radius, y - radius, x, y},
		{x, y - radius, x + radius, y},
		{x - radius, y, x, y + radius},
		{x, y, x + radius, y + radius},
	}

	for _, quad := range quadrants {
		mean, variance := getRegionStats(integral, quad[0], quad[1], quad[2], quad[3])
		totalVariance := variance[0] + variance[1] + variance[2]

		if totalVariance < minVariance {
			minVariance = totalVariance
			bestMean = mean
		}
	}

	_, _, _, a := srcImg.At(x, y).RGBA()

	return color.RGBA{
		R: uint8(math.Min(255, math.Max(0, bestMean[0]))),
		G: uint8(math.Min(255, math.Max(0, bestMean[1]))),
		B: uint8(math.Min(255, math.Max(0, bestMean[2]))),
		A: uint8(a >> 8),
	}
}

type KuwaharaWorkerTask struct {
	srcImg   image.Image
	dstImg   *image.RGBA
	integral *IntegralImage
	radius   int
	startRow int
	endRow   int
}

func kuwaharaWorker(task *KuwaharaWorkerTask, wg *sync.WaitGroup) {
	defer wg.Done()

	bounds := task.srcImg.Bounds()
	for y := task.startRow; y < task.endRow; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			pixel := kuwaharaFilterPixel(task.srcImg, task.integral, x, y, task.radius)
			task.dstImg.Set(x, y, pixel)
		}
	}
}

func applyKuwaharaFilter(srcImg image.Image, radius int, numWorkers int) *image.RGBA {
	bounds := srcImg.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y

	integral := NewIntegralImage(width, height)

	start := time.Now()
	buildIntegralImages(srcImg, integral)
	satTime := time.Since(start)
	fmt.Printf("SAT build time: %dms\n", satTime.Milliseconds())

	dstImg := image.NewRGBA(bounds)

	var wg sync.WaitGroup
	rowsPerWorker := height / numWorkers

	for i := 0; i < numWorkers; i++ {
		startRow := i * rowsPerWorker
		endRow := startRow + rowsPerWorker
		if i == numWorkers-1 {
			endRow = height
		}

		task := &KuwaharaWorkerTask{
			srcImg:   srcImg,
			dstImg:   dstImg,
			integral: integral,
			radius:   radius,
			startRow: startRow,
			endRow:   endRow,
		}

		wg.Add(1)
		go kuwaharaWorker(task, &wg)
	}

	wg.Wait()
	return dstImg
}
