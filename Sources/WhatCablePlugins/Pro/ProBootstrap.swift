import AppKit
import SwiftUI
import Combine
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Entry point for the self-built Pro plugin.
///
/// Registers every Pro surface with the app's plugin registry. Because this
/// is compiled from source there is no licence gate: everything registers
/// unconditionally, so all "Pro" features are unlocked in any build that
/// includes this target.
///
/// All code lives in this `Pro/` directory so that pulling updates from the
/// upstream repository never conflicts with it. The only tracked file this
/// touches is `../Bootstrap.swift`, by a single call.
    @MainActor
    public enum ProPlugin {
        public static func bootstrap(registry: PluginRegistry) {
            registerScreens(registry: registry)
            registerPortCardTrailing(registry: registry)
            registerMenus(registry: registry)
            registerSettings(registry: registry)
            registerWidget(registry: registry)
            registerCLI(registry: registry)
            registerLaunch(registry: registry)
        }

        // MARK: - Pro screens

        private static func registerScreens(registry: PluginRegistry) {
            registry.register(proScreen: "pro.overview") { _ in
                AnyView(ProOverviewView())
            }
            registry.register(proScreen: "pro.power-monitor") { _ in
                AnyView(ProPowerMonitorView())
            }
            registry.register(proScreen: "pro.negotiation") { context in
                AnyView(ProNegotiationDiagnosticsView(context: context))
            }
            registry.register(proScreen: "pro.cable-diagnostics") { context in
                AnyView(ProCableDiagnosticsView(context: context))
            }
            registry.register(proScreen: "pro.display-diagnostics") { context in
                AnyView(ProDisplayDiagnosticsView(context: context))
            }
            registry.register(proScreen: "pro.saved-cables") { _ in
                AnyView(ProSavedCablesView())
            }
        }

    // MARK: - Port-card trailing controls (pin diagram + liquid detection)

    private static func registerPortCardTrailing(registry: PluginRegistry) {
        registry.register(portCardTrailing: { context in
            AnyView(ProPortCardTrailing(context: context))
        })
    }

    // MARK: - Menus

    private static func registerMenus(registry: PluginRegistry) {
        // A bolt button in the popover header, next to pin/refresh/settings.
        registry.register(headerButton: {
            AnyView(ProPowerMonitorHeaderButton())
        })

        // Right-click status item menu entries.
        registry.register(nsMenuItemBuilder: {
            ProMenuItems.shared.makeItem(id: "power-monitor", title: "Power Monitor…") {
                openProScreen(id: "pro.power-monitor")
            }
        }, at: .statusItemMenu)

        registry.register(nsMenuItemBuilder: {
            ProMenuItems.shared.makeItem(id: "negotiation", title: "Negotiation Diagnostics…") {
                openProScreen(id: "pro.negotiation", portCard: firstPortContext())
            }
        }, at: .statusItemMenu)

        registry.register(nsMenuItemBuilder: {
            ProMenuItems.shared.makeItem(id: "display", title: "Display Diagnostics…") {
                openProScreen(id: "pro.display-diagnostics", portCard: firstPortContext())
            }
        }, at: .statusItemMenu)

        registry.register(nsMenuItemBuilder: {
            ProMenuItems.shared.makeItem(id: "saved-cables", title: "Saved Cables…") {
                openProScreen(id: "pro.saved-cables")
            }
        }, at: .statusItemMenu)

        registry.register(nsMenuItemBuilder: {
            ProMenuItems.shared.makeItem(id: "overview", title: "Pro Features…") {
                openProScreen(id: "pro.overview")
            }
        }, at: .statusItemMenu)
    }

    // MARK: - Launch

    private static func registerLaunch(registry: PluginRegistry) {
        registry.register(launchHook: {
            ProCableHistoryStore.shared.start()
        })
    }

    // MARK: - Settings

    private static func registerSettings(registry: PluginRegistry) {
        registry.register(settingsProSection: {
            AnyView(ProSettingsSection())
        })
    }

    // MARK: - Widget power data

    private static func registerWidget(registry: PluginRegistry) {
        registry.register(widgetDataContributor: ProPowerWidgetContributor.shared)
    }

    // MARK: - CLI commands

    private static func registerCLI(registry: PluginRegistry) {
        for command in ProCLICommands.commands {
            registry.register(cliCommand: command)
        }
    }

    // MARK: - Shared helpers

    /// Navigate the app to a Pro screen (rendered in-place, or focused if it
    /// is already detached into its own window).
    public static func openProScreen(id: String, portCard: PortCardContext? = nil) {
        RefreshSignal.shared.activeProScreen = ProScreenRoute(id: id, portCard: portCard)
    }

    /// Build a `PortCardContext` from a live port, mirroring how `ContentView`
    /// constructs the context for its trailing builders.
    public static func context(for port: AppleHPMInterface) -> PortCardContext {
        PortCardContext(
            portKey: port.portKey,
            portNumber: port.portNumber,
            serviceName: port.serviceName,
            portTypeDescription: port.portTypeDescription,
            pinConfiguration: port.pinConfiguration,
            plugOrientation: port.plugOrientation
        )
    }

    /// The first port that carries any data, for global menu entries that need
    /// a per-port context to open (Negotiation Diagnostics). Nil when nothing
    /// is connected.
    public static func firstPortContext() -> PortCardContext? {
        WatcherHub.shared.portWatcher.ports.first { $0.portKey != nil }.map(context(for:))
    }
}

/// Retained target for plugin menu items. AppKit menu items need an `@objc`
/// action with a strong target, so the static `shared` instance keeps the
/// action map alive for the whole process.
@MainActor
final class ProMenuItems: NSObject {
    static let shared = ProMenuItems()
    private var actions: [String: () -> Void] = [:]

    func makeItem(id: String, title: String, action: @escaping () -> Void) -> NSMenuItem {
        actions[id] = action
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = self
        item.identifier = NSUserInterfaceItemIdentifier("pro.\(id)")
        return item
    }

    @objc private func fire(_ sender: NSMenuItem) {
        guard let id = sender.identifier?.rawValue else { return }
        actions[id]?()
    }
}
