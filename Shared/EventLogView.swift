//
//  EventLogView.swift
//  Shared
//
//  Scrolling list of EventLog entries, used by both apps.
//

import SwiftUI
import CoreBluetooth

struct EventLogView: View {
    let log: EventLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event Log")
                    .font(.headline)
                Spacer()
                Button("Clear") { log.clear() }
                    .disabled(log.entries.isEmpty)
            }

            ScrollViewReader { proxy in
                List(log.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(entry.kind.color)
                        Text(entry.message)
                            .textSelection(.enabled)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .id(entry.id)
                }
                .overlay {
                    if log.entries.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: log.entries.count) {
                    if let last = log.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private extension LogEntry.Kind {
    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .sent: "arrow.up.circle"
        case .received: "arrow.down.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .info: .secondary
        case .sent: .blue
        case .received: .green
        case .error: .red
        }
    }
}

// MARK: - Display helpers

extension CBManagerState {
    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .resetting: "Resetting"
        case .unsupported: "Unsupported"
        case .unauthorized: "Unauthorized"
        case .poweredOff: "Powered Off"
        case .poweredOn: "Powered On"
        @unknown default: "Unknown"
        }
    }

    var color: Color {
        self == .poweredOn ? .green : .orange
    }
}

/// A small label + colored dot, used for status rows.
struct StatusRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
