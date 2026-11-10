//
//  NoteEvent.swift
//  Shared
//
//  The payload of a noteOn / noteOff command. Uses MIDI conventions:
//  note 0–127 (60 = middle C), velocity 0–127 (how hard the key was hit).
//
//  Full noteOn packet: [seq lo][seq hi][cmd][note][velocity] = 5 bytes
//

import Foundation

struct NoteEvent: Equatable {
    let note: UInt8
    let velocity: UInt8

    /// The 2 bytes that go in CommandPacket.payload.
    func encode() -> Data {
        Data([note, velocity])
    }

    static func decode(_ payload: Data) -> NoteEvent? {
        // Require exactly 2 bytes, and both values must be <= 127.
        let bytes = [UInt8](payload)
        guard bytes.count == 2 else { return nil }
        
        let note = bytes[0]
        let velocity = bytes[1]
        guard note <= 127, velocity <= 127 else { return nil }   // MIDI range
        
        return NoteEvent(note: note, velocity: velocity)
    }
}

// MARK: - Display helpers

nonisolated enum NoteName {
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// 60 → "C4", 61 → "C♯4"
    static func of(_ note: UInt8) -> String {
        let octave = Int(note) / 12 - 1
        return "\(names[Int(note) % 12])\(octave)"
    }

    /// True for the black keys (C♯, D♯, F♯, G♯, A♯).
    static func isBlack(_ note: UInt8) -> Bool {
        [1, 3, 6, 8, 10].contains(Int(note) % 12)
    }
}
