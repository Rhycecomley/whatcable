import SwiftUI
import Combine
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// The Power Monitor Pro screen.
///
/// Owns a `PowerService` (sharing the hub's single AppleSMC connection),
/// keeps its per-port UUID map fresh from the live HPM port list, and renders
/// the latest snapshot: system power in (or battery discharge), per-port
/// readings, and the cable resistance estimate.
struct ProPowerMonitorView: View {
    @StateObject private var service: PowerService
    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @State private var portUpdateCancellable: AnyCancellable?
    @State private var history: [Double] = []
    private let historyCapacity = 90
    @Environment(\.fontScale) private var fontScale

    init() {
        _service = StateObject(wrappedValue: PowerService(smcReader: WatcherHub.shared.smcReader))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let snap = service.latestSnapshot {
                    systemCard(snap)
                    if history.count > 1 {
                        powerGraph(snap)
                    }
                    if !snap.portSamples.isEmpty {
                        portPowerSection(snap)
                    } else {
                        noPortData(snap)
                    }
                    resistanceCard(snap)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Reading power…")
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 520 * fontScale, alignment: .topLeading)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(service.$latestSnapshot) { snap in
            guard let snap else { return }
            history.append(Double(snap.activePowerMW) / 1000)
            if history.count > historyCapacity {
                history.removeFirst(history.count - historyCapacity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Power Monitor").scaledFont(.title2, weight: .bold)
            Spacer()
            if let snap = service.latestSnapshot {
                Text(sourceLabel(snap))
                    .scaledFont(.caption, weight: .semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sourceColor(snap).opacity(0.15), in: Capsule())
            }
        }
    }

    private func start() {
        service.updatePorts(portWatcher.ports)
        portUpdateCancellable = portWatcher.$ports.sink { [weak service] ports in
            service?.updatePorts(ports)
        }
        service.start()
    }

    private func stop() {
        portUpdateCancellable = nil
        history.removeAll()
        service.stop()
    }

    // MARK: - System power graph

    private func powerGraph(_ snap: PowerMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("System power input").scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "last \(history.count)s")
                    .scaledFont(.caption2)
                    .foregroundStyle(.tertiary)
            }
            PowerSparkline(samples: history, onBattery: snap.onBattery)
                .frame(height: 90 * fontScale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - System card

    private func systemCard(_ snap: PowerMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(watts(snap.activePowerMW))
                    .scaledFont(size: 44, weight: .bold, monospacedDigit: true)
                Text("W").scaledFont(.title3, weight: .semibold).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                metric("Voltage", volts(snap.activeVoltageMV))
                metric("Current", amps(snap.activeCurrentMA))
            }
            Text(systemStatusLine(snap))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).scaledFont(.headline, monospacedDigit: true)
            Text(label).scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    private func systemStatusLine(_ snap: PowerMonitorSnapshot) -> String {
        if snap.onBattery {
            return "On battery — discharging"
        }
        if !snap.hasContract && !snap.perPortMeteringSupported {
            return "Waiting for live data…"
        }
        return snap.perPortMeteringSupported
            ? "Charger input · per-port metering available"
            : "Charger input"
    }

    // MARK: - Per-port section

    private func portPowerSection(_ snap: PowerMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-port power").scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
            ForEach(snap.portSamples.sorted(by: { ($0.portIndex, $0.portKey) < ($1.portIndex, $1.portKey) }), id: \.portKey) { sample in
                portRow(sample)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func portRow(_ sample: PortPowerSample) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(portName(sample.portKey)).scaledFont(.callout, weight: .semibold)
                Text(verbatim: "\(volts(sample.configuredVoltage)) · \(amps(sample.current))")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(watts(sample.watts)).scaledFont(.headline, monospacedDigit: true)
            Text("W").scaledFont(.caption).foregroundStyle(.secondary)
            meteringBadge(sample)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func meteringBadge(_ sample: PortPowerSample) -> some View {
        if sample.isSMCMeasured {
            Text("live").scaledFont(.caption2, weight: .semibold).foregroundStyle(.green)
        } else if sample.isContractedFallback {
            Text("contract").scaledFont(.caption2, weight: .semibold).foregroundStyle(.secondary)
        }
    }

    private func noPortData(_ snap: PowerMonitorSnapshot) -> some View {
        Text(snap.perPortMeteringSupported
             ? "No per-port readings yet — plug something in."
             : "This Mac doesn't expose live per-port power metering.")
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Resistance card

    @ViewBuilder
    private func resistanceCard(_ snap: PowerMonitorSnapshot) -> some View {
        if let estimate = snap.resistanceEstimate {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cable resistance").scaledFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                switch estimate.status {
                case .stable:
                    Text(String(format: "%.0f mΩ", estimate.milliohms))
                        .scaledFont(.headline, monospacedDigit: true)
                    if let tier = estimate.tier(ratedFiveA: false) {
                        Text(tierLabel(tier)).scaledFont(.caption).foregroundStyle(tierColor(tier))
                    }
                case .converging:
                    Text("Converging — \(estimate.sampleCount) samples").scaledFont(.callout).foregroundStyle(.secondary)
                case .insufficient:
                    Text("Insufficient data — keep the load steady").scaledFont(.callout).foregroundStyle(.secondary)
                case .unreliable:
                    Text("Unreliable — vary the load to estimate").scaledFont(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tierLabel(_ tier: CableResistanceEstimate.Tier) -> String {
        switch tier {
        case .good: return "Well within spec"
        case .marginal: return "Within spec, approaching the ceiling"
        case .high: return "Over the spec budget for this cable rating"
        }
    }

    private func tierColor(_ tier: CableResistanceEstimate.Tier) -> Color {
        switch tier {
        case .good: return .green
        case .marginal: return .orange
        case .high: return .red
        }
    }

    // MARK: - Formatting

    private func portName(_ key: String) -> String {
        guard let port = portWatcher.ports.first(where: { $0.portKey == key }) else { return key }
        return port.portDescription ?? port.serviceName
    }

    private func sourceLabel(_ snap: PowerMonitorSnapshot) -> String {
        if snap.onBattery { return "Battery" }
        return snap.batteryInstalled ? "Charger" : "AC power"
    }

    private func sourceColor(_ snap: PowerMonitorSnapshot) -> Color {
        snap.onBattery ? .blue : .green
    }

    private func watts(_ mW: Int) -> String { String(format: "%.1f", Double(mW) / 1000) }
    private func volts(_ mV: Int) -> String { String(format: "%.1f V", Double(mV) / 1000) }
    private func amps(_ mA: Int) -> String { String(format: "%.2f A", Double(mA) / 1000) }
}

/// A compact live sparkline of a rolling power series, with faint axis ticks
/// and a gradient fill under the line. No charting dependency: just a path
/// drawn into a `GeometryReader`.
struct PowerSparkline: View {
    let samples: [Double]
    let onBattery: Bool
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let maxValue = max(samples.max() ?? 0, 1)
            let minValue = samples.min() ?? 0
            let span = max(maxValue - minValue, 0.1)

            let points = samples.enumerated().map { index, value in
                let x = width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                let y = height - height * CGFloat((value - minValue) / span)
                return CGPoint(x: x, y: y)
            }

            let line = Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }

            ZStack {
                // Faint grid lines so the scale reads against the shape.
                ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)
                        .position(x: width / 2, y: height * CGFloat(fraction))
                }

                // Gradient fill under the line.
                line
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                line
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Min / max labels.
                Text(String(format: "%.0f", minValue))
                    .font(.system(size: 8 * fontScale))
                    .foregroundStyle(.tertiary)
                    .position(x: width - 4, y: height)
                Text(String(format: "%.0f", maxValue))
                    .font(.system(size: 8 * fontScale))
                    .foregroundStyle(.tertiary)
                    .position(x: width - 4, y: 0)
            }
        }
    }

    private var accent: Color {
        onBattery ? .blue : .green
    }
}
