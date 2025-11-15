//
//  appMenuApp.swift
//  appMenu
//
//  Created by Jeffrey Strupp on 10/16/25.
//

import SwiftUI

@main
struct appMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store: AppStore

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        // Configure the app delegate early, before any windows are shown.
        appDelegate.configure(with: store)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}
