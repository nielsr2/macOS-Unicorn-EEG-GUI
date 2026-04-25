/*
 * BandPowerLSLOutput.swift
 * UnicornEEG
 *
 * Streams computed frequency band powers and ratios to a separate LSL stream.
 * Dynamic channel count based on configured ratios.
 */

import Foundation

class BandPowerLSLOutput {
    var streamName: String
    private var outlet: lsl_outlet?
    private var channelCount: Int = 0

    static let nominalRate: Double = 2.0

    init(streamName: String = "UnicornBands") {
        self.streamName = streamName
    }

    func start(bandConfigs: [BandConfig], ratioConfigs: [BandRatioConfig]) {
        let bandCount = bandConfigs.count
        // 8 per-channel values per band + 1 average per band + ratios
        channelCount = bandCount * 8 + bandCount + ratioConfigs.count

        let uid = randomUID(length: 8)

        let info = lsl_create_streaminfo(
            streamName,
            "FFT",
            Int32(channelCount),
            BandPowerLSLOutput.nominalRate,
            cft_float32,
            uid
        )

        let desc = lsl_get_desc(info)
        let acquisition = lsl_append_child(desc, "acquisition")
        lsl_append_child_value(acquisition, "manufacturer", "Gtec")
        lsl_append_child_value(acquisition, "model", "Unicorn")
        lsl_append_child_value(acquisition, "processing", "FFT band power (log10 µV²)")

        let chns = lsl_append_child(desc, "channels")

        // Per-channel band powers
        for band in bandConfigs {
            for ch in 1...8 {
                let chn = lsl_append_child(chns, "channel")
                lsl_append_child_value(chn, "label", "\(band.name.lowercased())_eeg\(ch)")
                lsl_append_child_value(chn, "unit", "log10(µV²)")
                lsl_append_child_value(chn, "type", band.name.uppercased())
            }
        }

        // Average band powers
        for band in bandConfigs {
            let chn = lsl_append_child(chns, "channel")
            lsl_append_child_value(chn, "label", "\(band.name.lowercased())_avg")
            lsl_append_child_value(chn, "unit", "log10(µV²)")
            lsl_append_child_value(chn, "type", band.name.uppercased())
        }

        // Ratios
        for ratio in ratioConfigs {
            let numName = ratio.numerator < bandConfigs.count ? bandConfigs[ratio.numerator].name : "?"
            let denName = ratio.denominator < bandConfigs.count ? bandConfigs[ratio.denominator].name : "?"
            let chn = lsl_append_child(chns, "channel")
            lsl_append_child_value(chn, "label", "ratio_\(numName)_\(denName)")
            lsl_append_child_value(chn, "unit", "ratio")
            lsl_append_child_value(chn, "type", "RATIO")
        }

        outlet = lsl_create_outlet(info, 0, 360)
        lsl_destroy_streaminfo(info)
    }

    func pushResult(_ result: BandPowerResult) {
        guard let outlet = outlet else { return }

        var dat = [Float](repeating: 0, count: channelCount)
        let bandCount = result.average.count
        var idx = 0

        // Per-channel band powers
        for band in 0..<bandCount {
            for ch in 0..<8 {
                if band < result.perChannel[ch].count {
                    dat[idx] = result.perChannel[ch][band]
                }
                idx += 1
            }
        }

        // Averages
        for band in 0..<bandCount {
            dat[idx] = result.average[band]
            idx += 1
        }

        // Ratios
        for r in 0..<result.ratios.count {
            dat[idx] = result.ratios[r]
            idx += 1
        }

        lsl_push_sample_f(outlet, &dat)
    }

    func stop() {
        if let outlet = outlet {
            lsl_destroy_outlet(outlet)
        }
        outlet = nil
    }

    private func randomUID(length: Int) -> String {
        let charset = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<length).map { _ in charset.randomElement()! })
    }
}
