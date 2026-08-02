import Darwin
import Foundation
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// The `--dashboard` command: a live full-screen terminal view of every port
/// and the power picture. Tab switches between Overview and Power; q or
/// Ctrl+C exits and restores the terminal.
enum ProDashboard {
    @MainActor
    static func run() async {
        let terminal = DashboardTerminal()
        terminal.enterRawMode()
        Self.installSignalHandlers(restore: { terminal.restore() })
        defer {
            terminal.restore()
            Self.removeSignalHandlers()
        }

        let provider = DarwinSnapshotProvider()
        let powerService = PowerService()
        powerService.start()
        defer { powerService.stop() }

        var screen: Screen = .overview
        while !Task.isCancelled {
            while let key = terminal.pollKey() {
                switch key {
                case 0x09: screen = screen.next       // Tab
                case 0x03, 0x71: return                // Ctrl+C / q
                default: break
                }
            }

            let cable = try? await provider.snapshot()
            let power = powerService.latestSnapshot
            print(render(screen: screen, cable: cable, power: power))
            fflush(stdout)

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private enum Screen: Int, CaseIterable {
        case overview = 0
        case negotiation = 1
        case power = 2

        var next: Screen {
            Screen(rawValue: (rawValue + 1) % Screen.allCases.count)!
        }
    }

    // MARK: - Rendering

    private static func render(screen: Screen, cable: CableSnapshot?, power: PowerMonitorSnapshot?) -> String {
        var lines: [String] = []
        lines.append("\u{1B}[2J\u{1B}[H")
        switch screen {
        case .overview: renderOverview(&lines, cable: cable, power: power)
        case .negotiation: renderNegotiation(&lines, cable: cable)
        case .power: renderPower(&lines, power: power)
        }
        return lines.joined(separator: "\n")
    }

    private static func renderOverview(_ lines: inout [String], cable: CableSnapshot?, power: PowerMonitorSnapshot?) {
        lines.append("WhatCable Dashboard · \(timestamp()) · Overview")
        lines.append("")
        if let cable {
            if cable.ports.isEmpty {
                lines.append("No USB-C ports detected.")
            } else {
                lines.append(String(format: "%-18@ %-11@ %-24@ %@", "PORT" as NSString, "STATE" as NSString, "TRANSPORTS" as NSString, "POWER" as NSString))
                for port in cable.ports {
                    let name = port.portDescription ?? port.serviceName
                    let state = port.connectionActive == true ? "connected" : "idle"
                    let transports = port.transportsActive.isEmpty ? "—" : port.transportsActive.joined(separator: ", ")
                    let watts = power.flatMap { portWatts(for: $0, key: port.portKey) } ?? "—"
                    lines.append(String(format: "%-18@ %-11@ %-24@ %@", name as NSString, state as NSString, transports as NSString, watts as NSString))
                }
            }
        } else {
            lines.append("Reading…")
        }
        if let power {
            lines.append("")
            lines.append(systemPowerLine(power))
        }
        lines.append("")
        lines.append(footer)
    }

    private static func renderNegotiation(_ lines: inout [String], cable: CableSnapshot?) {
        lines.append("WhatCable Dashboard · \(timestamp()) · Negotiation")
        lines.append("")
        guard let cable else {
            lines.append("Reading…")
            lines.append("")
            lines.append(footer)
            return
        }
        let activePorts = cable.ports.filter { $0.connectionActive == true }
        if activePorts.isEmpty {
            lines.append("No active connections.")
            lines.append("")
            lines.append(footer)
            return
        }
        for port in activePorts {
            lines.append(port.portDescription ?? port.serviceName)
            let identities = cable.identities.filter { $0.portKey == port.portKey }
            let devices = port.matchingDevices(from: cable.usbDevices)
            if let dataLink = DataLinkDiagnostic(
                port: port,
                identities: identities,
                devices: devices,
                usb3Transports: cable.usb3Transports,
                cio: cable.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                thunderboltSwitches: cable.thunderboltSwitches
            ) {
                let facts = dataLink.facts
                let parts = [
                    "Host \(speed(facts.hostGbps))",
                    "Cable \(speed(facts.cableGbps))",
                    "Device \(speed(facts.deviceGbps))",
                    "Active \(speed(facts.activeGbps))"
                ]
                lines.append("  \(dataLink.summary)")
                lines.append("  " + parts.joined(separator: " · "))
            } else {
                lines.append("  No data-link verdict.")
            }
            if let charging = ChargingDiagnostic(
                port: port,
                sources: cable.powerSources.filter { $0.portKey == port.portKey },
                identities: identities,
                adapter: cable.adapter,
                batteryFullyCharged: cable.batteryFullyCharged,
                batteryIsCharging: cable.batteryIsCharging,
                federatedIdentities: cable.federatedIdentities
            ) {
                lines.append("  \(charging.summary)")
            }
            lines.append("")
        }
        lines.append(footer)
    }

    private static func renderPower(_ lines: inout [String], power: PowerMonitorSnapshot?) {
        lines.append("WhatCable Dashboard · \(timestamp()) · Power")
        lines.append("")
        if let power {
            lines.append(systemPowerLine(power))
            lines.append("")
            if power.portSamples.isEmpty {
                lines.append("No per-port readings.")
            } else {
                lines.append("PER-PORT POWER")
                for sample in power.portSamples.sorted(by: { ($0.portIndex, $0.portKey) < ($1.portIndex, $1.portKey) }) {
                    let tag = sample.isSMCMeasured ? "live" : (sample.isContractedFallback ? "contract" : "pdo")
                    lines.append(String(
                        format: "  %@  %6.1f W · %5.1f V · %5.2f A  [%@]",
                        sample.portKey,
                        Double(sample.watts) / 1000,
                        Double(sample.configuredVoltage) / 1000,
                        Double(sample.current) / 1000,
                        tag
                    ))
                }
            }
        } else {
            lines.append("Reading…")
        }
        lines.append("")
        lines.append(footer)
    }

    private static func systemPowerLine(_ power: PowerMonitorSnapshot) -> String {
        let source = power.onBattery ? "Battery" : (power.batteryInstalled ? "Charger" : "AC power")
        return String(
            format: "System: %6.1f W · %5.1f V · %5.2f A   (%@)",
            Double(power.activePowerMW) / 1000,
            Double(power.activeVoltageMV) / 1000,
            Double(power.activeCurrentMA) / 1000,
            source
        )
    }

    private static func portWatts(for power: PowerMonitorSnapshot, key: String?) -> String? {
        guard let key else { return nil }
        guard let sample = power.portSamples.first(where: { $0.portKey == key }) else { return nil }
        return String(format: "%.1f W", Double(sample.watts) / 1000)
    }

    private static func speed(_ gbps: Double?) -> String {
        guard let gbps else { return "—" }
        if gbps < 1 { return "\(Int((gbps * 1000).rounded())) Mbps" }
        if gbps.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(gbps)) Gbps" }
        return "\(gbps) Gbps"
    }

    private static let footer = "[Tab] switch view · [q] quit"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    // MARK: - Signal handling

    private static var signalSources: [DispatchSourceSignal] = []

    private static func installSignalHandlers(restore: @escaping () -> Void) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for sig in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                restore()
                exit(128 + sig)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static func removeSignalHandlers() {
        signalSources.removeAll()
    }
}

/// Puts the terminal into raw mode so the dashboard can read single keypresses
/// without Enter, and restores it on exit.
private final class DashboardTerminal {
    private var saved = termios()
    private var isRaw = false

    func enterRawMode() {
        guard !isRaw else { return }
        var t = termios()
        guard tcgetattr(STDIN_FILENO, &t) == 0 else { return }
        saved = t
        // tcflag_t is UInt64 on macOS; the flag macros import as tcflag_t.
        t.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
        t.c_iflag &= ~tcflag_t(IXON)
        t.c_cc.16 = 0   // VMIN: non-blocking read
        t.c_cc.17 = 0   // VTIME: no wait
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
        isRaw = true
    }

    func restore() {
        guard isRaw else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
        isRaw = false
    }

    func pollKey() -> UInt8? {
        var byte: UInt8 = 0
        let count = read(STDIN_FILENO, &byte, 1)
        return count == 1 ? byte : nil
    }
}
