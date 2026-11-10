//
//  SoundLinkUUIDs.swift
//  Shared (compiled into both the macOS and iOS targets)
//
//  The custom GATT layout both apps agree on.
//
//  Service: SoundLink
//   ├─ Command characteristic  (Mac → iPhone)  write
//   └─ Ack characteristic      (iPhone → Mac)  notify
//

import CoreBluetooth

enum SoundLinkUUIDs {
    static let service = CBUUID(string: "45840C98-D8A9-4C05-B635-9874635DBE09")
    static let commandCharacteristic = CBUUID(string: "5444592C-B87D-4304-AED8-63172777BB5E")
    static let ackCharacteristic = CBUUID(string: "75A5FFDC-B393-4ECC-A665-117D6541F83E")

    /// Local name the iPhone advertises, so the Mac can label it in the scan list.
    static let advertisedName = "SoundLink"
}
