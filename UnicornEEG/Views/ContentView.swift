/*
 * ContentView.swift
 * UnicornEEG
 *
 * Main window layout: connection controls at top, waveform + band power center,
 * output config and status bar at bottom.
 */

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: StreamEngine
    @State private var showBandPanel = true

    var body: some View {
        VStack(spacing: 0) {
            ConnectionView()
                .padding()

            Divider()

            // Main content: waveforms + optional band power panel
            HStack(spacing: 0) {
                WaveformView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showBandPanel {
                    Divider()
                    BandPowerBarView()
                        .frame(width: 200)
                }
            }

            Divider()

            // Bottom controls
            HStack {
                OutputConfigView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Spacer()

                Toggle("Bands", isOn: $showBandPanel)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(.trailing)
            }

            Divider()

            StatusBarView()
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Error", isPresented: .init(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("OK") { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }
}
