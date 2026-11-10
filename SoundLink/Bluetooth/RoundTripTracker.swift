//
//  RoundTripTracker.swift
//  SoundLink (macOS)
//
//  Measures time from writing a command to receiving its ack.
//  (This is BLE command round-trip time, not audio latency.)
//

import Foundation

struct RoundTripTracker {
    // Send time for each command still waiting for an ack, keyed by sequence number.
    private var pending: [UInt16: ContinuousClock.Instant] = [:]

    mutating func markSent(sequence: UInt16) {
        pending[sequence] = .now
    }

    // Returns the round-trip time in milliseconds, or nil if the sequence wasn't pending.
    mutating func markAcked(sequence: UInt16) -> Double? {
        // removeValue returns the old value and deletes it in one step
        guard let sentAt = pending.removeValue(forKey: sequence) else { return nil }
        
        let elapsed = ContinuousClock.now - sentAt
        let c = elapsed.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }

    // Drop everything, e.g. after a disconnect.
    mutating func reset() {
        pending.removeAll()
    }
}
