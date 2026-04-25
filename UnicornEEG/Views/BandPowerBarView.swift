/*
 * BandPowerBarView.swift
 * UnicornEEG
 *
 * Real-time vertical bar chart showing frequency band power levels and
 * computed band ratios, with configurable ranges and ratio definitions.
 */

import SwiftUI

struct BandPowerBarView: View {
    @EnvironmentObject var engine: StreamEngine
    @State private var showConfig = false

    private let bandColors: [Color] = [
        Color(red: 0.9, green: 0.2, blue: 0.2),  // Delta
        Color(red: 0.9, green: 0.6, blue: 0.1),  // Theta
        Color(red: 0.2, green: 0.8, blue: 0.3),  // Alpha
        Color(red: 0.1, green: 0.7, blue: 0.7),  // Beta
        Color(red: 0.6, green: 0.2, blue: 0.8),  // Gamma
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Band Power")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: { showConfig.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Configure bands & ratios")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Bar chart
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { _ in
                let result = engine.bandPowerProcessor.latestResult
                let bands = engine.bandPowerProcessor.bandConfigs
                let values = result?.average ?? [Float](repeating: -10, count: bands.count)
                let ratioConfigs = engine.bandPowerProcessor.ratioConfigs
                let ratioValues = result?.ratios ?? [Float](repeating: 0, count: ratioConfigs.count)

                let minDB: Float = -8.0
                let maxDB: Float = -1.0

                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<bands.count, id: \.self) { i in
                            let normalized = CGFloat(max(0, min(1, (values[i] - minDB) / (maxDB - minDB))))
                            let barHeight = max(2, normalized * (geo.size.height - 30))
                            let color = i < bandColors.count ? bandColors[i] : .gray

                            VStack(spacing: 2) {
                                Spacer()

                                Text(String(format: "%.1f", values[i]))
                                    .font(.system(size: 8))
                                    .foregroundColor(color.opacity(0.8))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(height: barHeight)

                                VStack(spacing: 0) {
                                    Text(bands[i].name)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(color)
                                    Text("\(Int(bands[i].low))-\(Int(bands[i].high))")
                                        .font(.system(size: 7))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                // Ratios section
                if !ratioConfigs.isEmpty {
                    Divider().padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ratios")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(0..<ratioConfigs.count, id: \.self) { i in
                            let rc = ratioConfigs[i]
                            let val = ratioValues[i]
                            let numName = rc.numerator < bands.count ? bands[rc.numerator].name : "?"
                            let denName = rc.denominator < bands.count ? bands[rc.denominator].name : "?"

                            HStack(spacing: 4) {
                                Text("\(numName)/\(denName)")
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: 70, alignment: .leading)

                                // Mini horizontal bar
                                GeometryReader { geo in
                                    let maxRatio: CGFloat = 5.0
                                    let barWidth = max(2, min(geo.size.width, CGFloat(val) / maxRatio * geo.size.width))

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(ratioColor(val))
                                        .frame(width: barWidth, height: 12)
                                }
                                .frame(height: 12)

                                Text(String(format: "%.2f", val))
                                    .font(.system(size: 9, weight: .medium))
                                    .frame(width: 35, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }

            // Config panel
            if showConfig {
                BandConfigView(
                    bandConfigs: Binding(
                        get: { engine.bandPowerProcessor.bandConfigs },
                        set: { engine.bandPowerProcessor.bandConfigs = $0 }
                    ),
                    ratioConfigs: Binding(
                        get: { engine.bandPowerProcessor.ratioConfigs },
                        set: { engine.bandPowerProcessor.ratioConfigs = $0 }
                    )
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func ratioColor(_ value: Float) -> Color {
        if value < 0.5 { return .blue }
        if value < 1.0 { return .cyan }
        if value < 2.0 { return .green }
        if value < 3.0 { return .yellow }
        return .orange
    }
}

// MARK: - Configuration Panel

struct BandConfigView: View {
    @Binding var bandConfigs: [BandConfig]
    @Binding var ratioConfigs: [BandRatioConfig]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            // Band ranges
            Text("Band Ranges (Hz)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)

            ForEach(0..<bandConfigs.count, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("", text: Binding(
                        get: { bandConfigs[i].name },
                        set: { bandConfigs[i].name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)

                    TextField("", value: Binding(
                        get: { bandConfigs[i].low },
                        set: { bandConfigs[i].low = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 35)

                    Text("–")

                    TextField("", value: Binding(
                        get: { bandConfigs[i].high },
                        set: { bandConfigs[i].high = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 35)

                    Text("Hz").font(.system(size: 9)).foregroundColor(.secondary)

                    Button(action: {
                        // Remove band and fix ratio indices
                        ratioConfigs.removeAll { $0.numerator == i || $0.denominator == i }
                        for j in 0..<ratioConfigs.count {
                            if ratioConfigs[j].numerator > i { ratioConfigs[j].numerator -= 1 }
                            if ratioConfigs[j].denominator > i { ratioConfigs[j].denominator -= 1 }
                        }
                        bandConfigs.remove(at: i)
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(bandConfigs.count <= 1)
                }
                .font(.system(size: 10))
            }

            Button(action: {
                let newId = (bandConfigs.map(\.id).max() ?? -1) + 1
                let lastHigh = bandConfigs.last?.high ?? 50
                bandConfigs.append(BandConfig(id: newId, name: "Band\(bandConfigs.count + 1)", low: lastHigh, high: lastHigh + 20))
            }) {
                Label("Add band", systemImage: "plus.circle")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Divider()

            // Ratios
            Text("Ratios")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)

            ForEach(0..<ratioConfigs.count, id: \.self) { i in
                HStack(spacing: 4) {
                    Picker("", selection: Binding(
                        get: { ratioConfigs[i].numerator },
                        set: { ratioConfigs[i].numerator = $0 }
                    )) {
                        ForEach(0..<bandConfigs.count, id: \.self) { b in
                            Text(bandConfigs[b].name).tag(b)
                        }
                    }
                    .frame(width: 65)

                    Text("/")

                    Picker("", selection: Binding(
                        get: { ratioConfigs[i].denominator },
                        set: { ratioConfigs[i].denominator = $0 }
                    )) {
                        ForEach(0..<bandConfigs.count, id: \.self) { b in
                            Text(bandConfigs[b].name).tag(b)
                        }
                    }
                    .frame(width: 65)

                    Button(action: {
                        ratioConfigs.remove(at: i)
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 10))
            }

            HStack {
                Button(action: {
                    let newId = (ratioConfigs.map(\.id).max() ?? -1) + 1
                    ratioConfigs.append(BandRatioConfig(id: newId, numerator: 0, denominator: min(1, bandConfigs.count - 1)))
                }) {
                    Label("Add ratio", systemImage: "plus.circle")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Reset all") {
                    bandConfigs = FrequencyBand.defaultConfigs
                    ratioConfigs = [
                        BandRatioConfig(id: 0, numerator: 2, denominator: 3),
                        BandRatioConfig(id: 1, numerator: 1, denominator: 3),
                    ]
                }
                .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}
