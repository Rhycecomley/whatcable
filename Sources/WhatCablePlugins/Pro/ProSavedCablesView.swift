import SwiftUI
import WhatCableAppKit
import WhatCableCore

/// Saved Cables screen (route `pro.saved-cables`): the persistent per-cable
/// history the store samples at the hub's cadence.
struct ProSavedCablesView: View {
    @ObservedObject private var store = ProCableHistoryStore.shared
    @Environment(\.fontScale) private var fontScale
    @State private var renaming: ProCableHistoryStore.Entry?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Cables").scaledFont(.title2, weight: .bold)
                Text(store.isSampling
                     ? "Every cable you plug in is tracked here."
                     : "Start sampling to begin tracking cables.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)

                if store.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "cable.connector")
                            .scaledFont(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No cables tracked yet.")
                            .scaledFont(.headline, weight: .bold)
                        Text("Plug in an e-marked cable and it will appear here — most cables under 60W don't carry an e-marker.")
                            .scaledFont(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(store.entries.sorted { $0.lastSeen > $1.lastSeen }) { entry in
                        cableRow(entry)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 520 * fontScale, alignment: .topLeading)
        .sheet(item: $renaming) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename cable").scaledFont(.headline, weight: .bold)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.rename(entry, to: renameText)
                        renaming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 340)
        }
    }

    private func cableRow(_ entry: ProCableHistoryStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.secondary)
                Text(entry.name).scaledFont(.callout, weight: .bold)
                Spacer()
                Button {
                    renameText = entry.name
                    renaming = entry
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Rename")
                Button {
                    store.delete(entry)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Remove from history")
            }
            VStack(alignment: .leading, spacing: 2) {
                bullet("Last used", relativeDate(entry.lastSeen))
                bullet("Sessions", "\(entry.sessionCount)")
                if entry.warningCount > 0 {
                    bullet("Warning sessions", "\(entry.warningCount)")
                        .foregroundStyle(entry.warningCount > 0 ? Color.orange : .secondary)
                }
                if let port = entry.lastPort {
                    bullet("Last port", port)
                }
                if let watts = entry.lastWatts, watts > 0 {
                    bullet("Last negotiated", "\(watts) W")
                }
                if let speed = entry.lastSpeedGbps {
                    bullet("Last link", Self.gbps(speed))
                }
            }
            .padding(.leading, 26)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bullet(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: "•").foregroundStyle(.secondary)
            Text("\(label): \(value)").scaledFont(.callout)
            Spacer()
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func gbps(_ v: Double) -> String {
        if v < 1 { return "\(Int((v * 1000).rounded())) Mbps" }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v)) Gbps" }
        return "\(v) Gbps"
    }
}
