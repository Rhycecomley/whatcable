import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Negotiation Diagnostics screen (route `pro.negotiation`).
///
/// For one port it lays out, side by side, what the Mac port, the cable and
/// the connected device each support against what actually got negotiated,
/// with the binding constraint highlighted. Power (charging) and data (link
/// speed) verdicts come from the shared Core diagnostics; the negotiated PD
/// contract is shown as the source's PDO profile list.
struct ProNegotiationDiagnosticsView: View {
    let context: PortCardContext?

    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @ObservedObject private var deviceWatcher = WatcherHub.shared.deviceWatcher
    @ObservedObject private var powerWatcher = WatcherHub.shared.powerWatcher
    @ObservedObject private var pdWatcher = WatcherHub.shared.pdWatcher
    @ObservedObject private var tbWatcher = WatcherHub.shared.tbWatcher
    @ObservedObject private var usb3Watcher = WatcherHub.shared.usb3Watcher
    @ObservedObject private var trmWatcher = WatcherHub.shared.trmWatcher
    @Environment(\.fontScale) private var fontScale

    private var port: AppleHPMInterface? {
        guard let key = context?.portKey else { return nil }
        return portWatcher.ports.first { $0.portKey == key }
    }

    private var devices: [USBDevice] {
        port?.matchingDevices(from: deviceWatcher.devices) ?? []
    }

    private var identities: [USBPDSOP] {
        if let port { return pdWatcher.identities(for: port) }
        guard let key = context?.portKey else { return [] }
        return pdWatcher.identities.filter { $0.portKey == key }
    }

    private var cableEmarker: USBPDSOP? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    private var chargingDiagnostic: ChargingDiagnostic? {
        guard let port else { return nil }
        let battery = AppleSmartBatteryReader.read()
        let sources = powerWatcher.sources(for: port)
        let adapter = SystemPower.currentAdapter()
        let activePortCount = portWatcher.ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
            ports: portWatcher.ports, sources: powerWatcher.sources)
        let wattageSource = ChargerWattageSource.resolve(
            portSources: sources,
            activePortCount: activePortCount,
            chargerSourceCount: chargerSourceCount,
            adapter: adapter
        )
        let chargingPortKeys = Set(portWatcher.ports.compactMap { p -> String? in
            PowerSource.hasLiveChargingContract(in: powerWatcher.sources(for: p)) ? p.portKey : nil
        })
        return ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: identities,
            adapter: adapter,
            wattageSource: wattageSource,
            batteryFullyCharged: battery.battery?.fullyCharged,
            batteryIsCharging: battery.battery?.isCharging,
            anotherPortActivelyCharging: port.portKey.map { key in
                chargingPortKeys.contains { $0 != key }
            } ?? false,
            federatedIdentities: battery.federatedIdentities
        )
    }

    private var dataLinkDiagnostic: DataLinkDiagnostic? {
        guard let port else { return nil }
        return DataLinkDiagnostic(
            port: port,
            identities: identities,
            devices: devices,
            usb3Transports: usb3Watcher.transports(for: port),
            cio: trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
            thunderboltSwitches: tbWatcher.switches
        )
    }

    private var powerSources: [PowerSource] {
        guard let port else { return [] }
        return powerWatcher.sources(for: port)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let charging = chargingDiagnostic {
                    verdictCard(
                        title: "Charging",
                        summary: charging.summary,
                        detail: charging.detail,
                        warning: charging.isWarning,
                        icon: charging.isWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
                    )
                }
                if let dataLink = dataLinkDiagnostic {
                    verdictCard(
                        title: "Data link",
                        summary: dataLink.summary,
                        detail: dataLink.detail,
                        warning: dataLink.isWarning,
                        icon: dataLink.isWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
                    )
                    factsTiles(dataLink.facts)
                }
                contractSection
                pdoSection
            }
            .padding(12)
        }
        .frame(minWidth: 560 * fontScale, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Negotiation Diagnostics").scaledFont(.title2, weight: .bold)
            Text(port?.portDescription ?? context?.serviceName ?? "Port")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Verdicts

    private func verdictCard(title: String, summary: String, detail: String, warning: Bool, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(warning ? Color.orange : Color.green)
                .scaledFont(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
                Text(summary).scaledFont(.callout, weight: .bold)
                Text(detail).scaledFont(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((warning ? Color.orange : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data-link facts, side by side

    private func factsTiles(_ facts: DataLinkDiagnostic.Facts) -> some View {
        let weakest = weakestParty(dataLinkDiagnostic?.bottleneck)
        return HStack(alignment: .top, spacing: 8) {
            tile("Mac port", facts.hostGbps.map(Self.gbps) ?? "?", weakest == .host)
            tile("Cable", facts.cableGbps.map(Self.gbps) ?? "?", weakest == .cable)
            tile("Device", facts.deviceGbps.map(Self.gbps) ?? "?", weakest == .device)
            tile("Negotiated", Self.gbps(facts.activeGbps), weakest == nil)
        }
        .padding(.bottom, 2)
    }

    private enum WeakParty { case host, cable, device }

    private func weakestParty(_ bottleneck: DataLinkDiagnostic.Bottleneck?) -> WeakParty? {
        switch bottleneck {
        case .cableLimit, .cableContradictsActive, .unknownCable: return .cable
        case .hostLimit: return .host
        case .deviceLimit: return .device
        default: return nil
        }
    }

    private func tile(_ label: String, _ value: String, _ isWeakest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).scaledFont(.caption2, weight: .semibold).foregroundStyle(.secondary)
            Text(value).scaledFont(.callout, weight: .bold, monospacedDigit: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            (isWeakest ? Color.orange : Color.secondary).opacity(isWeakest ? 0.15 : 0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isWeakest ? Color.orange.opacity(0.6) : .clear, lineWidth: 1)
        )
    }

    private static func gbps(_ v: Double) -> String {
        if v < 1 { return "\(Int((v * 1000).rounded())) Mbps" }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v)) Gbps" }
        return "\(v) Gbps"
    }

    // MARK: - Negotiated contract

    private var contractSection: some View {
        section("Negotiated contract") {
            if let charging = chargingDiagnostic, let negotiated = charging.negotiatedWattsLabel {
                contractRow("Charger", charging.chargerW.map { "\($0) W" } ?? "—")
                contractRow("Cable rating", charging.cableW.map { "\($0) W" } ?? "—")
                contractRow("Negotiated", negotiated)
            } else {
                Text("No active power contract on this port.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pdoSection: some View {
        section("PD profiles") {
            let sources = powerSources
            if sources.isEmpty {
                Text("No power sources on this port.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sources, id: \.id) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                        ForEach(source.options.sorted(by: { $0.voltageMV < $1.voltageMV }), id: \.self) { option in
                            let isWinning = option == source.winning
                            HStack(spacing: 6) {
                                Image(systemName: isWinning ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isWinning ? Color.green : Color.secondary)
                                    .scaledFont(.caption)
                                Text(verbatim: "\(option.voltsLabel) @ \(option.ampsLabel) — \(option.wattsLabel)")
                                    .scaledFont(.callout, monospacedDigit: true)
                                if isWinning {
                                    Text("active").scaledFont(.caption2, weight: .semibold).foregroundStyle(.green)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func contractRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).scaledFont(.caption).foregroundStyle(.secondary)
                .frame(width: 120 * fontScale, alignment: .leading)
            Text(value).scaledFont(.callout, monospacedDigit: true)
            Spacer()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension ChargingDiagnostic {
    var negotiatedWattsLabel: String? {
        switch bottleneck {
        case .fine(let w): return w > 0 ? "\(w) W" : nil
        case .macLimit(let w, _, _): return w > 0 ? "\(w) W" : nil
        case .chargerLimit(let w): return w > 0 ? "\(w) W" : nil
        case .standbyCharger(let w): return w > 0 ? "\(w) W" : nil
        case .cableLimit, .noCharger: return nil
        }
    }
}
