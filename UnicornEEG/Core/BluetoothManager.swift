/*
 * BluetoothManager.swift
 * UnicornEEG
 *
 * Manages the Bluetooth connection to the Unicorn device.
 * Uses blueutil CLI for reliable unpair/pair/connect/disconnect operations,
 * and IOBluetooth for device discovery.
 */

import Foundation
import IOBluetooth

enum BluetoothManager {

    /// Find the Unicorn device among paired Bluetooth devices.
    static func findUnicorn() -> IOBluetoothDevice? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        return devices.first { device in
            guard let name = device.name else { return false }
            return name.contains("UN")
        }
    }

    /// Get the Bluetooth address of the Unicorn (e.g. "84-2e-14-09-ed-04").
    static func unicornAddress() -> String? {
        return findUnicorn()?.addressString
    }

    /// Disconnect at the Bluetooth baseband level.
    static func disconnectUnicorn() {
        guard let addr = unicornAddress() else { return }
        run(["--disconnect", addr])
        // Wait for disconnect
        let deadline = Date().addingTimeInterval(3.0)
        while isConnected(addr) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Connect at the Bluetooth baseband level.
    static func connectUnicorn() -> Bool {
        guard let addr = unicornAddress() else { return false }
        run(["--connect", addr])
        let deadline = Date().addingTimeInterval(5.0)
        while !isConnected(addr) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isConnected(addr)
    }

    /// Full unpair + re-pair cycle. This is equivalent to what the user does
    /// manually in Bluetooth settings: forget device, then pair again.
    static func unpairAndRepair() -> Bool {
        // Get address before unpairing (won't be findable after)
        guard let addr = unicornAddress() else {
            print("[BT] unpairAndRepair: no Unicorn address found")
            return false
        }

        // Disconnect if connected
        print("[BT] Disconnecting \(addr)...")
        let disconnectStatus = run(["--disconnect", addr])
        print("[BT] Disconnect exit status: \(disconnectStatus)")
        Thread.sleep(forTimeInterval: 1.0)

        // Unpair
        print("[BT] Unpairing \(addr)...")
        let unpairStatus = run(["--unpair", addr])
        print("[BT] Unpair exit status: \(unpairStatus)")
        Thread.sleep(forTimeInterval: 2.0)

        // Re-pair
        print("[BT] Pairing \(addr)...")
        let pairStatus = run(["--pair", addr])
        print("[BT] Pair exit status: \(pairStatus)")
        Thread.sleep(forTimeInterval: 3.0)

        // Connect
        print("[BT] Connecting \(addr)...")
        run(["--connect", addr])

        // Wait for connection
        let deadline = Date().addingTimeInterval(8.0)
        while !isConnected(addr) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
        }

        let connected = isConnected(addr)
        print("[BT] Connected: \(connected)")

        guard connected else { return false }

        // Wait for serial port to appear
        Thread.sleep(forTimeInterval: 1.0)
        let portFound = waitForSerialPort(timeout: 5.0)
        print("[BT] Serial port found: \(portFound)")
        return portFound
    }

    /// Escalating reset: try disconnect+reconnect first, then unpair+repair.
    static func resetConnection() -> Bool {
        guard let addr = unicornAddress() else { return false }

        // Attempt 1: simple disconnect + reconnect
        run(["--disconnect", addr])
        Thread.sleep(forTimeInterval: 1.0)
        run(["--connect", addr])

        let deadline = Date().addingTimeInterval(5.0)
        while !isConnected(addr) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }

        if isConnected(addr) && waitForSerialPort(timeout: 3.0) {
            return true
        }

        // Attempt 2: full unpair + re-pair
        return unpairAndRepair()
    }

    /// Check if a device is connected.
    private static func isConnected(_ address: String) -> Bool {
        let output = runCapture(["--is-connected", address])
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Wait for a Unicorn serial port to appear in /dev/.
    private static func waitForSerialPort(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if findUnicornPortName() != nil {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// Find a Unicorn serial port name.
    static func findUnicornPortName() -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else { return nil }
        return entries.first(where: { $0.hasPrefix("cu.UN") }).map { "/dev/\($0)" }
    }

    // MARK: - blueutil subprocess

    private static var bleutilPath: String = {
        // Prefer bundled copy, fall back to Homebrew install
        if let bundled = Bundle.main.path(forResource: "blueutil", ofType: nil) {
            return bundled
        }
        return "/usr/local/bin/blueutil"
    }()

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bleutilPath)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[BT] blueutil \(args.joined(separator: " ")) stdout: \(stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[BT] blueutil \(args.joined(separator: " ")) stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return process.terminationStatus
        } catch {
            print("[BT] blueutil \(args.joined(separator: " ")) failed to launch: \(error)")
            return -1
        }
    }

    private static func runCapture(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bleutilPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
