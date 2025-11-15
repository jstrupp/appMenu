//
//  ContentView.swift
//  appMenu
//
//  Created by Jeffrey Strupp on 10/16/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("App Menu")
                .font(.title2)
            
            Text("Right-click the Dock icon or use the menu bar item to launch apps.\nUse Settings to customize folders and apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                // If you have your own wrapper, keep it; otherwise SettingsLink works on macOS 14+
                AppSettingsLink {
                    Text("Open Settings")
                }
                Button("Refresh Menus") {
                    store.refreshMenusRequested()
                }
                Button("Help") {
                    HelpManager.openHelp()
                }
            }
        }
        .padding()
        // Install the SwiftUI openSettings action so AppKit (Dock menu) can trigger it.
        .background(OpenSettingsInstaller())
    }
}

#Preview {
    ContentView().environmentObject(AppStore(inMemory: true))
}

// Captures the SwiftUI openSettings environment action and registers it
// so AppKit code can invoke it without using AppKit selectors.
private struct OpenSettingsInstaller: View {
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Color.clear
            .onAppear {
                if #available(macOS 14.0, *) {
                    OpenSettingsCoordinator.shared.install {
                        openSettings()
                    }
                } else {
                    // On older systems, no SettingsLink/openSettings; leave uninstalled.
                    OpenSettingsCoordinator.shared.install(nil)
                }
            }
    }
}
