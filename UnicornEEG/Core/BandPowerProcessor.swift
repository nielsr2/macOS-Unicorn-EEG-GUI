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

struct BandRatioConfig: Identifiable {
    let id: Int
    var numerator: Int    // index into bandConfigs
    var denominator: Int  // index into bandConfigs
}

struct BandPowerResult {
    let perChannel: [[Float]]  // [8 channels][5 bands]
    let average: [Float]       // [5 bands] averaged across channels
    let ratios: [Float]        // computed ratios (linear scale, averaged across channels)
}

struct BandConfig: Identifiable {
    let id: Int
    var name: String
    var low: Float
    var high: Float
}

enum FrequencyBand: Int, CaseIterable {
    case delta = 0
    case theta = 1
    case alpha = 2
    case beta  = 3
    case gamma = 4

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

    static var defaultConfigs: [BandConfig] {
        [
            BandConfig(id: 0, name: "Delta", low: 0.5, high: 4.0),
            BandConfig(id: 1, name: "Theta", low: 4.0, high: 8.0),
            BandConfig(id: 2, name: "Alpha", low: 8.0, high: 13.0),
            BandConfig(id: 3, name: "Beta",  low: 13.0, high: 30.0),
            BandConfig(id: 4, name: "Gamma", low: 30.0, high: 50.0),
        ]
    }
}

class BandPowerProcessor {
    let fftSize: Int = 512
    let hopSize: Int = 125
    let sampleRate: Float = 250.0
    let eegChannelCount: Int = 8

    /// Configurable band frequency ranges
    var bandConfigs: [BandConfig] = FrequencyBand.defaultConfigs

    /// Configurable band power ratios (e.g. alpha/beta, theta/beta)
    var ratioConfigs: [BandRatioConfig] = [
        BandRatioConfig(id: 0, numerator: 2, denominator: 3),  // Alpha/Beta
        BandRatioConfig(id: 1, numerator: 1, denominator: 3),  // Theta/Beta
    ]

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var hannWindow: [Float]

    private var sampleBuffer: [[Float]]
    private var samplesAccumulated: Int = 0
    private var samplesSinceLastHop: Int = 0

    /// Latest result for the bar chart (updated ~2 Hz)
    var latestResult: BandPowerResult?

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

    func processSample(_ sample: UnicornSample) {
        for ch in 0..<eegChannelCount {
            if samplesAccumulated < fftSize {
                sampleBuffer[ch][samplesAccumulated] = sample.eeg[ch]
            } else {
                sampleBuffer[ch].removeFirst()
                sampleBuffer[ch].append(sample.eeg[ch])
            }
        }

        if samplesAccumulated < fftSize {
            samplesAccumulated += 1
        }
        samplesSinceLastHop += 1

        guard samplesAccumulated >= fftSize, samplesSinceLastHop >= hopSize else { return }
        samplesSinceLastHop = 0

        let result = computeBandPowers()
        latestResult = result
        onBandPowerComputed?(result)
    }

    func reset() {
        for ch in 0..<eegChannelCount {
            sampleBuffer[ch] = [Float](repeating: 0, count: fftSize)
        }
        samplesAccumulated = 0
        samplesSinceLastHop = 0
        latestResult = nil
    }

    // MARK: - FFT

    private func computeBandPowers() -> BandPowerResult {
        let n = fftSize
        let halfN = n / 2
        let freqResolution = sampleRate / Float(n)
        let bandCount = bandConfigs.count

        var perChannel = [[Float]](repeating: [Float](repeating: 0, count: bandCount), count: eegChannelCount)

        for ch in 0..<eegChannelCount {
            var windowed = [Float](repeating: 0, count: n)
            vDSP_vmul(sampleBuffer[ch], 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

            var realPart = [Float](repeating: 0, count: halfN)
            var imagPart = [Float](repeating: 0, count: halfN)

            for i in 0..<halfN {
                realPart[i] = windowed[2 * i]
                imagPart[i] = windowed[2 * i + 1]
            }

            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

            var magnitudes = [Float](repeating: 0, count: halfN)
            vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

            let scale = 1.0 / Float(n * n)
            vDSP_vsmul(magnitudes, 1, [scale], &magnitudes, 1, vDSP_Length(halfN))

            for (bi, band) in bandConfigs.enumerated() {
                let lowBin = max(1, Int(band.low / freqResolution))
                let highBin = min(halfN - 1, Int(band.high / freqResolution))

                var power: Float = 0
                if highBin >= lowBin {
                    for bin in lowBin...highBin {
                        power += magnitudes[bin]
                    }
                }

                perChannel[ch][bi] = log10(power + 1e-10)
            }
        }

        var average = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            var sum: Float = 0
            for ch in 0..<eegChannelCount {
                sum += perChannel[ch][band]
            }
            average[band] = sum / Float(eegChannelCount)
        }

        // Compute ratios in linear power space (10^logPower), averaged across channels
        var ratios = [Float]()
        for ratio in ratioConfigs {
            guard ratio.numerator < bandCount, ratio.denominator < bandCount else {
                ratios.append(0)
                continue
            }
            // Use linear power for the ratio, not log
            let numPower = pow(10.0, average[ratio.numerator])
            let denPower = pow(10.0, average[ratio.denominator])
            ratios.append(denPower > 1e-20 ? numPower / denPower : 0)
        }

        return BandPowerResult(perChannel: perChannel, average: average, ratios: ratios)
    }
}
