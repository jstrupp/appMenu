// AppLauncher.swift
import AppKit

final class AppLauncher {
    func launch(_ app: AppItem) {
        NSWorkspace.shared.openApplication(at: app.url,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}
