import Combine
import Foundation
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Supplies the power data the macOS widget reads: per-port watts and a
/// rolling system-power history.
///
/// Rather than running its own 1 Hz poll, this piggybacks on
/// `WatcherHub.shared.didRefresh`, so it samples at the hub's own cadence
/// (1 Hz while any UI surface is visible, 30 s idle). The `PowerService` is
/// only ever driven by `refresh()`, never `start()`, and shares the hub's
/// single AppleSMC connection.
@MainActor
final class ProPowerWidgetContributor: WidgetDataContributor {
    static let shared = ProPowerWidgetContributor()

    private let service: PowerService
    private let changesSubject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private var systemCurrent: Double = 0
    private var systemHistory: [Double] = []
    private var portHistory: [String: [Double]] = [:]
    /// Samples kept per series. 90 s at the visible 1 Hz cadence.
    private let maxSamples = 90

    private init() {
        service = PowerService(smcReader: WatcherHub.shared.smcReader)
    }

    func start() {
        guard !started else { return }
        started = true

        service.updatePorts(WatcherHub.shared.portWatcher.ports)

        WatcherHub.shared.portWatcher.$ports
            .sink { [weak service] ports in
                service?.updatePorts(ports)
            }
            .store(in: &cancellables)

        WatcherHub.shared.didRefresh
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &cancellables)

        tick()
    }

    func stop() {
        cancellables.removeAll()
        service.stop()
        started = false
    }

    private func tick() {
        service.refresh()
        guard let snapshot = service.latestSnapshot else { return }
        record(snapshot)
    }

    private func record(_ snapshot: PowerMonitorSnapshot) {
        let current = Double(snapshot.activePowerMW) / 1000
        systemCurrent = current
        append(&systemHistory, current)

        for sample in snapshot.portSamples {
            let watts = Double(sample.watts) / 1000
            var history = portHistory[sample.portKey, default: []]
            append(&history, watts)
            portHistory[sample.portKey] = history
        }

        changesSubject.send()
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > maxSamples {
            history.removeFirst(history.count - maxSamples)
        }
    }

    func recentPower(forPortKey key: String) -> [Double]? {
        guard let history = portHistory[key], !history.isEmpty else { return nil }
        return history
    }

    func latestSystemPower() -> (current: Double, history: [Double])? {
        guard !systemHistory.isEmpty else { return nil }
        return (systemCurrent, systemHistory)
    }
}
