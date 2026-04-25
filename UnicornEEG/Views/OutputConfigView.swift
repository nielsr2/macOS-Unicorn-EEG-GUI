/*
 * OutputConfigView.swift
 * UnicornEEG
 *
 * Toggle switches and settings for the three output modes:
 * text file, LSL stream, and audio output.
 */

import SwiftUI

struct OutputConfigView: View {
    @EnvironmentObject var engine: StreamEngine

    // Text output
    @State private var textEnabled = false
    @State private var textFilePath = ""

    // LSL output
    @State private var lslEnabled = false
    @State private var lslStreamName = "Unicorn"

    // Audio output
    @State private var audioEnabled = false
    @State private var audioDevices: [AudioDeviceInfo] = []
    @State private var selectedAudioDevice: Int = -1
    @State private var audioSampleRate: Float = 44100
    @State private var audioBufferSize: Float = 2.0
    @State private var audioBlockSize: Float = 0.01
    @State private var audioHPFilter: Float = 10.0
    @State private var audioAutoScale = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Configuration").font(.headline)

            HStack(alignment: .top, spacing: 24) {
                // Text file output
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Text File", isOn: $textEnabled)
                        .onChange(of: textEnabled) { _ in
                            updateOutputs()
                        }
                    if textEnabled {
                        HStack {
                            TextField("File path", text: $textFilePath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button("Browse...") {
                                browseForFile()
                            }
                        }
                    }
                }
                .frame(minWidth: 200, alignment: .leading)

                Divider().frame(height: 60)

                // LSL output
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("LSL Raw EEG", isOn: $lslEnabled)
                        .onChange(of: lslEnabled) { _ in
                            updateOutputs()
                        }
                    if lslEnabled {
                        HStack {
                            Text("Name:")
                            TextField("Stream name", text: $lslStreamName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }

                    Toggle("LSL Band Power", isOn: $engine.bandPowerLSLEnabled)
                }
                .frame(minWidth: 200, alignment: .leading)

                Divider().frame(height: 60)

                // Audio output
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Audio", isOn: $audioEnabled)
                        .onChange(of: audioEnabled) { _ in
                            if audioEnabled {
                                audioDevices = AudioOutput.listDevices()
                                if selectedAudioDevice < 0,
                                   let def = audioDevices.first(where: { $0.isDefault }) {
                                    selectedAudioDevice = def.index
                                }
                            }
                            updateOutputs()
                        }
                    if audioEnabled {
                        Picker("Device:", selection: $selectedAudioDevice) {
                            ForEach(audioDevices, id: \.index) { device in
                                Text(device.name).tag(device.index)
                            }
                        }
                        .frame(width: 200)

                        HStack {
                            Text("Rate:")
                            TextField("Hz", value: $audioSampleRate, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("Hz")
                        }

                        Toggle("Auto scale", isOn: $audioAutoScale)
                    }
                }
                .frame(minWidth: 200, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        .disabled(engine.isStreaming)
    }

    private func updateOutputs() {
        engine.removeAllOutputs()

        if textEnabled && !textFilePath.isEmpty {
            engine.addOutput(TextFileOutput(filePath: textFilePath))
        }

        if lslEnabled {
            engine.addOutput(LSLOutput(streamName: lslStreamName))
        }

        if audioEnabled {
            var config = AudioOutputConfig()
            config.outputDeviceIndex = selectedAudioDevice
            config.sampleRate = audioSampleRate
            config.bufferSize = audioBufferSize
            config.blockSize = audioBlockSize
            config.hpFilterTimeConstant = audioHPFilter
            config.autoScale = audioAutoScale
            engine.addOutput(AudioOutput(config: config))
        }
    }

    private func browseForFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "unicorn_data.txt"
        if panel.runModal() == .OK, let url = panel.url {
            textFilePath = url.path
            updateOutputs()
        }
    }
}
