# Unicorn EEG macOS 2 LSL

A native macOS application for the [Unicorn Hybrid Black](https://github.com/unicorn-bi/Unicorn-Suite-Hybrid-Black-User-Manual) 8-channel EEG system. Real-time visualization and streaming to [LabStreamingLayer (LSL)](https://labstreaminglayer.readthedocs.io).

![App Screenshot](UNICORN%20MACOS.png)

> Built on [unicorn2xx](https://github.com/robertoostenveld/unicorn2xx) by Robert Oostenveld. For cross-platform CLI tools (unicorn2txt, unicorn2lsl, unicorn2audio), see the original repository.

> **Note:** This software has not been thoroughly tested. If you plan to use it for an experiment or anything where data quality matters, please verify the output against a known-good setup before relying on it.

## Download

Grab the latest release for your Mac:

- **[Intel Mac (x86_64)](https://github.com/nielsr2/macOS-Unicorn-EEG-GUI/releases/latest)** 
- **[Apple Silicon (M1/M2/M3/M4)](https://github.com/nielsr2/macOS-Unicorn-EEG-GUI/releases/latest)**

All dependencies are bundled — no Homebrew or other installs needed.

## Quick start

1. Unzip and move **UnicornEEG.app** to Applications
2. Right-click the app > **Open** (to bypass Gatekeeper on first launch)
3. Grant Bluetooth permission when prompted
4. Pair the Unicorn headset once via **System Settings > Bluetooth**
5. Power on the headset and click **Start** — the app handles the Bluetooth connection automatically

## Features

- **8-channel EEG waveform display** — real-time scrolling visualization at 250 Hz
- **Frequency band power bars** — live delta, theta, alpha, beta, gamma power with customizable frequency ranges
- **Signal quality head map** — per-electrode contact quality visualization
- **Customizable band ratios** — alpha/beta, theta/beta, or define your own
- **Automatic Bluetooth management** — the Unicorn's Bluetooth stack on macOS requires a forget/re-pair cycle before each session, which has been a major pain point. This app handles it automatically using [blueutil](https://github.com/toy/blueutil)
- **LSL output** — raw EEG stream + optional band power stream
- **Text file output** — tab-separated values for offline analysis

## Troubleshooting

- **blueutil not found:** The app bundles blueutil, but if issues arise you can also `brew install blueutil` as a fallback.
- **No serial port appears:** Check System Settings > Privacy & Security > Bluetooth and make sure UnicornEEG has permission.

## Building from source

See [BUILDING.md](BUILDING.md) for instructions on compiling the app yourself.

## Acknowledgments

- [unicorn2xx](https://github.com/robertoostenveld/unicorn2xx) by Robert Oostenveld — CLI tools for streaming Unicorn EEG data
- [blueutil](https://github.com/toy/blueutil) by Frederik Kolber — Bluetooth CLI utility (GPL v2, bundled in this app)
