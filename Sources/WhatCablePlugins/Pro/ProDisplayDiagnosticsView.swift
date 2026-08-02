import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Display Diagnostics screen (route `pro.display-diagnostics`).
///
/// For one port it compares each connected monitor's live on-screen mode and
/// top mode (read from CoreGraphics, so true 5K/6K modes are right even when
/// the EDID under-describes them) against the bandwidth the DisplayPort link
/// actually carries, using the shared `DisplayDiagnostic` verdicts.
struct ProDisplayDiagnosticsView: View {
    let context: PortCardContext?

    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @ObservedObject private var displayWatcher = WatcherHub.shared.displayWatcher
    @ObservedObject private var pdWatcher = WatcherHub.shared.pdWatcher
    @ObservedObject private var deviceWatcher = WatcherHub.shared.deviceWatcher
    @Environment(\.fontScale) private var fontScale

    private var port: AppleHPMInterface? {
        guard let key = context?.portKey else { return nil }
        return portWatcher.ports.first { $0.portKey == key }
    }

    private var identities: [USBPDSOP] {
        if let port { return pdWatcher.identities(for: port) }
        guard let key = context?.portKey else { return [] }
        return pdWatcher.identities.filter { $0.portKey == key }
    }

    private var cableEmarker: USBPDSOP? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    private var billboardPresent: Bool {
        guard let port else { return false }
        return port.hasBillboardDevice(among: deviceWatcher.devices)
    }

    private var displayStatuses: [IOPortTransportStateDisplayPort] {
        if let port {
            return displayWatcher.statuses
                .filter { $0.status.canonicallyMatches(port: port) }
                .map(\.status)
        }
        guard let key = context?.portKey else { return [] }
        return displayWatcher.statuses.filter { $0.status.portKey == key }.map(\.status)
    }

    private var diagnostics: [(diagnostic: DisplayDiagnostic, link: DisplayPortLink)] {
        displayStatuses.compactMap { dp in
            DisplayDiagnostic(dp: dp, cable: cableEmarker, billboardPresent: billboardPresent)
                .map { ($0, dp.link) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if diagnostics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .scaledFont(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No active display on this port.")
                            .scaledFont(.headline, weight: .bold)
                        Text("Connect a monitor to a USB-C or HDMI port and it will appear here.")
                            .scaledFont(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, pair in
                        diagnosticCard(pair.diagnostic, link: pair.link)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 520 * fontScale, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Display Diagnostics").scaledFont(.title2, weight: .bold)
            Text(port?.portDescription ?? context?.serviceName ?? "Port")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func diagnosticCard(_ diagnostic: DisplayDiagnostic, link: DisplayPortLink) -> some View {
        let facts = diagnostic.facts
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: diagnostic.isWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(diagnostic.isWarning ? Color.orange : Color.green)
                    .scaledFont(.callout)
                VStack(alignment: .leading, spacing: 2) {
                    Text(facts.monitorName ?? "Display").scaledFont(.callout, weight: .bold)
                    Text(diagnostic.summary).scaledFont(.callout, weight: .semibold)
                    Text(diagnostic.detail).scaledFont(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let preferredWidth = facts.preferredWidth, let preferredHeight = facts.preferredHeight {
                    row("Preferred mode", "\(preferredWidth) x \(preferredHeight)" + (facts.preferredRefreshHz.map { " @ \($0)Hz" } ?? ""))
                }
                if let maxRefresh = facts.maxRefreshHz {
                    row("Max refresh", "\(maxRefresh)Hz")
                }
                if let currentMode = facts.currentMode {
                    row("Live mode", currentMode.label)
                }
                if let maxMode = facts.maxMode {
                    row("Top mode", maxMode.label)
                }
                if let needed = facts.neededGbps {
                    row("Needs", Self.gbps(needed))
                }
                if let delivered = facts.deliveredGbps {
                    row("Link carries", Self.gbps(delivered))
                }
                row("Link", Self.linkLabel(facts))
                if let sinkType = facts.sinkType {
                    row("Adapter", facts.branchDevice.map { "USB-C to \(sinkType) · \($0)" } ?? "USB-C to \(sinkType)")
                }
                row("Cable", link.tunneled
                     ? "Tunnelled (TB/USB4)"
                     : (diagnostic.cableAssessment == .unlikelyTheCable ? "Unlikely the limit" : "Inconclusive"))
            }

            if let billboardNote = diagnostic.billboardNote {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                        .scaledFont(.caption)
                    Text(billboardNote).scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).scaledFont(.caption).foregroundStyle(.secondary)
                .frame(width: 130 * fontScale, alignment: .leading)
            Text(value).scaledFont(.callout, monospacedDigit: true)
            Spacer()
        }
    }

    private static func gbps(_ v: Double) -> String {
        String(format: "%.1f Gbps", v)
    }

    private static func linkLabel(_ facts: DisplayDiagnostic.Facts) -> String {
        if let rate = facts.rateDescription {
            return "\(facts.lanes) of \(facts.maxLanes) lanes at \(rate)"
        }
        return "\(facts.lanes) of \(facts.maxLanes) lanes"
    }
}
