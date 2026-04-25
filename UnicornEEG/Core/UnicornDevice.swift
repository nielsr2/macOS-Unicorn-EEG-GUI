/*
 * UnicornDevice.swift
 * UnicornEEG
 *
 * Manages the serial-over-Bluetooth connection to the Unicorn Hybrid Black device.
 * Wraps libserialport for port enumeration, connection, and packet reading.
 */

import Foundation

struct SerialPortInfo {
    let index: Int
    let name: String
    let description: String
    let isUnicorn: Bool
}

enum UnicornDeviceError: LocalizedError {
    case noPortsFound
    case cannotOpenPort(String)
    case cannotConfigure(String)
    case cannotStartAcquisition
    case incorrectResponse(bytesRead: Int32, bytes: [UInt8])
    case readFailed
    case portNotOpen

    var errorDescription: String? {
        switch self {
        case .noPortsFound: return "No serial ports found."
        case .cannotOpenPort(let msg): return "Cannot open port: \(msg)"
        case .cannotConfigure(let msg): return "Cannot configure port: \(msg)"
        case .cannotStartAcquisition: return "Cannot start data stream."
        case .incorrectResponse(let n, let b):
            let hex = b.map { String(format: "0x%02X", $0) }.joined(separator: " ")
            return "Incorrect response from device: read \(n) bytes [\(hex)]"
        case .readFailed: return "Cannot read packet."
        case .portNotOpen: return "Port is not open."
        }
    }
}

class UnicornDevice {
    private var port: OpaquePointer?
    private var portName: String?  // stored for reconnection
    private let readTimeout: UInt32 = 100   // short timeout for interruptible reads
    private let writeTimeout: UInt32 = 5000

    private let startAcq: [UInt8] = [0x61, 0x7C, 0x87]
    private let stopAcq: [UInt8] = [0x63, 0x5C, 0xC5]

    // Thread-safe stop flag — set to true to make readPacket() return nil promptly
    private let stopLock = NSLock()
    private var _shouldStop = false
    var shouldStop: Bool {
        get { stopLock.withLock { _shouldStop } }
        set { stopLock.withLock { _shouldStop = newValue } }
    }

    var isConnected: Bool { port != nil }

    // MARK: - Port Enumeration

    static func listPorts() -> [SerialPortInfo] {
        var portList: UnsafeMutablePointer<OpaquePointer?>?
        let result = sp_list_ports(&portList)
        guard result == SP_OK, let list = portList else { return [] }

        var ports: [SerialPortInfo] = []
        var i = 0
        while let p = list[i] {
            let name = String(cString: sp_get_port_name(p))
            let rawDesc = sp_get_port_description(p)
            let desc = rawDesc != nil ? String(cString: rawDesc!) : ""
            let isUnicorn = name.contains("UN") || desc.contains("UN")
            ports.append(SerialPortInfo(index: i, name: name, description: desc, isUnicorn: isUnicorn))
            i += 1
        }

        sp_free_port_list(list)
        return ports
    }

    // MARK: - Connection

    func connect(portName: String) throws {
        // Close any stale port first
        disconnect()

        // Enumerate ports and use sp_copy_port to preserve Bluetooth transport
        // metadata. This matches the C CLI tools. Using sp_get_port_by_name
        // creates a minimal port struct that lacks Bluetooth RFCOMM info,
        // causing the device to not respond on macOS.
        var portList: UnsafeMutablePointer<OpaquePointer?>?
        guard sp_list_ports(&portList) == SP_OK, let list = portList else {
            throw UnicornDeviceError.cannotOpenPort("Failed to enumerate ports")
        }

        var newPort: OpaquePointer?
        var i = 0
        while let p = list[i] {
            if String(cString: sp_get_port_name(p)) == portName {
                guard sp_copy_port(p, &newPort) == SP_OK else {
                    sp_free_port_list(list)
                    throw UnicornDeviceError.cannotOpenPort(portName)
                }
                break
            }
            i += 1
        }
        sp_free_port_list(list)

        guard let copiedPort = newPort else {
            throw UnicornDeviceError.cannotOpenPort("Port \(portName) not found")
        }

        guard sp_open(copiedPort, SP_MODE_READ_WRITE) == SP_OK else {
            sp_free_port(copiedPort)
            throw UnicornDeviceError.cannotOpenPort(portName)
        }

        // Configure: 115200, 8N1, no flow control
        guard sp_set_baudrate(copiedPort, 115200) == SP_OK,
              sp_set_bits(copiedPort, 8) == SP_OK,
              sp_set_parity(copiedPort, SP_PARITY_NONE) == SP_OK,
              sp_set_stopbits(copiedPort, 1) == SP_OK,
              sp_set_flowcontrol(copiedPort, SP_FLOWCONTROL_NONE) == SP_OK else {
            sp_close(copiedPort)
            sp_free_port(copiedPort)
            throw UnicornDeviceError.cannotConfigure("Failed to set port parameters")
        }

        self.port = copiedPort
        self.portName = portName
        self.shouldStop = false
    }

    func disconnect() {
        if let p = port {
            sp_close(p)
            sp_free_port(p)
            port = nil
        }
    }

    /// Close and reopen the serial port to reset the Bluetooth connection.
    private func reconnect() throws {
        guard let name = portName else { throw UnicornDeviceError.portNotOpen }
        disconnect()
        Thread.sleep(forTimeInterval: 1.0)
        try connect(portName: name)
    }

    // MARK: - Port Flushing

    func flush() {
        guard let p = port else { return }
        sp_flush(p, SP_BUF_BOTH)

        // Drain any remaining bytes
        var drain = [UInt8](repeating: 0, count: 512)
        drain.withUnsafeMutableBufferPointer { buf in
            while sp_nonblocking_read(p, buf.baseAddress, buf.count).rawValue > 0 {}
        }
    }

    // MARK: - Acquisition Control

    /// Try to send start_acq and get the expected 0x00 0x00 0x00 response.
    /// Returns true on success, false on failure.
    private func tryStartAcq() -> Bool {
        guard let p = port else { return false }

        let written = startAcq.withUnsafeBufferPointer { buf in
            sp_blocking_write(p, buf.baseAddress, buf.count, writeTimeout)
        }
        guard written.rawValue == 3 else { return false }

        var response = [UInt8](repeating: 0, count: 3)
        let read = response.withUnsafeMutableBufferPointer { buf in
            sp_blocking_read(p, buf.baseAddress, buf.count, 5000)
        }

        return read.rawValue == 3 && response[0] == 0x00 && response[1] == 0x00 && response[2] == 0x00
    }

    /// Send stop_acq command and flush the port.
    private func sendStop() {
        guard let p = port else { return }
        stopAcq.withUnsafeBufferPointer { buf in
            _ = sp_blocking_write(p, buf.baseAddress, buf.count, writeTimeout)
        }
        Thread.sleep(forTimeInterval: 0.3)
        flush()
    }

    func startAcquisition() throws {
        guard port != nil else { throw UnicornDeviceError.portNotOpen }
        shouldStop = false

        // Attempt 1: stop any stale acquisition, flush, then start
        sendStop()
        Thread.sleep(forTimeInterval: 0.2)
        flush()

        if tryStartAcq() { return }

        // Attempt 2: maybe the device needed the full stop cycle — try again
        sendStop()
        Thread.sleep(forTimeInterval: 0.5)
        flush()

        if tryStartAcq() { return }

        // Attempt 3: the serial connection itself may be corrupted.
        // Close the port, reopen it, and try from scratch.
        try reconnect()
        sendStop()
        Thread.sleep(forTimeInterval: 0.5)
        flush()

        if tryStartAcq() { return }

        // All attempts failed — read the actual response for the error message
        var response = [UInt8](repeating: 0xFF, count: 3)
        let written = startAcq.withUnsafeBufferPointer { buf in
            sp_blocking_write(port!, buf.baseAddress, buf.count, writeTimeout)
        }
        if written.rawValue == 3 {
            let read = response.withUnsafeMutableBufferPointer { buf in
                sp_blocking_read(port!, buf.baseAddress, buf.count, 5000)
            }
            throw UnicornDeviceError.incorrectResponse(bytesRead: read.rawValue, bytes: response)
        } else {
            throw UnicornDeviceError.cannotStartAcquisition
        }
    }

    func stopAcquisition() {
        sendStop()
    }

    // MARK: - Packet Reading

    /// Reads a single 45-byte packet using short blocking reads (100ms each).
    /// Checks `shouldStop` between reads so the thread can exit promptly.
    func readPacket() -> UnicornSample? {
        guard let p = port else { return nil }

        var buf = [UInt8](repeating: 0, count: PacketParser.packetSize)
        var bytesRead: Int32 = 0
        let target = Int32(PacketParser.packetSize)

        while bytesRead < target {
            if shouldStop { return nil }

            let remaining = Int(target - bytesRead)
            let result = buf.withUnsafeMutableBufferPointer { bufPtr in
                sp_blocking_read(p, bufPtr.baseAddress! + Int(bytesRead), remaining, readTimeout)
            }

            let n = result.rawValue
            if n < 0 { return nil } // error
            bytesRead += n
        }

        return buf.withUnsafeBufferPointer { bufPtr in
            PacketParser.parse(bufPtr.baseAddress!)
        }
    }

    deinit {
        disconnect()
    }
}
