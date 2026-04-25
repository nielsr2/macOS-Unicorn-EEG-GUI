/*
 * SignalQualityProcessor.swift
 * UnicornEEG
 *
 * Infers per-electrode signal quality from the EEG data itself.
 * Computes RMS amplitude, ADC saturation, and a combined quality score
 * over a sliding 1-second window.
 */

import Foundation

enum SignalQuality: Int {
    case unknown = 0
    case good = 1
    case fair = 2
    case bad = 3
}

struct ChannelQualityInfo {
    let quality: SignalQuality
    let rms: Float         // µV
    let saturation: Float  // 0..1 ratio of clipped samples
}

class SignalQualityProcessor {
    let windowSize = 250  // 1 second at 250 Hz
    let channelCount = 8

    // ADC clipping threshold: 95% of the 24-bit max value scaled to µV
    // max ADC = 2^23 - 1 = 8388607, scaled: 8388607 * 4500000 / 50331642 ≈ 750 µV
    let saturationThreshold: Float = 750.0 * 0.95

    private var sampleBuffer: [[Float]]  // [channel][samples]
    private var bufferIndex: Int = 0
    private var bufferFull: Bool = false
    private var samplesSinceUpdate: Int = 0

    private(set) var channelQualities: [ChannelQualityInfo]

    init() {
        sampleBuffer = [[Float]](repeating: [Float](repeating: 0, count: windowSize), count: channelCount)
        channelQualities = [ChannelQualityInfo](repeating:
            ChannelQualityInfo(quality: .unknown, rms: 0, saturation: 0), count: channelCount)
    }

    /// Feed a sample. Call from acquisition thread.
    /// Returns true when qualities have been updated.
    func processSample(_ sample: UnicornSample) -> Bool {
        for ch in 0..<channelCount {
            sampleBuffer[ch][bufferIndex] = sample.eeg[ch]
        }
        bufferIndex = (bufferIndex + 1) % windowSize
        if bufferIndex == 0 { bufferFull = true }

        samplesSinceUpdate += 1

        // Update at ~4 Hz (every 62 samples)
        guard bufferFull, samplesSinceUpdate >= 62 else { return false }
        samplesSinceUpdate = 0

        computeQualities()
        return true
    }

    func reset() {
        for ch in 0..<channelCount {
            sampleBuffer[ch] = [Float](repeating: 0, count: windowSize)
        }
        bufferIndex = 0
        bufferFull = false
        samplesSinceUpdate = 0
        channelQualities = [ChannelQualityInfo](repeating:
            ChannelQualityInfo(quality: .unknown, rms: 0, saturation: 0), count: channelCount)
    }

    private func computeQualities() {
        var results = [ChannelQualityInfo]()

        for ch in 0..<channelCount {
            let data = sampleBuffer[ch]

            // RMS
            var sumSq: Float = 0
            var clippedCount: Int = 0
            for val in data {
                sumSq += val * val
                if abs(val) > saturationThreshold {
                    clippedCount += 1
                }
            }
            let rms = sqrt(sumSq / Float(windowSize))
            let saturation = Float(clippedCount) / Float(windowSize)

            // Combined quality
            let quality: SignalQuality
            if saturation > 0.01 {
                quality = .bad
            } else if rms > 500 || rms < 1 {
                quality = .bad
            } else if rms > 150 || rms < 5 {
                quality = .fair
            } else {
                quality = .good
            }

            results.append(ChannelQualityInfo(quality: quality, rms: rms, saturation: saturation))
        }

        channelQualities = results
    }
}
