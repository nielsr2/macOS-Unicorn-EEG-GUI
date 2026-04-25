/*
 * RingBuffer.swift
 * UnicornEEG
 *
 * Thread-safe single-producer single-consumer ring buffer for passing
 * samples from the acquisition thread to the UI visualization thread.
 */

import Foundation

class RingBuffer {
    private let capacity: Int
    private let channelCount: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    init(capacity: Int, channelCount: Int = UnicornSample.totalChannelCount) {
        self.capacity = capacity
        self.channelCount = channelCount
        self.buffer = [Float](repeating: 0, count: capacity * channelCount)
    }

    func write(_ sample: UnicornSample) {
        lock.lock()
        let offset = writeIndex * channelCount
        let all = sample.allChannels
        for i in 0..<min(channelCount, all.count) {
            buffer[offset + i] = all[i]
        }
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity {
            count += 1
        }
        lock.unlock()
    }

    /// Read the latest `maxCount` samples for all channels.
    /// Returns an array of shape [samples][channels], ordered oldest to newest.
    func readLatest(maxCount: Int) -> [[Float]] {
        lock.lock()
        let n = min(maxCount, count)
        var result = [[Float]]()
        result.reserveCapacity(n)

        let startIndex = (writeIndex - n + capacity) % capacity
        for i in 0..<n {
            let idx = (startIndex + i) % capacity
            let offset = idx * channelCount
            let sample = Array(buffer[offset..<(offset + channelCount)])
            result.append(sample)
        }
        lock.unlock()
        return result
    }

    /// Write a raw float array (for non-UnicornSample data like band powers).
    func writeRaw(_ values: [Float]) {
        lock.lock()
        let offset = writeIndex * channelCount
        for i in 0..<min(channelCount, values.count) {
            buffer[offset + i] = values[i]
        }
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity {
            count += 1
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        writeIndex = 0
        count = 0
        lock.unlock()
    }
}
