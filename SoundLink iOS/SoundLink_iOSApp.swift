//
//  SoundLink_iOSApp.swift
//  SoundLink iOS
//
//  iPhone app: BLE peripheral that receives piano notes and plays them.
//

import SwiftUI

@main
struct SoundLink_iOSApp: App {
    @State private var peripheral = PeripheralManager()
    @State private var synth = NoteSynth()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(peripheral)
                .environment(synth)
                .task {
                    synth.start()
                    peripheral.onCommand = synth.handle
                }
                .onChange(of: peripheral.isCentralSubscribed) { _, subscribed in
                    // Mac went away mid-note: don't leave anything ringing.
                    if !subscribed { synth.allNotesOff() }
                }
        }
    }
}
