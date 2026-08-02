import Foundation
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Pro CLI commands: a live power monitor (`--monitor`) and its
/// newline-delimited-JSON sibling (`--monitor-json`).
enum ProCLICommands {
    static var commands: [CLICommand] { [monitor, dashboard, licence] }

    /// No-op licence commands. This build has no licence gate, so the flags
    /// the docs describe exist and are accepted, and each explains that Pro
    /// is already unlocked rather than trying to hit a licence server.
    private static let licenceFlags: Set<String> = ["--activate", "--licence", "--deactivate", "--silence-pro-hints", "--show-pro-hints"]
    private static let licence = CLICommand(
        flagNames: licenceFlags,
        helpLines: """
          --activate KEY  Validate and store a Pro licence (no-op: Pro is unlocked here)
          --licence       Show licence status (always: Pro unlocked)
          --deactivate    Remove the stored licence (no-op)
          --silence-pro-hints   Hide Pro hints (nothing to hide in this build)
          --show-pro-hints      Show Pro hints (nothing to show in this build)

        """,
        readsCableData: false,
        matches: { args in
            args.contains(where: { licenceFlags.contains($0) })
        },
        run: { args in
            let message: String
            if args.contains("--activate") {
                message = "Pro is already unlocked in this build — no licence key needed."
            } else if args.contains("--deactivate") {
                message = "There is no licence to deactivate in this build."
            } else if args.contains("--licence") {
                message = "Pro: unlocked (source build — no licence required)."
            } else {
                message = "Pro hints are always off in this build (everything is unlocked)."
            }
            print(message)
        }
    )

    private static let monitor = CLICommand(
        flagNames: ["--monitor", "--monitor-json"],
        helpLines: """
          --monitor      Live power monitor (Ctrl+C to exit)
          --monitor-json Live power monitor, one JSON snapshot per line

        """,
        readsCableData: true,
        matches: { args in args.contains("--monitor") || args.contains("--monitor-json") },
        run: { args in
            await runMonitor(asJSON: args.contains("--monitor-json"))
        }
    )

    private static let dashboard = CLICommand(
        flagNames: ["--dashboard"],
        helpLines: """
          --dashboard    Live full-screen terminal dashboard (Tab to switch views)

        """,
        readsCableData: true,
        matches: { args in args.contains("--dashboard") },
        run: { _ in
            await ProDashboard.run()
        }
    )

    @MainActor
    private static func runMonitor(asJSON: Bool) async {
        let service = PowerService()
        service.start()
        defer { service.stop() }

        for await snapshot in service.snapshots {
            if asJSON {
                if let line = encodeJSON(snapshot) {
                    print(line)
                    fflush(stdout)
                }
            } else {
                print("\u{1B}[2J\u{1B}[H", terminator: "")
                print(renderText(snapshot))
                fflush(stdout)
            }
        }
    }

    private static func encodeJSON(_ snapshot: PowerMonitorSnapshot) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              let line = String(data: data, encoding: .utf8) else { return nil }
        return line
    }

    private static func renderText(_ snapshot: PowerMonitorSnapshot) -> String {
        var lines: [String] = []
        let source = snapshot.onBattery
            ? "Battery"
            : (snapshot.batteryInstalled ? "Charger" : "AC power")
        lines.append("Power Monitor · \(timestampFormatter.string(from: snapshot.timestamp)) · \(source)")
        lines.append(String(
            format: "  System: %.1f W · %.1f V · %.2f A",
            Double(snapshot.activePowerMW) / 1000,
            Double(snapshot.activeVoltageMV) / 1000,
            Double(snapshot.activeCurrentMA) / 1000
        ))
        if let estimate = snapshot.resistanceEstimate, estimate.status == .stable {
            lines.append(String(
                format: "  Cable resistance: %.0f mΩ · r²=%.2f",
                estimate.milliohms, estimate.rSquared
            ))
        }
        for sample in snapshot.portSamples.sorted(by: {
            ($0.portIndex, $0.portKey) < ($1.portIndex, $1.portKey)
        }) {
            let tag = sample.isSMCMeasured ? "live" : (sample.isContractedFallback ? "contract" : "pdo")
            lines.append(String(
                format: "  Port %@: %.1f W · %.1f V · %.2f A [%@]",
                sample.portKey,
                Double(sample.watts) / 1000,
                Double(sample.configuredVoltage) / 1000,
                Double(sample.current) / 1000,
                tag
            ))
        }
        return lines.joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
