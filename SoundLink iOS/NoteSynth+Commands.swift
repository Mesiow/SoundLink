//
//  NoteSynth+Commands.swift
//  SoundLink iOS
//
//  Turns a decoded BLE command into sound. Plugged into
//  PeripheralManager.onCommand, so the Bluetooth code never touches audio.
//

import Foundation

extension NoteSynth {
    func handle(_ packet: CommandPacket) -> AckStatus {
        switch packet.command {
        case .ping:
            return .ok

        case .noteOn:
            guard let event = NoteEvent.decode(packet.payload) else { return .malformedPacket }
            noteOn(event.note, velocity: event.velocity)
            return .ok

        case .noteOff:
            guard let event = NoteEvent.decode(packet.payload) else { return .malformedPacket }
            noteOff(event.note)
            return .ok

        case .allNotesOff:
            allNotesOff()
            return .ok
        }
    }
}
