package main

import (
	"fmt"
	"sync"
)

// Linear Congruential Generator - same formula across all languages
func lcgRandom(seed *uint32) float64 {
	*seed = *seed*1664525 + 1013904223
	return float64(*seed&0x7FFFFFFF) / float64(0x7FFFFFFF)
}

func monteCarloWorker(samples int, seed uint32) int {
	inside := 0

	for range samples {
		x := lcgRandom(&seed)
		y := lcgRandom(&seed)
		if x*x + y*y <= 1.0 {
			inside++
		}
	}

	return inside
}

func monteCarloOperation(totalSamples int, numWorkers int) {
	if numWorkers <= 0 {
		numWorkers = 1
	}

	samplesPerWorker := totalSamples / numWorkers
	remainder := totalSamples % numWorkers

	var wg sync.WaitGroup
	results := make(chan int, numWorkers)

	for i := range numWorkers {
		samples := samplesPerWorker
		if i == numWorkers-1 {
			samples += remainder
		}

		wg.Add(1)
		go func(workerID int, numSamples int) {
			defer wg.Done()
			seed := uint32(12345 + workerID*67890) // Consistent seed pattern
			inside := monteCarloWorker(numSamples, seed)
			results <- inside
		}(i, samples)
	}

	go func() {
		wg.Wait()
		close(results)
	}()

	totalInside := 0
	for inside := range results {
		totalInside += inside
	}

	piEstimate := 4.0 * float64(totalInside) / float64(totalSamples)

	fmt.Printf("Monte Carlo Pi Estimation\n")
	fmt.Printf("Total samples: %d\n", totalSamples)
	fmt.Printf("Points inside circle: %d\n", totalInside)
	fmt.Printf("Pi estimate: %.6f\n", piEstimate)
	fmt.Printf("Error: %.6f\n", 3.141592653589793 - piEstimate)
}
