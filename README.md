# SoundLink

Play piano on your Mac and hear it on your iPhone, sent over Bluetooth Low Energy (BLE).

The Mac app shows a playable keyboard. Each key press is sent to the iPhone, which plays the note, so you can listen through Bluetooth earphones connected to the phone. With no iPhone connected, the Mac plays notes through its own speakers.

## How it works

```
 Mac (BLE central)                          iPhone (BLE peripheral)
┌──────────────────┐   command (write)    ┌──────────────────────┐
│ Piano keyboard   │ ───────────────────▶ │ Decode command       │
│ CentralManager   │                      │ PeripheralManager    │
│                  │ ◀─────────────────── │ NoteSynth plays note │
└──────────────────┘    ack (notify)      └──────────────────────┘
```

1. The iPhone advertises a custom SoundLink GATT service.
2. The Mac scans for that service, connects, and subscribes to acks.
3. Key presses are sent as small command packets. Notes use write-without-response for low latency.
4. The iPhone plays the note and sends back an ack, and the Mac uses it to measure round-trip time.

### GATT layout

| Item | Direction | Properties |
| --- | --- | --- |
| SoundLink service | | |
| Command characteristic | Mac → iPhone | write, write without response |
| Ack characteristic | iPhone → Mac | notify |

UUIDs are defined in `Shared/SoundLinkUUIDs.swift`.

### Packet format

| Packet | Bytes |
| --- | --- |
| Command | `[seq lo][seq hi][command][payload…]` |
| Note payload | `[note][velocity]` (MIDI, 0–127) |
| Ack | `[seq lo][seq hi][status]` |

Commands: `ping`, `noteOn`, `noteOff`, `allNotesOff`.

## Project structure

```
Shared/           Code used by both apps (UUIDs, packets, NoteSynth, EventLog)
SoundLink/        macOS app: BLE central, piano keyboard UI
SoundLink iOS/    iOS app: BLE peripheral, plays received notes
```

## Requirements

- Xcode 26 or later
- macOS 15.6+ (Mac app)
- iOS 26+ on a physical iPhone (the Simulator doesn't support Bluetooth)
- Bluetooth turned on for both devices

## Getting started

1. Open `SoundLink.xcodeproj` in Xcode.
2. Run the **SoundLink iOS** scheme on your iPhone and allow Bluetooth access.
3. Run the **SoundLink** scheme on your Mac and allow Bluetooth access.
4. On the Mac, press **Scan**, then choose your iPhone from the list.
5. Once the status shows **Ready**, play.

## Playing the keyboard

```
 W E   T Y U   O P        ← black keys
A S D F G H J K L ; '     ← white keys

Z / X = octave down / up
```

You can also click the keys with the mouse.

## Sound

Notes play through `AVAudioUnitSampler` using `Shared/Piano.sf2`. To change the instrument, set `NoteSynth.soundFontProgram` (for example, `7` is grand piano and `14` is upright piano). Without the SoundFont, the sampler falls back to a plain built-in tone.
