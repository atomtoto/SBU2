//
//  FrameAssembler.swift
//  SBU2
//

import Foundation

/// Reassembles delimited, length-prefixed frames from BLE notifications.
///
/// The dongle splits its answers into 20-byte chunks and occasionally packs two
/// short frames into one notification, so neither "one notification = one frame"
/// nor "a frame ends when the chunk ends" holds. This buffers bytes instead and
/// cuts frames at the length announced in the header.
///
/// The layout is passed in rather than hardcoded so a second BMS family can reuse
/// the buffering without inheriting JBD's framing bytes.
struct FrameAssembler {

    /// How a family delimits its frames.
    struct Layout: Equatable {
        var startByte: UInt8
        var stopByte: UInt8
        /// Everything in a frame that is not payload.
        var overhead: Int
        /// Offset of the byte announcing the payload length.
        var lengthIndex: Int
    }

    /// How long a half-received frame may sit at the head of the buffer.
    ///
    /// Without this a single truncated answer — one chunk lost on a weak link — leaves
    /// a header waiting for bytes that will never arrive, and every later answer queues
    /// up behind it. The stream then stays out of step until the pack is disconnected,
    /// which is exactly what a reading that only works from very close looks like.
    static let staleAfter: TimeInterval = 1.5

    private let layout: Layout
    private var buffer: [UInt8] = []
    /// When the buffer last went from complete to holding a partial frame.
    private var partialSince: Date?

    init(layout: Layout = JBD.frameLayout) {
        self.layout = layout
    }

    /// Discards anything buffered so far. Call it on (re)connect so a truncated
    /// answer from a previous session cannot corrupt the next one.
    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        partialSince = nil
    }

    /// Appends a notification and returns every complete frame it completed.
    mutating func append(_ data: Data, at now: Date = .now) -> [[UInt8]] {
        if let partialSince, now.timeIntervalSince(partialSince) > Self.staleAfter {
            reset()
        }
        buffer.append(contentsOf: data)

        var frames: [[UInt8]] = []
        while true {
            // Resync: drop everything before the next start byte.
            if let start = buffer.firstIndex(of: layout.startByte) {
                if start > 0 { buffer.removeFirst(start) }
            } else {
                buffer.removeAll(keepingCapacity: true)
                break
            }

            guard buffer.count > layout.lengthIndex else { break }
            let expected = layout.overhead + Int(buffer[layout.lengthIndex])
            guard buffer.count >= expected else { break }

            let frame = Array(buffer[0..<expected])
            if frame.last == layout.stopByte {
                frames.append(frame)
                buffer.removeFirst(expected)
            } else {
                // Length byte was noise — skip this start byte and look for the next one.
                buffer.removeFirst()
            }
        }

        partialSince = buffer.isEmpty ? nil : (partialSince ?? now)
        return frames
    }
}
