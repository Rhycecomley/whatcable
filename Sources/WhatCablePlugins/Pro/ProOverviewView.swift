import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// The "WhatCable Pro" overview screen (route `pro.overview`): a landing page
/// listing what this build unlocks, with buttons straight into each screen.
struct ProOverviewView: View {
    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @Environment(\.fontScale) private var fontScale

    private var firstPort: AppleHPMInterface? {
        portWatcher.ports.first { $0.portKey != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("WhatCable Pro").scaledFont(.title2, weight: .bold)
                Text("Everything below is unlocked in this build — no licence needed.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)

                featureCard(
                    icon: "bolt.fill",
                    title: "Power Monitor",
                    detail: "Live system power input, per-port metering and cable resistance."
                ) {
                    ProPlugin.openProScreen(id: "pro.power-monitor")
                }

                if let port = firstPort {
                    featureCard(
                        icon: "arrow.left.arrow.right",
                        title: "Negotiation Diagnostics",
                        detail: "What the Mac, cable and device support vs what was negotiated, for \(port.portDescription ?? port.serviceName)."
                    ) {
                        ProPlugin.openProScreen(id: "pro.negotiation", portCard: ProPlugin.context(for: port))
                    }
                    featureCard(
                        icon: "cpu",
                        title: "Cable Diagnostics",
                        detail: "Per-port pin maps, liquid detection and connection health for \(port.portDescription ?? port.serviceName)."
                    ) {
                        ProPlugin.openProScreen(id: "pro.cable-diagnostics", portCard: ProPlugin.context(for: port))
                    }
                    featureCard(
                        icon: "display",
                        title: "Display Diagnostics",
                        detail: "Your monitor's live mode vs what the DisplayPort link carries, for \(port.portDescription ?? port.serviceName)."
                    ) {
                        ProPlugin.openProScreen(id: "pro.display-diagnostics", portCard: ProPlugin.context(for: port))
                    }
                } else {
                    featureCard(
                        icon: "arrow.left.arrow.right",
                        title: "Negotiation Diagnostics",
                        detail: "What the Mac, cable and device support vs what was negotiated. Plug a cable in to open it for a specific port."
                    ) {}
                    featureCard(
                        icon: "cpu",
                        title: "Cable Diagnostics",
                        detail: "Per-port pin maps, liquid detection and connection health. Plug a cable in to open it for a specific port."
                    ) {}
                    featureCard(
                        icon: "display",
                        title: "Display Diagnostics",
                        detail: "Your monitor's live mode vs what the DisplayPort link carries. Connect a display to open it."
                    ) {}
                }

                featureCard(
                    icon: "cable.connector.horizontal",
                    title: "Saved Cables",
                    detail: "Every e-marked cable you use, tracked across sessions with its history."
                ) {
                    ProPlugin.openProScreen(id: "pro.saved-cables")
                }

                infoRow("Pin diagrams", "Live 24-pin USB-C map and liquid-detection status on every port card.")
                infoRow("Port health", "Overcurrent trips, plug events and connection counts per port.")
            }
            .padding(12)
        }
        .frame(minWidth: 520 * fontScale, alignment: .topLeading)
    }

    private func featureCard(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .scaledFont(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(.callout, weight: .bold)
                    Text(detail).scaledFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").scaledFont(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func infoRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(.callout)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(.callout, weight: .semibold)
                Text(detail).scaledFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// The Pro section in Settings. Replaces the stock "Upgrade to WhatCable Pro"
/// link once the plugin is present.
struct ProSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WhatCable Pro", systemImage: "bolt.fill")
                .scaledFont(.body, weight: .semibold)
            Text("This build unlocks every Pro feature — no licence needed.")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            Button("Open Power Monitor…") {
                ProPlugin.openProScreen(id: "pro.power-monitor")
            }
            .scaledFont(.body)
        }
    }
}

/// The bolt button in the popover header that jumps straight to the Power
/// Monitor screen.
struct ProPowerMonitorHeaderButton: View {
    var body: some View {
        Button {
            ProPlugin.openProScreen(id: "pro.power-monitor")
        } label: {
            Image(systemName: "bolt")
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Power Monitor")
    }
}
