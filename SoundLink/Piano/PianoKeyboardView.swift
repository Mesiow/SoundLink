//
//  PianoKeyboardView.swift
//  SoundLink (macOS)
//
//  An 18-key piano (C to F of the next octave), played with the mouse
//  or the computer keyboard:
//
//     W E   T Y U   O P          ← black keys
//    A S D F G H J K L ; '       ← white keys
//
//    Z / X = octave down / up
//
//  This view only reports presses and releases. It knows nothing about Bluetooth.
//

import SwiftUI

struct PianoKeyboardView: View {
    /// Octave of the leftmost C (4 → starts at middle C, MIDI 60).
    @Binding var octave: Int
    let onNoteOn: (_ note: UInt8, _ velocity: UInt8) -> Void
    let onNoteOff: (_ note: UInt8) -> Void

    static let octaveRange = 1...7
    private static let keyCount = 18
    private static let shortcuts: [Character] = ["a", "w", "s", "e", "d", "f", "t", "g", "y", "h", "u", "j", "k", "o", "l", "p", ";", "'"]
    private static let keyboardVelocity: UInt8 = 100

    /// Notes currently held down (by mouse or keyboard), for highlighting.
    @State private var pressedNotes: Set<UInt8> = []
    /// Which note each computer key started, so release matches press even if the octave changed.
    @State private var heldByKey: [Character: UInt8] = [:]
    @FocusState private var isFocused: Bool

    private var lowestNote: UInt8 { UInt8(12 * (octave + 1)) }
    private var notes: [UInt8] { (0..<Self.keyCount).map { lowestNote + UInt8($0) } }

    var body: some View {
        GeometryReader { geo in
            let whiteNotes = notes.filter { !NoteName.isBlack($0) }
            let whiteWidth = geo.size.width / CGFloat(whiteNotes.count)
            let blackWidth = whiteWidth * 0.6
            let blackHeight = geo.size.height * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteNotes, id: \.self) { note in
                        key(note, width: whiteWidth, height: geo.size.height)
                    }
                }

                ForEach(notes.filter(NoteName.isBlack), id: \.self) { note in
                    // A black key sits on the line between two white keys.
                    let whitesBefore = notes.filter { $0 < note && !NoteName.isBlack($0) }.count
                    key(note, width: blackWidth, height: blackHeight)
                        .offset(x: CGFloat(whitesBefore) * whiteWidth - blackWidth / 2)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onTapGesture { isFocused = true }
        .onKeyPress(phases: [.down, .up], action: handleKeyPress)
    }

    // MARK: - Key view

    private func key(_ note: UInt8, width: CGFloat, height: CGFloat) -> some View {
        let isBlack = NoteName.isBlack(note)
        let isPressed = pressedNotes.contains(note)
        let index = Int(note - lowestNote)

        return RoundedRectangle(cornerRadius: 4)
            .fill(isPressed ? Color.accentColor : (isBlack ? Color.black : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.6), lineWidth: 1))
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    Text(String(Self.shortcuts[index]).uppercased())
                        .font(.caption.weight(.semibold))
                    if note % 12 == 0 {
                        Text(NoteName.of(note)).font(.caption2)
                    }
                }
                .foregroundStyle(isBlack || isPressed ? Color.white : Color.gray)
                .padding(.bottom, 6)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !pressedNotes.contains(note) else { return }
                        // Like a real piano: pressing lower on the key plays louder.
                        let depth = min(max(drag.startLocation.y / height, 0), 1)
                        press(note, velocity: UInt8(40 + depth * 87))
                    }
                    .onEnded { _ in release(note) }
            )
    }

    // MARK: - Input

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let char = keyPress.characters.lowercased().first else { return .ignored }

        if keyPress.phase == .down, char == "z" || char == "x" {
            shiftOctave(by: char == "z" ? -1 : 1)
            return .handled
        }

        guard let index = Self.shortcuts.firstIndex(of: char) else { return .ignored }

        switch keyPress.phase {
        case .down:
            guard heldByKey[char] == nil else { return .handled }
            let note = lowestNote + UInt8(index)
            heldByKey[char] = note
            press(note, velocity: Self.keyboardVelocity)
        case .up:
            if let note = heldByKey.removeValue(forKey: char) {
                release(note)
            }
        default:
            break
        }
        return .handled
    }

    private func press(_ note: UInt8, velocity: UInt8) {
        guard pressedNotes.insert(note).inserted else { return }
        onNoteOn(note, velocity)
    }

    private func release(_ note: UInt8) {
        guard pressedNotes.remove(note) != nil else { return }
        onNoteOff(note)
    }

    private func shiftOctave(by delta: Int) {
        let newOctave = octave + delta
        guard Self.octaveRange.contains(newOctave) else { return }
        // Release held notes first so nothing gets stuck on the iPhone.
        pressedNotes.forEach(release)
        heldByKey.removeAll()
        octave = newOctave
    }
}

#Preview {
    PianoKeyboardView(octave: .constant(4), onNoteOn: { _, _ in }, onNoteOff: { _ in })
        .frame(width: 600, height: 200)
        .padding()
}
