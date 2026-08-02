import Combine
import Foundation
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Persistent record of the cables this Mac has been used with.
///
/// The sampler rides `WatcherHub.shared.didRefresh` (the hub's own cadence:
/// 1 Hz while any UI surface is visible, 30 s idle), so it never starts a
/// second IOKit poll. Each cable e-marker is fingerprinted and tracked across
/// sessions: first/last seen, session count, warnings, and the last port,
/// negotiated wattage and link speed. Persisted to JSON in Application Support.
@MainActor
final class ProCableHistoryStore: ObservableObject {
    static let shared = ProCableHistoryStore()

    struct Entry: Codable, Identifiable, Equatable {
        var id: String            // fingerprint
        var name: String
        var vendorID: Int
        var productID: Int
        var firstSeen: Date
        var lastSeen: Date
        var sessionCount: Int
        var warningCount: Int
        var lastPort: String?
        var lastWatts: Int?
        var lastSpeedGbps: Double?
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isSampling = false

    private struct Session {
        var warnedSoFar = false
    }

    private var sessions: [String: Session] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    // MARK: - Sampling

    func start() {
        guard !isSampling else { return }
        isSampling = true
        WatcherHub.shared.didRefresh
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &cancellables)
        tick()
    }

    func stop() {
        cancellables.removeAll()
        isSampling = false
    }

    private func tick() {
        let present = cableFingerprints()
        let now = Date()

        // Departures first: a cable that vanished ends its session and, if
        // it misbehaved while present, is recorded as a warning.
        for (fingerprint, session) in sessions where !present.contains(fingerprint) {
            if session.warnedSoFar {
                mutateEntry(fingerprint) { $0.warningCount += 1 }
            }
            sessions[fingerprint] = nil
        }

        // Present cables: open a new session for first-timers, update the
        // entry's live facts, and fold in this tick's warning signal.
        for fingerprint in present {
            let isNewSession = sessions[fingerprint] == nil
            if isNewSession {
                sessions[fingerprint] = Session(warnedSoFar: cableHasWarning(fingerprint))
                mutateEntry(fingerprint) { entry in
                    entry.sessionCount += 1
                    if entry.firstSeen == .distantPast { entry.firstSeen = now }
                }
            } else {
                if cableHasWarning(fingerprint) {
                    sessions[fingerprint]?.warnedSoFar = true
                }
            }
            updateLiveFacts(fingerprint, now: now)
        }

        scheduleSave()
    }

    // MARK: - Per-cable facts

    private struct CableObservation {
        let fingerprint: String
        let identity: USBPDSOP
        let port: AppleHPMInterface?
        let portKey: String?
    }

    private func observations() -> [CableObservation] {
        WatcherHub.shared.pdWatcher.identities.compactMap { identity in
            guard identity.identifiesAsCable else { return nil }
            let port = WatcherHub.shared.portWatcher.ports.first { $0.portKey == identity.portKey }
            return CableObservation(
                fingerprint: fingerprint(for: identity),
                identity: identity,
                port: port,
                portKey: port?.portKey
            )
        }
    }

    private func cableFingerprints() -> Set<String> {
        Set(observations().map(\.fingerprint))
    }

    private func cableHasWarning(_ fingerprint: String) -> Bool {
        guard let observation = observations().first(where: { $0.fingerprint == fingerprint }),
              let port = observation.port else { return false }
        let hub = WatcherHub.shared
        let identities = hub.pdWatcher.identities(for: port)
        let devices = port.matchingDevices(from: hub.deviceWatcher.devices)
        if let dataLink = DataLinkDiagnostic(
            port: port,
            identities: identities,
            devices: devices,
            usb3Transports: hub.usb3Watcher.transports(for: port),
            cio: hub.trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
            thunderboltSwitches: hub.tbWatcher.switches
        ), dataLink.isWarning {
            return true
        }
        return false
    }

    private func updateLiveFacts(_ fingerprint: String, now: Date) {
        guard let observation = observations().first(where: { $0.fingerprint == fingerprint }) else { return }
        let hub = WatcherHub.shared
        let identity = observation.identity
        mutateEntry(fingerprint) { entry in
            entry.lastSeen = now
            entry.lastPort = observation.portKey ?? identity.portKey
            if let port = observation.port {
                let sources = hub.powerWatcher.sources(for: port)
                if let watts = PowerSource.preferredChargingSource(in: sources)?.winning?.maxPowerMW {
                    entry.lastWatts = Int((Double(watts) / 1000).rounded())
                }
                let devices = port.matchingDevices(from: hub.deviceWatcher.devices)
                if let speed = DataLinkDiagnostic(
                    port: port,
                    identities: hub.pdWatcher.identities(for: port),
                    devices: devices,
                    usb3Transports: hub.usb3Watcher.transports(for: port),
                    cio: hub.trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                    thunderboltSwitches: hub.tbWatcher.switches
                )?.facts.activeGbps {
                    entry.lastSpeedGbps = speed
                }
            }
        }
    }

    // MARK: - Entries

    private func fingerprint(for identity: USBPDSOP) -> String {
        let type = identity.idHeader?.ufpProductType.rawValue ?? 0
        return "\(identity.vendorID)-\(identity.productID)-\(identity.bcdDevice)-\(type)"
    }

    private func defaultName(for identity: USBPDSOP) -> String {
        if let vendor = CableDB.vendorName(vid: identity.vendorID) {
            return "\(vendor) cable"
        }
        return String(format: "USB-C cable (0x%04X)", identity.vendorID)
    }

    private func mutateEntry(_ fingerprint: String, _ mutate: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == fingerprint }) else {
            guard let observation = observations().first(where: { $0.fingerprint == fingerprint }) else { return }
            var entry = Entry(
                id: fingerprint,
                name: defaultName(for: observation.identity),
                vendorID: observation.identity.vendorID,
                productID: observation.identity.productID,
                firstSeen: .distantPast,
                lastSeen: Date(),
                sessionCount: 0,
                warningCount: 0,
                lastPort: nil,
                lastWatts: nil,
                lastSpeedGbps: nil
            )
            mutate(&entry)
            entries.append(entry)
            return
        }
        mutate(&entries[index])
    }

    // MARK: - User actions

    func rename(_ entry: Entry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].name = trimmed
        scheduleSave()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        sessions[entry.id] = nil
        scheduleSave()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WhatCable", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cable-history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(self.entries) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }
}
