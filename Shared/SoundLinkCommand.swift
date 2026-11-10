//
//  SoundLinkCommand.swift
//  Shared
//
//  The wire format for commands (Mac → iPhone) and acknowledgments (iPhone → Mac).
//  Keep packets small: they need to fit in a single BLE write / notification.
//

import Foundation

/// Every command the Mac can send.
enum SoundLinkCommand: UInt8 {
    /// Round-trip test. Payload: none.
    case ping = 0x01
    /// Start a note. Payload: NoteEvent [note][velocity].
    case noteOn = 0x02
    /// Stop a note. Payload: NoteEvent [note][velocity] (velocity ignored).
    case noteOff = 0x03
    /// Panic button: stop every sounding note. Payload: none.
    case allNotesOff = 0x04
}

/// Result code the iPhone sends back in an ack.
enum AckStatus: UInt8 {
    case ok = 0x00
    case unknownCommand = 0x01
    case malformedPacket = 0x02
    case playbackFailed = 0x03
}

/// Mac → iPhone.
/// Suggested layout: [sequence: UInt16][command: UInt8][payload: bytes...]
struct CommandPacket {
    /// Incrementing number so an ack can be matched to the command that caused it (for round-trip time).
    let sequence: UInt16
    let command: SoundLinkCommand
    /// Optional extra data, e.g. an encoded NoteEvent.
    let payload: Data

    func encode() -> Data {
        // Pack sequence, command and payload into bytes.
        //data encoded in little endian
        var data = Data(capacity: 3 + payload.count)
        data.append(UInt8(sequence & 0xFF)) //low byte
        data.append(UInt8(sequence >> 8)) //high byte
        data.append(command.rawValue) //byte 1
        data.append(payload)
        
        return data
    }

    static func decode(_ data: Data) -> CommandPacket? {
        // Validate length, read the fields back out.
        let bytes = [UInt8](data) //copy into plain array
        guard bytes.count >= 3 else { return nil }
        
        let sequence = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        guard let command = SoundLinkCommand(rawValue: bytes[2]) else { return nil }
        let payload = Data(bytes[3...]) //empty if count == 3
        
        return CommandPacket(sequence: sequence, command: command, payload: payload)
    }
}

/// iPhone → Mac.
/// Suggested layout: [sequence: UInt16][status: UInt8]
struct AckPacket {
    let sequence: UInt16
    let status: AckStatus

    func encode() -> Data {
        //
        let data: [UInt8] = [UInt8(sequence & 0xFF), UInt8(sequence >> 8), status.rawValue]
        return Data(data)
    }

    static func decode(_ data: Data) -> AckPacket? {
        let bytes = [UInt8](data)
        guard bytes.count == 3, let status = AckStatus(rawValue: bytes[2]) else {
            return nil
        }
        let sequence = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        return AckPacket(sequence: sequence, status: status)
    }
}
