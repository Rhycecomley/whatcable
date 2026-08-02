import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Compact per-port controls shown at the trailing edge of a port card:
/// a pin-diagram button and a liquid-detection indicator.
///
/// The pin map itself is drawn from the port's IOKit `Pin Configuration`
/// (the same data `ContentView` hands us in `PortCardContext`); the liquid
/// state is read off the live HPM port model.
struct ProPortCardTrailing: View {
    let context: PortCardContext
    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @State private var showPinDiagram = false

    private var livePort: AppleHPMInterface? {
        guard let key = context.portKey else { return nil }
        return portWatcher.ports.first { $0.portKey == key }
    }

    private var liquidState: String? {
        guard let state = livePort?.ldcmStateDescription, !state.isEmpty else { return nil }
        return state
    }

    private var liquidDetected: Bool {
        guard let state = liquidState else { return false }
        return state.lowercased() != "idle"
    }

    private var hasPinMap: Bool {
        USBCPinMap.from(pinConfiguration: context.pinConfiguration, plugOrientation: context.plugOrientation) != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            if hasPinMap || liquidState != nil {
                Button {
                    showPinDiagram = true
                } label: {
                    Image(systemName: "cpu")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Pin diagram")
            }
            if let liquid = liquidState {
                Image(systemName: liquidDetected ? "drop.fill" : "drop")
                    .scaledFont(.caption)
                    .foregroundStyle(liquidDetected ? Color.orange : Color.secondary)
                    .help(liquidDetected ? "Liquid detected: \(liquid)" : "Liquid detection: \(liquid)")
            }
        }
        .popover(isPresented: $showPinDiagram, arrowEdge: .trailing) {
            ProPinDiagramPopover(context: context, liquidState: liquidState, liquidDetected: liquidDetected)
        }
    }
}

/// Full pin-map diagram, shared between the port-card popover and the Cable
/// Diagnostics screen.
struct ProPinDiagramPopover: View {
    let context: PortCardContext?
    let liquidState: String?
    let liquidDetected: Bool
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin Diagram").scaledFont(.headline, weight: .bold)
            if let context,
               let map = USBCPinMap.from(pinConfiguration: context.pinConfiguration, plugOrientation: context.plugOrientation) {
                Text(map.signalSummary).scaledFont(.callout).foregroundStyle(.secondary)
                Text("Orientation: \(map.orientationLabel)").scaledFont(.caption).foregroundStyle(.secondary)
                pinRows(map)
                legend
            } else {
                Text("No pin configuration data for this port.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            }
            if let liquidState {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: liquidDetected ? "drop.fill" : "drop")
                        .foregroundStyle(liquidDetected ? Color.orange : Color.secondary)
                    Text(liquidDetected ? "Liquid detected — \(liquidState)" : "Liquid detection: \(liquidState)")
                        .scaledFont(.callout)
                }
            }
        }
        .padding(14)
    }

    private func pinRows(_ map: USBCPinMap) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(map.topRow) { pin in PinCell(pin: pin) }
            }
            HStack(spacing: 3) {
                ForEach(map.bottomRow) { pin in PinCell(pin: pin) }
            }
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], alignment: .leading, spacing: 4) {
            ForEach(legendItems, id: \.name) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.name).scaledFont(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var legendItems: [(name: String, color: Color)] {
        [
            ("Inactive", .secondary.opacity(0.3)),
            ("GND", .gray),
            ("VBUS", .red),
            ("CC", .teal),
            ("USB 2.0", .blue),
            ("USB 3", .green),
            ("DP Lane", .orange),
            ("DP AUX", .purple)
        ]
    }
}

private struct PinCell: View {
    let pin: USBCPinMap.Pin
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(spacing: 1) {
            Text(pin.id)
                .font(.system(size: 7 * fontScale))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8 * fontScale, height: 8 * fontScale)
        }
        .frame(width: 18 * fontScale)
    }

    private var color: Color {
        switch pin.signal {
        case .inactive: return Color.secondary.opacity(0.3)
        case .ground: return .gray
        case .vbus: return .red
        case .cc: return .teal
        case .usb2: return .blue
        case .usb3PairA, .usb3PairB: return .green
        case .dpLane: return .orange
        case .dpAux: return .purple
        case .unknown: return .gray
        }
    }
}
