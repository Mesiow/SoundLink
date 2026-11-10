//
//  NoteSynth.swift
//  Shared
//
//  Plays piano notes locally. Used by both apps:
//  - iPhone: plays notes received over BLE. iOS sends the audio to your
//    Bluetooth earphones automatically when they're connected.
//  - Mac: plays the piano through the Mac's own speakers when no iPhone is connected.
//
//  Audio graph:  AVAudioUnitSampler → engine.mainMixerNode → output
//

import AVFoundation
import Observation

@Observable
final class NoteSynth {
    /// Notes currently sounding, so the UI can show them.
    private(set) var activeNotes: Set<UInt8> = []

    /// Name of an optional SoundFont in the app bundle (e.g. drop "Piano.sf2" into Shared/).
    /// Without it, the sampler plays a plain built-in tone.
    static let soundFontName = "Piano"
    /// Which instrument in the SoundFont to use. Piano.sf2 (BandLab Keyboards) has:
    /// 0 accordion, 1 bright piano, 2 dark grand, 3 electric piano, 4 felt piano,
    /// 5 FM keys, 6 FM tines, 7 grand piano, 8 harpsichord, 9 honky tonk piano,
    /// 10 hyperbrite piano, 11 lofi piano, 12 mellow EP, 13 studio grand,
    /// 14 upright piano, 15 whirly
    static let soundFontProgram: UInt8 = 7

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let sampler = AVAudioUnitSampler()
    @ObservationIgnored private var isSetUp = false

    private static let channel: UInt8 = 0

    /// Attach + connect the sampler and start the engine. Safe to call more than once.
    func start() {
        if !isSetUp {
            #if os(iOS)
            configureAudioSession()
            #endif

            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            isSetUp = true

            loadSoundFont(named: Self.soundFontName)
        }
        ensureRunning()
    }

    /// Loads a piano SoundFont (.sf2) from the app bundle for a realistic sound.
    func loadSoundFont(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sf2") else {
            print("NoteSynth: no \(name).sf2 in bundle, using the default tone")
            return
        }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: Self.soundFontProgram,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            print("NoteSynth: loaded \(name).sf2")
        } catch {
            print("NoteSynth: failed to load \(name).sf2: \(error)")
        }
    }

    func noteOn(_ note: UInt8, velocity: UInt8) {
        guard note <= 127 else { return }
        // MIDI convention: a noteOn with velocity 0 means noteOff.
        guard velocity > 0 else { return noteOff(note) }

        ensureRunning()
        // Re-striking a held note: stop it first so it restarts cleanly.
        if activeNotes.contains(note) {
            sampler.stopNote(note, onChannel: Self.channel)
        }
        sampler.startNote(note, withVelocity: min(velocity, 127), onChannel: Self.channel)
        activeNotes.insert(note)
    }

    func noteOff(_ note: UInt8) {
        guard note <= 127 else { return }
        sampler.stopNote(note, onChannel: Self.channel)
        activeNotes.remove(note)
    }

    /// Stop every sounding note. Also call this when the Mac disconnects,
    /// so a key held at that moment doesn't ring forever.
    func allNotesOff() {
        for note in activeNotes {
            sampler.stopNote(note, onChannel: Self.channel)
        }
        // MIDI "All Notes Off" controller, in case anything was missed.
        sampler.sendController(123, withValue: 0, onChannel: Self.channel)
        activeNotes.removeAll()
    }

    // MARK: - Private

    /// The engine stops itself when the audio route changes (e.g. earphones
    /// connect/disconnect) or after an interruption, so restart it on demand.
    private func ensureRunning() {
        guard isSetUp, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("NoteSynth: audio engine failed to start: \(error)")
        }
    }

    #if os(iOS)
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback: plays with the silent switch on and routes to Bluetooth earphones.
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("NoteSynth: audio session error: \(error)")
        }
    }
    #endif
}
