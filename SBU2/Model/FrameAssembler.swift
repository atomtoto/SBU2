//
//  FrameAssembler.swift
//  SBU2
//

import Foundation

/// Reassembles JBD frames from BLE notifications.
///
/// The dongle splits its answers into 20-byte chunks and occasionally packs two
/// short frames into one notification, so neither "one notification = one frame"
/// nor "a frame ends when the chunk ends" holds. This buffers bytes instead and
/// cuts frames at the length announced in the header.
struct FrameAssembler {

    private var buffer: [UInt8] = []

    /// Discards anything buffered so far. Call it on (re)connect so a truncated
    /// answer from a previous session cannot corrupt the next one.
    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Appends a notification and returns every complete frame it completed.
    mutating func append(_ data: Data) -> [[UInt8]] {
        buffer.append(contentsOf: data)

        var frames: [[UInt8]] = []
        while true {
            // Resync: drop everything before the next start byte.
            if let start = buffer.firstIndex(of: JBD.startByte) {
                if start > 0 { buffer.removeFirst(start) }
            } else {
                buffer.removeAll(keepingCapacity: true)
                break
            }

            guard buffer.count >= 4 else { break }
            let expected = JBD.overhead + Int(buffer[3])
            guard buffer.count >= expected else { break }

            let frame = Array(buffer[0..<expected])
            if frame.last == JBD.stopByte {
                frames.append(frame)
                buffer.removeFirst(expected)
            } else {
                // Length byte was noise — skip this start byte and look for the next one.
                buffer.removeFirst()
            }
        }
        return frames
    }
}
