# Unicorn EEG macOS 2 LSL

A native macOS application for the [Unicorn Hybrid Black](https://www.unicorn-bi.com/) 8-channel EEG system. Open source, lightweight, and built for real-time streaming to [LabStreamingLayer (LSL)](https://labstreaminglayer.readthedocs.io) — no official macOS GUI required.

<!-- TODO: Add screenshot of the main window with waveforms and band power panel -->
![App Screenshot](UNICORN%20MACOS.png)

>Built on [unicorn2xx](https://github.com/robertoostenveld/unicorn2xx) by Robert Oostenveld. If you need cross-platform CLI tools (unicorn2txt, unicorn2lsl, unicorn2audio), see the original repository.

## Why this app?

The official Unicorn software is Windows-only. This project gives macOS users a fast, hackable alternative with real-time visualization, LSL integration, and reliable Bluetooth that just works — the app automatically handles the forget/re-pair cycle that the Unicorn's Bluetooth stack requires on macOS.

## Features

- **8-channel EEG waveform display** — real-time scrolling visualization at 250 Hz
- **Frequency band power bars** — live delta, theta, alpha, beta, gamma power with customizable frequency ranges
- **Signal quality head map** — per-electrode contact quality visualization
- **Customizable band ratios** — alpha/beta, theta/beta, or define your own
- **Automatic Bluetooth management** — no more manual forget/re-pair in System Settings; the app uses [blueutil](https://github.com/toy/blueutil) to handle it automatically
- **Multiple output sinks:**
  - **LSL** — raw EEG stream + optional band power stream
  - **Text file** — tab-separated values for offline analysis
  - **Audio** — resampled EEG output to any audio device (real or virtual)

<!-- TODO: Add screenshot of the band power panel and head map -->

## Requirements

- macOS 15.0 or later
- [Homebrew](https://brew.sh)
- Unicorn Hybrid Black EEG headset (paired via Bluetooth at least once)

## Installation

Install dependencies via Homebrew:

```bash
brew install libserialport portaudio libsamplerate xcodegen
```

Install [liblsl](https://github.com/sccn/liblsl/releases) manually — download the latest release and copy the files:

```bash
# Option A: system-wide
cp liblsl/lib/* /usr/local/lib/
cp liblsl/include/* /usr/local/include/

# Option B: project-local
mkdir -p external/lsl/{lib,include}
cp liblsl/lib/* external/lsl/lib/
cp liblsl/include/* external/lsl/include/
```

## Building

```bash
./setup_xcode.sh       # generates the Xcode project via XcodeGen
open UnicornEEG.xcodeproj
```

Then build with **Cmd+B** in Xcode and run.

> **Note:** The App Sandbox must be disabled for Bluetooth and serial port access.

## Usage

1. Power on the Unicorn headset (LED gives short flashes while waiting)
2. Make sure the device has been paired with your Mac at least once via System Settings > Bluetooth
3. Click **Start** — the app automatically resets the Bluetooth connection and begins streaming
4. Configure outputs (LSL, file, audio) in the bottom panel
5. Toggle the **Bands** checkbox to show/hide the frequency band power panel

<!-- TODO: Add screenshot of the output configuration panel -->

## Troubleshooting

- **Bluetooth won't connect:** Make sure the headset is powered on and has been paired at least once. If all else fails, run `sudo pkill bluetoothd` in a terminal to restart the macOS Bluetooth daemon.
- **blueutil not found:** The app bundles blueutil, but if issues arise you can also install it with `brew install blueutil` as a fallback.
- **No serial port appears:** Grant the app Bluetooth permission when prompted. Check System Settings > Privacy & Security > Bluetooth.

## Dependencies

| Library | Purpose | Install |
|---------|---------|---------|
| [libserialport](https://sigrok.org/wiki/Libserialport) | Serial port communication | `brew install libserialport` |
| [liblsl](https://labstreaminglayer.readthedocs.io) | LabStreamingLayer streaming | [Manual install](https://github.com/sccn/liblsl/releases) |
| [PortAudio](http://www.portaudio.com) | Audio output | `brew install portaudio` |
| [libsamplerate](http://libsndfile.github.io/libsamplerate) | Audio resampling | `brew install libsamplerate` |
| [blueutil](https://github.com/toy/blueutil) | Bluetooth CLI control | Bundled in .app |

## Acknowledgments

- [unicorn2xx](https://github.com/robertoostenveld/unicorn2xx) by Robert Oostenveld — CLI tools for streaming Unicorn EEG data
- [blueutil](https://github.com/toy/blueutil) by Frederik Kolber — Bluetooth CLI utility (GPL v2, bundled in this app)
