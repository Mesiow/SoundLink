//
//  ContentView.swift
//  SoundLink iOS
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @Environment(PeripheralManager.self) private var peripheral
    @Environment(NoteSynth.self) private var synth

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusSection
                advertisingButton
                EventLogView(log: peripheral.log)
            }
            .padding()
            .navigationTitle("SoundLink Receiver")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusSection: some View {
        VStack(spacing: 10) {
            StatusRow(
                title: "Bluetooth",
                value: peripheral.bluetoothState.displayName,
                color: peripheral.bluetoothState.color
            )
            StatusRow(
                title: "Advertising",
                value: peripheral.isAdvertising ? "On" : "Off",
                color: peripheral.isAdvertising ? .green : .gray
            )
            StatusRow(
                title: "Mac",
                value: peripheral.isCentralSubscribed ? "Subscribed" : "Not connected",
                color: peripheral.isCentralSubscribed ? .green : .gray
            )
            StatusRow(
                title: "Playing",
                value: playingText,
                color: synth.activeNotes.isEmpty ? .gray : .blue
            )
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private var playingText: String {
        guard !synth.activeNotes.isEmpty else { return "–" }
        return synth.activeNotes.sorted().map(NoteName.of).joined(separator: " ")
    }

    private var advertisingButton: some View {
        Button {
            if peripheral.isAdvertising {
                peripheral.stopAdvertising()
            } else {
                peripheral.startAdvertising()
            }
        } label: {
            Label(
                peripheral.isAdvertising ? "Stop Advertising" : "Start Advertising",
                systemImage: peripheral.isAdvertising ? "stop.circle" : "dot.radiowaves.left.and.right"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(peripheral.bluetoothState != .poweredOn)
    }
}

#Preview {
    ContentView()
        .environment(PeripheralManager())
        .environment(NoteSynth())
}
