import WhatCableAppKit

public func bootstrapPlugins(registry: PluginRegistry) {
    // The app and CLI both call this during startup, which always runs on the
    // main thread, so hopping to the main actor here is safe. All Pro surfaces
    // live in the `Pro/` directory of this target (see ProPlugin.bootstrap).
    MainActor.assumeIsolated {
        ProPlugin.bootstrap(registry: registry)
    }
}
