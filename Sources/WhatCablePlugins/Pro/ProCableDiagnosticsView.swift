import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Per-port Cable Diagnostics screen (route `pro.cable-diagnostics`).
///
/// Shows the pin map, liquid-detection state, connection facts, port health
/// counters, and the USB-PD identities (SOP / SOP' / SOP'') for one port.
struct ProCableDiagnosticsView: View {
    let context: PortCardContext?

    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @ObservedObject private var pdWatcher = WatcherHub.shared.pdWatcher
    @ObservedObject private var deviceWatcher = WatcherHub.shared.deviceWatcher
    @ObservedObject private var usb3Watcher = WatcherHub.shared.usb3Watcher
    @Environment(\.fontScale) private var fontScale

    private var port: AppleHPMInterface? {
        guard let key = context?.portKey else { return nil }
        return portWatcher.ports.first { $0.portKey == key }
    }

    private var identities: [USBPDSOP] {
        if let port {
            return pdWatcher.identities(for: port)
        }
        guard let key = context?.portKey else { return [] }
        return pdWatcher.identities.filter { $0.portKey == key }
    }

    private var devices: [USBDevice] {
        port?.matchingDevices(from: deviceWatcher.devices) ?? []
    }

    private var liquidState: String? {
        guard let state = port?.ldcmStateDescription, !state.isEmpty else { return nil }
        return state
    }

    private var liquidDetected: Bool {
        guard let state = liquidState else { return false }
        return state.lowercased() != "idle"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ProPinDiagramPopover(
                    context: context,
                    liquidState: liquidState,
                    liquidDetected: liquidDetected
                )
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                connectionSection
                healthSection
                pdSection
                devicesSection
            }
            .padding(12)
        }
        .frame(minWidth: 500 * fontScale, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(port?.portDescription ?? context?.serviceName ?? "Cable Diagnostics")
                    .scaledFont(.title2, weight: .bold)
                if let type = context?.portTypeDescription, let num = context?.portNumber {
                    Text("\(type) Port \(num)").scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let liquidState {
                Label(liquidDetected ? "Liquid detected" : "No liquid",
                      systemImage: liquidDetected ? "drop.fill" : "drop")
                    .scaledFont(.caption)
                    .foregroundStyle(liquidDetected ? Color.orange : Color.secondary)
            }
        }
    }

    // MARK: - Connection facts

    private var connectionSection: some View {
        section("Connection") {
            if let port {
                row("Active", yesNo(port.connectionActive))
                row("Active cable electronics", yesNo(port.activeCable))
                row("Optical", yesNo(port.opticalCable))
                row("USB active", yesNo(port.usbActive))
                row("SuperSpeed", yesNo(port.superSpeedActive))
                row("Plug events", port.plugEventCount.map(String.init) ?? "—")
                row("Connections", port.connectionCount.map(String.init) ?? "—")
                row("Overcurrent trips", port.overcurrentCount.map(String.init) ?? "—")
                if !port.featuresEnabled.isEmpty {
                    row("Features", port.featuresEnabled.joined(separator: ", "))
                }
                if let fw = port.firmwareVersion {
                    row("Firmware", fw)
                }
            } else {
                Text("Port not currently visible.").scaledFont(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var healthSection: some View {
        section("Port health") {
            if let port {
                row("Power limits", port.powerCurrentLimits.isEmpty ? "—" : port.powerCurrentLimits.map { "\($0)mA" }.joined(separator: ", "))
                if let boot = port.bootFlagsHex, !boot.isEmpty {
                    row("Boot flags", boot)
                }
            }
            let overcurrent = port?.overcurrentCount ?? 0
            row("Overcurrent count", "\(overcurrent)")
        }
    }

    // MARK: - PD identities

    private var pdSection: some View {
        section("PD identities") {
            if identities.isEmpty {
                Text("No USB-PD identities captured on this port.")
                    .scaledFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(identities, id: \.id) { identity in
                    identityRow(identity)
                }
            }
        }
    }

    private func identityRow(_ identity: USBPDSOP) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(endpointLabel(identity.endpoint))
                .scaledFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
                .frame(width: 44 * fontScale, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(identitySummary(identity)).scaledFont(.callout)
                if let header = identity.idHeader {
                    Text(header.ufpProductType.label).scaledFont(.caption).foregroundStyle(.secondary)
                }
                if let rev = identity.pdRevisionLabel {
                    Text(rev).scaledFont(.caption).foregroundStyle(.secondary)
                }
                if !identity.vdos.isEmpty {
                    DisclosureGroup("Raw VDOs (\(identity.vdos.count))") {
                        ForEach(Array(identity.vdos.enumerated()), id: \.offset) { index, vdo in
                            Text(verbatim: "VDO[\(index)] 0x\(String(format: "%08X", vdo))")
                                .scaledFont(.caption, design: .monospaced)
                                .textSelection(.enabled)
                        }
                    }
                    .scaledFont(.caption)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Devices

    private var devicesSection: some View {
        section("Connected devices") {
            if devices.isEmpty {
                Text("No USB devices on this port.").scaledFont(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(devices, id: \.id) { device in
                    HStack(spacing: 6) {
                        Text(verbatim: "•").foregroundStyle(.secondary)
                        Text(device.displayName).scaledFont(.callout)
                        Spacer()
                        Text(device.speedLabel).scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary)
                .frame(width: 160 * fontScale, alignment: .leading)
            Text(value).scaledFont(.callout, monospacedDigit: true)
            Spacer()
        }
    }

    private func yesNo(_ v: Bool?) -> String {
        guard let v else { return "—" }
        return v ? "Yes" : "No"
    }

    private func endpointLabel(_ endpoint: USBPDSOP.Endpoint) -> String {
        switch endpoint {
        case .sop: return "SOP"
        case .sopPrime: return "SOP'"
        case .sopDoublePrime: return "SOP''"
        case .unknown: return "?"
        }
    }

    private func identitySummary(_ identity: USBPDSOP) -> String {
        let vendor = CableDB.vendorName(vid: identity.vendorID) ?? String(format: "0x%04X", identity.vendorID)
        var parts = [vendor]
        if identity.productID != 0 {
            parts.append(String(format: "PID 0x%04X", identity.productID))
        }
        return parts.joined(separator: " · ")
    }
}
