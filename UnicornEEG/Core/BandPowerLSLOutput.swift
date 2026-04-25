/*
 * BandPowerLSLOutput.swift
 * UnicornEEG
 *
 * Streams computed frequency band powers to a separate LSL stream.
 * 45 channels: 8 EEG channels × 5 bands + 5 averaged bands.
 */

import Foundation

class BandPowerLSLOutput {
    var streamName: String
    private var outlet: lsl_outlet?

    // 8 channels × 5 bands + 5 averages = 45
    static let channelCount: Int32 = 45
    // Band power updates at ~2 Hz (250 Hz / 125 hop)
    static let nominalRate: Double = 2.0

    init(streamName: String = "UnicornBands") {
        self.streamName = streamName
    }

    func start() {
        let uid = randomUID(length: 8)

        let info = lsl_create_streaminfo(
            streamName,
            "FFT",
            BandPowerLSLOutput.channelCount,
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

        let bandNames = ["delta", "theta", "alpha", "beta", "gamma"]

        // Per-channel band powers: delta_eeg1, delta_eeg2, ..., gamma_eeg8
        for band in bandNames {
            for ch in 1...8 {
                let chn = lsl_append_child(chns, "channel")
                lsl_append_child_value(chn, "label", "\(band)_eeg\(ch)")
                lsl_append_child_value(chn, "unit", "log10(µV²)")
                lsl_append_child_value(chn, "type", band.uppercased())
            }
        }

        // Average band powers
        for band in bandNames {
            let chn = lsl_append_child(chns, "channel")
            lsl_append_child_value(chn, "label", "\(band)_avg")
            lsl_append_child_value(chn, "unit", "log10(µV²)")
            lsl_append_child_value(chn, "type", band.uppercased())
        }

        outlet = lsl_create_outlet(info, 0, 360)
        lsl_destroy_streaminfo(info)
    }

    func pushResult(_ result: BandPowerResult) {
        guard let outlet = outlet else { return }

        // Pack into flat array: [delta_ch1..delta_ch8, theta_ch1..theta_ch8, ..., gamma_ch1..gamma_ch8, delta_avg..gamma_avg]
        var dat = [Float](repeating: 0, count: Int(BandPowerLSLOutput.channelCount))

        for band in 0..<FrequencyBand.count {
            for ch in 0..<8 {
                dat[band * 8 + ch] = result.perChannel[ch][band]
            }
        }

        // Averages at the end (indices 40-44)
        for band in 0..<FrequencyBand.count {
            dat[40 + band] = result.average[band]
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
