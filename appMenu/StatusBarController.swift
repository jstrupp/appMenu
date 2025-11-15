// StatusBarController.swift
import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var store: AppStore?
    private let handler: MenuActionHandler
    private var menu: NSMenu?
    
    init(store: AppStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.handler = MenuActionHandler(store: store)
        super.init()
        
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "App Menu")
            } else {
                button.title = "Apps"
            }
            // When statusItem.menu is set, AppKit shows it automatically on click.
            // No target/action needed.
        }
        rebuildMenu()
    }
    
    func rebuildMenu() {
        guard let store else { return }
        let built = DockMenuBuilder.buildMenu(from: store.items,
                                              store: store,
                                              handler: handler,
                                              includeRootSectionHeaders: false,
                                              includeUtilities: true)
        // Keep a strong reference and also assign to statusItem.menu.
        self.menu = built
        self.statusItem.menu = built
    }
}
