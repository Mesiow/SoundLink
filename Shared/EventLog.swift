//
//  EventLog.swift
//  Shared
//
//  A simple in-memory event logger both apps can show in their UI
//  (state changes, connects/disconnects, commands, acks, errors).
//

import Foundation
import Observation

struct LogEntry: Identifiable {
    enum Kind {
        case info
        case sent
        case received
        case error
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let message: String
}

@Observable
final class EventLog {
    private(set) var entries: [LogEntry] = []

    func log(_ message: String, kind: LogEntry.Kind = .info) {
        entries.append(LogEntry(kind: kind, message: message))
        print("[\(kind)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }
}
