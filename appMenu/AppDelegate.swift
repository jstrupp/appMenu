// AppDelegate.swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore?
    private var statusBarController: StatusBarController?
    // Keep a strong reference to the Dock menu action handler.
    private var dockMenuHandler: MenuActionHandler?
    
    func configure(with store: AppStore) {
        self.store = store
        
        // Create and retain the Dock menu handler
        self.dockMenuHandler = MenuActionHandler(store: store)
        
        // Status bar (menu bar extra) with its own retained handler internally
        let status = StatusBarController(store: store)
        self.statusBarController = status
        
        // Refresh status bar menu when model changes
        store.onModelChanged = { [weak status] in
            status?.rebuildMenu()
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide any automatically created SwiftUI windows at startup.
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let store, let handler = dockMenuHandler else { return nil }
        // Build Dock menu with a retained handler so items remain clickable.
        return DockMenuBuilder.buildMenu(from: store.items,
                                         store: store,
                                         handler: handler,
                                         includeRootSectionHeaders: false,
                                         includeUtilities: true,
                                         includeSettings: true,
                                         includeRefresh: false,
                                         includeQuit: false)
    }
}
