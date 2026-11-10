//
//  SoundLinkApp.swift
//  SoundLink (macOS)
//
//  Mac app: BLE central that finds the iPhone and sends piano notes.
//  With no iPhone connected, the piano plays through the Mac instead.
//

import SwiftUI

@main
struct SoundLinkApp: App {
    @State private var central = CentralManager()
    @State private var synth = NoteSynth()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(central)
                .environment(synth)
                .task { synth.start() }
        }
    }
}
