//
//  ContentView.swift
//  SoundLink (macOS)
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @Environment(CentralManager.self) private var central
    @Environment(NoteSynth.self) private var synth

    @State private var octave = 4
    /// Notes currently held that are playing on the Mac (not the iPhone), so each
    /// noteOff goes to the same place its noteOn went, even if the connection changes mid-press.
    @State private var localNotes: Set<UInt8> = []

    private var isRemote: Bool { central.connectionState == .ready }

    var body: some View {
        HSplitView {
            // Left: connection
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                scanSection
                deviceList
            }
            .padding()
            .frame(minWidth: 280, idealWidth: 300, maxWidth: 360)

            // Right: piano + log
            VStack(alignment: .leading, spacing: 16) {
                pianoSection
                EventLogView(log: central.log)
            }
            .padding()
            .frame(minWidth: 560)
        }
        .frame(minWidth: 880, minHeight: 560)
        .onChange(of: isRemote) {
            // Switching between Mac and iPhone: silence anything still ringing locally.
            synth.allNotesOff()
            localNotes.removeAll()
        }
    }

    // MARK: - Note routing

    private func noteOn(_ note: UInt8, velocity: UInt8) {
        if isRemote {
            central.noteOn(note, velocity: velocity)
        } else {
            localNotes.insert(note)
            synth.noteOn(note, velocity: velocity)
        }
    }

    private func noteOff(_ note: UInt8) {
        if localNotes.remove(note) != nil {
            synth.noteOff(note)
        } else {
            central.noteOff(note)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(spacing: 8) {
            StatusRow(
                title: "Bluetooth",
                value: central.bluetoothState.displayName,
                color: central.bluetoothState.color
            )
            StatusRow(
                title: "Connection",
                value: central.connectionState.displayName,
                color: central.connectionState.color
            )
            StatusRow(
                title: "Round trip",
                value: central.lastRoundTripMs.map { String(format: "%.1f ms", $0) } ?? "–",
                color: central.lastRoundTripMs == nil ? .gray : .blue
            )
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private var scanSection: some View {
        HStack {
            if central.connectionState == .scanning {
                Button("Stop Scan", systemImage: "stop.circle") { central.stopScanning() }
                ProgressView().controlSize(.small)
            } else {
                Button("Scan", systemImage: "magnifyingglass") { central.startScanning() }
                    .disabled(central.bluetoothState != .poweredOn)
            }
            Spacer()
            Button("Disconnect", systemImage: "xmark.circle") { central.disconnect() }
                .disabled(!central.connectionState.isConnected)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices").font(.headline)
            List(central.discoveredDevices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                        Text("RSSI \(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Connect") { central.connect(to: device.id) }
                        .disabled(central.connectionState.isConnected)
                }
            }
            .overlay {
                if central.discoveredDevices.isEmpty {
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pianoSection: some View {
        let ready = central.connectionState == .ready

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Piano").font(.headline)
                Spacer()

                Button("Octave down", systemImage: "minus") { octave -= 1 }
                    .labelStyle(.iconOnly)
                    .disabled(octave <= PianoKeyboardView.octaveRange.lowerBound)
                Text("C\(octave)")
                    .monospacedDigit()
                    .frame(width: 28)
                Button("Octave up", systemImage: "plus") { octave += 1 }
                    .labelStyle(.iconOnly)
                    .disabled(octave >= PianoKeyboardView.octaveRange.upperBound)

                Divider().frame(height: 16)

                Button("Ping", systemImage: "wave.3.right") { central.send(.ping) }
                    .disabled(!ready)
                Button("Panic", systemImage: "speaker.slash") {
                    synth.allNotesOff()
                    localNotes.removeAll()
                    if ready { central.allNotesOff() }
                }
                .help("Stop all notes")
            }

            PianoKeyboardView(
                octave: $octave,
                onNoteOn: noteOn,
                onNoteOff: noteOff
            )
            .frame(height: 180)

            Label(
                ready ? "Playing on iPhone" : "Playing on this Mac (no iPhone connected)",
                systemImage: ready ? "iphone.radiowaves.left.and.right" : "desktopcomputer"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(ready ? Color.green : Color.secondary)

            Text("Click keys or type A–' to play. Z / X shifts octave.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Display helpers

private extension ConnectionState {
    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .discovering: "Discovering"
        case .ready: "Ready"
        case .disconnected: "Disconnected"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .connecting, .discovering, .scanning: .yellow
        case .idle, .disconnected: .gray
        }
    }

    var isConnected: Bool {
        self == .discovering || self == .ready
    }
}

#Preview {
    ContentView()
        .environment(CentralManager())
        .environment(NoteSynth())
}
