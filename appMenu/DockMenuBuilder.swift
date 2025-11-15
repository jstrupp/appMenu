// DockMenuBuilder.swift
import AppKit
import SwiftUI

final class DockMenuBuilder {
    static func buildMenu(from items: [LaunchItem],
                          store: AppStore,
                          handler: MenuActionHandler,
                          includeRootSectionHeaders: Bool = false,
                          includeUtilities: Bool = true,
                          includeSettings: Bool = true,
                          includeRefresh: Bool = true,
                          includeQuit: Bool = true) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        if includeRootSectionHeaders, !items.isEmpty {
            let header = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }
        
        for item in items {
            append(item, to: menu, handler: handler)
        }
        
        if includeUtilities {
            if menu.items.count > 0 { menu.addItem(.separator()) }
            
            if includeSettings {
                // Plain NSMenuItem that triggers SwiftUI's openSettings via our coordinator
                let settings = NSMenuItem(title: "Open Settings…", action: #selector(MenuActionHandler.openSettings), keyEquivalent: ",")
                settings.target = handler
                settings.isEnabled = true
                menu.addItem(settings)
            }
            
            if includeRefresh {
                let refresh = NSMenuItem(title: "Refresh", action: #selector(MenuActionHandler.refreshMenus), keyEquivalent: "r")
                refresh.target = handler
                refresh.isEnabled = true
                menu.addItem(refresh)
            }
            
            if includeQuit {
                let quit = NSMenuItem(title: "Quit", action: #selector(MenuActionHandler.quitApp), keyEquivalent: "q")
                quit.target = handler
                quit.isEnabled = true
                menu.addItem(quit)
            }
        }
        return menu
    }
    
    private static func append(_ item: LaunchItem, to menu: NSMenu, handler: MenuActionHandler) {
        switch item {
        case .app(let app):
            let mi = NSMenuItem()
            mi.title = app.name
            mi.target = handler
            mi.action = #selector(MenuActionHandler.launchApp(_:))
            mi.representedObject = app
            if let icon = NSWorkspace.shared.icon(forFile: app.url.path).resized(to: NSSize(width: 16, height: 16)) {
                mi.image = icon
            }
            mi.isEnabled = true
            menu.addItem(mi)
        case .folder(let folder):
            let mi = NSMenuItem()
            mi.title = folder.name
            let sub = NSMenu()
            sub.autoenablesItems = false
            for child in folder.children {
                append(child, to: sub, handler: handler)
            }
            mi.submenu = sub
            mi.isEnabled = true
            menu.addItem(mi)
        }
    }
}

final class MenuActionHandler: NSObject {
    weak var store: AppStore?
    private let launcher = AppLauncher()
    
    init(store: AppStore) {
        self.store = store
    }
    
    @objc func launchApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppItem else { return }
        launcher.launch(app)
    }
    
    @objc func openSettings() {
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Prefer SwiftUI's openSettings (installed by ContentView)
        if OpenSettingsCoordinator.shared.open() {
            return
        }
        
        // Fallback: present SettingsView in an AppKit window if openSettings isn't available
        presentSettingsFallbackWindow()
    }
    
    @objc func refreshMenus() {
        store?.refreshMenusRequested()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Fallback Settings window (for older macOS or if installer not yet ran)
    private var fallbackSettingsWindow: NSWindow?
    
    private func presentSettingsFallbackWindow() {
        guard let store else { return }
        if let window = fallbackSettingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView:
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 560, minHeight: 480)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.fallbackSettingsWindow = window
    }
}

// Bridges SwiftUI's openSettings to AppKit callers.
final class OpenSettingsCoordinator {
    static let shared = OpenSettingsCoordinator()
    private var action: (() -> Void)?
    
    func install(_ action: (() -> Void)?) {
        self.action = action
    }
    
    // Returns true if the action was invoked.
    func open() -> Bool {
        guard let action else { return false }
        action()
        return true
    }
}

private extension NSImage {
    func resized(to size: NSSize) -> NSImage? {
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        let rect = NSRect(origin: .zero, size: size)
        self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return img
    }
}

