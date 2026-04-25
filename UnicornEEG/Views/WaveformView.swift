/*
 * WaveformView.swift
 * UnicornEEG
 *
 * Real-time display of EEG, accelerometer, gyroscope, battery, and counter
 * waveforms using Canvas + TimelineView.
 */

import SwiftUI

// Channel definition: index into the 16-element allChannels array
private struct ChannelDef {
    let index: Int
    let label: String
    let unit: String
    let color: Color
    let group: ChannelGroup
    let fixedPeak: Float?  // nil = auto/manual scale, non-nil = always use this range (±fixedPeak)
    let showDelta: Bool    // true = render as difference between consecutive samples
    init(index: Int, label: String, unit: String, color: Color, group: ChannelGroup, fixedPeak: Float?, showDelta: Bool = false) {
        self.index = index; self.label = label; self.unit = unit; self.color = color
        self.group = group; self.fixedPeak = fixedPeak; self.showDelta = showDelta
    }
}

private enum ChannelGroup: String, CaseIterable {
    case eeg = "EEG"
    case accel = "Accel"
    case gyro = "Gyro"
    case aux = "Aux"
    case bands = "Bands"
}

// Sensor ranges from the Unicorn data sheet:
//   Accel: 16-bit / 4096 → ±8g max, ±4g is a useful display range
//   Gyro:  16-bit / 32.8 → ±1000°/s max, ±500°/s is a useful display range
//   Battery: 0–100%, center around 50
//   Counter: always increasing, must auto-scale

private let allChannels: [ChannelDef] = [
    // EEG (indices 0-7) — auto-scaled
    .init(index: 0, label: "EEG1", unit: "µV", color: .red, group: .eeg, fixedPeak: nil),
    .init(index: 1, label: "EEG2", unit: "µV", color: .orange, group: .eeg, fixedPeak: nil),
    .init(index: 2, label: "EEG3", unit: "µV", color: .yellow, group: .eeg, fixedPeak: nil),
    .init(index: 3, label: "EEG4", unit: "µV", color: .green, group: .eeg, fixedPeak: nil),
    .init(index: 4, label: "EEG5", unit: "µV", color: .cyan, group: .eeg, fixedPeak: nil),
    .init(index: 5, label: "EEG6", unit: "µV", color: .blue, group: .eeg, fixedPeak: nil),
    .init(index: 6, label: "EEG7", unit: "µV", color: .purple, group: .eeg, fixedPeak: nil),
    .init(index: 7, label: "EEG8", unit: "µV", color: .pink, group: .eeg, fixedPeak: nil),
    // Accelerometer (indices 8-10) — fixed ±4g
    .init(index: 8,  label: "Acc X", unit: "g", color: Color(red: 0.8, green: 0.3, blue: 0.1), group: .accel, fixedPeak: 4.0),
    .init(index: 9,  label: "Acc Y", unit: "g", color: Color(red: 0.6, green: 0.5, blue: 0.1), group: .accel, fixedPeak: 4.0),
    .init(index: 10, label: "Acc Z", unit: "g", color: Color(red: 0.4, green: 0.6, blue: 0.2), group: .accel, fixedPeak: 4.0),
    // Gyroscope (indices 11-13) — fixed ±500°/s
    .init(index: 11, label: "Gyr X", unit: "°/s", color: Color(red: 0.1, green: 0.6, blue: 0.7), group: .gyro, fixedPeak: 500.0),
    .init(index: 12, label: "Gyr Y", unit: "°/s", color: Color(red: 0.3, green: 0.3, blue: 0.8), group: .gyro, fixedPeak: 500.0),
    .init(index: 13, label: "Gyr Z", unit: "°/s", color: Color(red: 0.6, green: 0.2, blue: 0.7), group: .gyro, fixedPeak: 500.0),
    // Aux (indices 14-15) — fixed ranges
    .init(index: 14, label: "Battery", unit: "%", color: Color(red: 0.9, green: 0.7, blue: 0.1), group: .aux, fixedPeak: 110.0),
    .init(index: 15, label: "Δ Sample", unit: "gap", color: .gray, group: .aux, fixedPeak: 5.0, showDelta: true),
]

// Band power channels — indices into the bandPowerBuffer (5 channels)
private let bandChannels: [ChannelDef] = [
    .init(index: 0, label: "Delta",  unit: "dB", color: Color(red: 0.9, green: 0.2, blue: 0.2), group: .bands, fixedPeak: nil),
    .init(index: 1, label: "Theta",  unit: "dB", color: Color(red: 0.9, green: 0.6, blue: 0.1), group: .bands, fixedPeak: nil),
    .init(index: 2, label: "Alpha",  unit: "dB", color: Color(red: 0.2, green: 0.8, blue: 0.3), group: .bands, fixedPeak: nil),
    .init(index: 3, label: "Beta",   unit: "dB", color: Color(red: 0.1, green: 0.7, blue: 0.7), group: .bands, fixedPeak: nil),
    .init(index: 4, label: "Gamma",  unit: "dB", color: Color(red: 0.6, green: 0.2, blue: 0.8), group: .bands, fixedPeak: nil),
]

struct WaveformView: View {
    @EnvironmentObject var engine: StreamEngine

    @State private var displaySeconds: Double = 4.0
    @State private var autoScale: Bool = true
    @State private var amplitudeScale: Double = 100.0

    @State private var showEEG: Bool = true
    @State private var showAccel: Bool = false
    @State private var showGyro: Bool = false
    @State private var showAux: Bool = false
    @State private var showBands: Bool = false

    private var visibleMainChannels: [ChannelDef] {
        allChannels.filter { ch in
            switch ch.group {
            case .eeg: return showEEG
            case .accel: return showAccel
            case .gyro: return showGyro
            case .aux: return showAux
            case .bands: return false
            }
        }
    }

    private var visibleBandChannels: [ChannelDef] {
        showBands ? bandChannels : []
    }

    private var allVisibleChannels: [ChannelDef] {
        visibleMainChannels + visibleBandChannels
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Text("Time:")
                Slider(value: $displaySeconds, in: 1...30, step: 1)
                    .frame(width: 100)
                Text("\(displaySeconds, specifier: "%.0f")s")

                Spacer().frame(width: 16)

                Toggle("Auto-scale", isOn: $autoScale)
                    .toggleStyle(.checkbox)

                if !autoScale {
                    Spacer().frame(width: 8)
                    Text("Scale:")
                    Slider(value: $amplitudeScale, in: 10...500, step: 10)
                        .frame(width: 80)
                    TextField("", value: $amplitudeScale, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("\u{00B5}V")
                }

                Spacer().frame(width: 16)

                // Channel group toggles
                Toggle("EEG", isOn: $showEEG).toggleStyle(.checkbox)
                Toggle("Accel", isOn: $showAccel).toggleStyle(.checkbox)
                Toggle("Gyro", isOn: $showGyro).toggleStyle(.checkbox)
                Toggle("Aux", isOn: $showAux).toggleStyle(.checkbox)
                Toggle("Bands", isOn: $showBands).toggleStyle(.checkbox)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Waveform canvas
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                Canvas { context, size in
                    let displaySamples = Int(displaySeconds * Double(PacketParser.sampleRate))
                    let mainSamples = engine.ringBuffer.readLatest(maxCount: displaySamples)

                    // Band power updates at ~2 Hz, so scale sample count accordingly
                    let bandDisplaySamples = max(1, Int(displaySeconds * 2.0))
                    let bandSamples = engine.bandPowerBuffer.readLatest(maxCount: bandDisplaySamples)

                    let channels = allVisibleChannels
                    let leftMargin: CGFloat = 70
                    let plotWidth = size.width - leftMargin

                    guard !channels.isEmpty else { return }

                    let channelHeight = size.height / CGFloat(channels.count)

                    // Compute per-channel scale
                    var peaks = [Float](repeating: 1.0, count: channels.count)
                    for (ci, ch) in channels.enumerated() {
                        if let fixed = ch.fixedPeak {
                            peaks[ci] = fixed
                        } else if autoScale {
                            let data = ch.group == .bands ? bandSamples : mainSamples
                            if !data.isEmpty {
                                var peak: Float = 0.001
                                for sample in data {
                                    if ch.index < sample.count {
                                        let absVal = abs(sample[ch.index])
                                        if absVal > peak { peak = absVal }
                                    }
                                }
                                peaks[ci] = peak * 1.1
                            }
                        }
                    }

                    for (ci, ch) in channels.enumerated() {
                        let centerY = channelHeight * (CGFloat(ci) + 0.5)
                        let topY = channelHeight * CGFloat(ci)

                        // Channel label
                        let labelText = Text(ch.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ch.color)
                        context.draw(labelText, at: CGPoint(x: 35, y: centerY - 7))

                        // Axis: show ± range with unit
                        let scaleVal: String
                        if let fixed = ch.fixedPeak {
                            scaleVal = String(format: "±%.0f %@", fixed, ch.unit)
                        } else if autoScale {
                            let p = peaks[ci] / 1.1
                            if p >= 1000 {
                                scaleVal = String(format: "±%.0f %@", p, ch.unit)
                            } else if p >= 1 {
                                scaleVal = String(format: "±%.1f %@", p, ch.unit)
                            } else {
                                scaleVal = String(format: "±%.3f %@", p, ch.unit)
                            }
                        } else {
                            scaleVal = "±\(Int(amplitudeScale)) \(ch.unit)"
                        }
                        let unitText = Text(scaleVal)
                            .font(.system(size: 8))
                            .foregroundColor(ch.color.opacity(0.7))
                        context.draw(unitText, at: CGPoint(x: 35, y: centerY + 7))

                        // Separator line
                        var sepLine = Path()
                        sepLine.move(to: CGPoint(x: leftMargin, y: topY))
                        sepLine.addLine(to: CGPoint(x: size.width, y: topY))
                        context.stroke(sepLine, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)

                        // Center line
                        var centerLine = Path()
                        centerLine.move(to: CGPoint(x: leftMargin, y: centerY))
                        centerLine.addLine(to: CGPoint(x: size.width, y: centerY))
                        context.stroke(centerLine, with: .color(.gray.opacity(0.1)), lineWidth: 0.5)

                        // Select data source based on channel group
                        let data = ch.group == .bands ? bandSamples : mainSamples
                        guard !data.isEmpty else { continue }

                        // Y scale
                        let yScale: CGFloat
                        if ch.fixedPeak != nil || autoScale {
                            yScale = channelHeight * 0.4 / CGFloat(peaks[ci])
                        } else {
                            yScale = channelHeight * 0.4 / CGFloat(amplitudeScale)
                        }

                        // Draw waveform
                        var path = Path()
                        let sampleCount = data.count
                        let xStep = plotWidth / max(1, CGFloat(sampleCount - 1))

                        if ch.showDelta {
                            for i in 0..<sampleCount {
                                let x = leftMargin + CGFloat(i) * xStep
                                let val: Float = i > 0
                                    ? data[i][ch.index] - data[i - 1][ch.index]
                                    : 0
                                let y = centerY - CGFloat(val) * yScale
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        } else {
                            for (i, sample) in data.enumerated() {
                                guard ch.index < sample.count else { continue }
                                let x = leftMargin + CGFloat(i) * xStep
                                let y = centerY - CGFloat(sample[ch.index]) * yScale
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }

                        context.stroke(path, with: .color(ch.color), lineWidth: ch.group == .bands ? 2.0 : 1.0)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
