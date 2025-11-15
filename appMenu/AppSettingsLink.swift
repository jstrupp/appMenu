//
//  AppSettingsLink.swift
//  appMenu
//
//  Created by Jeffrey Strupp on 10/17/25.
//

import SwiftUI
import AppKit

/// A compatibility wrapper that uses SwiftUI's `SettingsLink` on macOS 14+,
/// and falls back to the legacy AppKit selector on earlier macOS versions.
public struct AppSettingsLink<Label: View>: View {
    private let label: () -> Label

    public init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    public var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    label()
                }
            } else {
                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        if !NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
                            NSSound.beep()
                        }
                    }
                }) {
                    label()
                }
            }
        }
    }
}
