/*
 * BandPowerProcessor.swift
 * UnicornEEG
 *
 * Real-time FFT-based frequency band power extraction using Apple's Accelerate framework.
 * Computes power in standard EEG bands (delta, theta, alpha, beta, gamma) for each
 * EEG channel using a sliding window FFT.
 */

import Foundation
import Accelerate

struct BandPowerResult {
    let perChannel: [[Float]]  // [8 channels][5 bands]
    let average: [Float]       // [5 bands] averaged across channels
}

enum FrequencyBand: Int, CaseIterable {
    case delta = 0  // 0.5–4 Hz
    case theta = 1  // 4–8 Hz
    case alpha = 2  // 8–13 Hz
    case beta  = 3  // 13–30 Hz
    case gamma = 4  // 30–50 Hz

    var range: (low: Float, high: Float) {
        switch self {
        case .delta: return (0.5, 4.0)
        case .theta: return (4.0, 8.0)
        case .alpha: return (8.0, 13.0)
        case .beta:  return (13.0, 30.0)
        case .gamma: return (30.0, 50.0)
        }
    }

    var label: String {
        switch self {
        case .delta: return "Delta"
        case .theta: return "Theta"
        case .alpha: return "Alpha"
        case .beta:  return "Beta"
        case .gamma: return "Gamma"
        }
    }

    static let count = 5
}

class BandPowerProcessor {
    let fftSize: Int = 512           // next power of 2 above 500 (2 sec at 250 Hz)
    let hopSize: Int = 125           // 0.5 seconds between updates
    let sampleRate: Float = 250.0
    let eegChannelCount: Int = 8

    // FFT setup
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var hannWindow: [Float]

    // Sample accumulation buffer per channel
    private var sampleBuffer: [[Float]]  // [channel][samples]
    private var samplesAccumulated: Int = 0
    private var samplesSinceLastHop: Int = 0

    // Callback when new band powers are available
    var onBandPowerComputed: ((BandPowerResult) -> Void)?

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        sampleBuffer = [[Float]](repeating: [Float](repeating: 0, count: fftSize), count: eegChannelCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Feed a single sample. Call from the acquisition thread.
    func processSample(_ sample: UnicornSample) {
        // Shift buffer left by 1 and append new sample for each channel
        for ch in 0..<eegChannelCount {
            if samplesAccumulated < fftSize {
                sampleBuffer[ch][samplesAccumulated] = sample.eeg[ch]
            } else {
                // Shift left by 1
                sampleBuffer[ch].removeFirst()
                sampleBuffer[ch].append(sample.eeg[ch])
            }
        }

        if samplesAccumulated < fftSize {
            samplesAccumulated += 1
        }
        samplesSinceLastHop += 1

        // Only compute FFT once we have a full window and it's time for a hop
        guard samplesAccumulated >= fftSize, samplesSinceLastHop >= hopSize else { return }
        samplesSinceLastHop = 0

        let result = computeBandPowers()
        onBandPowerComputed?(result)
    }

    func reset() {
        for ch in 0..<eegChannelCount {
            sampleBuffer[ch] = [Float](repeating: 0, count: fftSize)
        }
        samplesAccumulated = 0
        samplesSinceLastHop = 0
    }

    // MARK: - FFT Computation

    private func computeBandPowers() -> BandPowerResult {
        let n = fftSize
        let halfN = n / 2
        let freqResolution = sampleRate / Float(n)  // Hz per bin

        var perChannel = [[Float]](repeating: [Float](repeating: 0, count: FrequencyBand.count), count: eegChannelCount)

        for ch in 0..<eegChannelCount {
            // Apply Hann window
            var windowed = [Float](repeating: 0, count: n)
            vDSP_vmul(sampleBuffer[ch], 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

            // Convert to split complex for FFT
            var realPart = [Float](repeating: 0, count: halfN)
            var imagPart = [Float](repeating: 0, count: halfN)

            // Pack into even/odd for real FFT
            for i in 0..<halfN {
                realPart[i] = windowed[2 * i]
                imagPart[i] = windowed[2 * i + 1]
            }

            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

            // Forward FFT
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

            // Compute power spectrum (magnitude squared)
            var magnitudes = [Float](repeating: 0, count: halfN)
            vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

            // Scale by 1/N²
            let scale = 1.0 / Float(n * n)
            vDSP_vsmul(magnitudes, 1, [scale], &magnitudes, 1, vDSP_Length(halfN))

            // Extract band powers
            for band in FrequencyBand.allCases {
                let lowBin = max(1, Int(band.range.low / freqResolution))
                let highBin = min(halfN - 1, Int(band.range.high / freqResolution))

                var power: Float = 0
                if highBin >= lowBin {
                    for bin in lowBin...highBin {
                        power += magnitudes[bin]
                    }
                }

                // Log scale (dB-like) — log10(power + epsilon) to avoid log(0)
                perChannel[ch][band.rawValue] = log10(power + 1e-10)
            }
        }

        // Average across channels
        var average = [Float](repeating: 0, count: FrequencyBand.count)
        for band in 0..<FrequencyBand.count {
            var sum: Float = 0
            for ch in 0..<eegChannelCount {
                sum += perChannel[ch][band]
            }
            average[band] = sum / Float(eegChannelCount)
        }

        return BandPowerResult(perChannel: perChannel, average: average)
    }
}
