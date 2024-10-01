//
//  CodeFusionApp.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-09-30.
//

import SwiftUI

@main
struct CodeFusionApp: App {
    @StateObject private var exclusionManager: ExclusionManager
    @StateObject private var fileManagerViewModel: FileManagerViewModel

    init() {
        let exclusionManager = ExclusionManager()
        _exclusionManager = StateObject(wrappedValue: exclusionManager)
        _fileManagerViewModel = StateObject(wrappedValue: FileManagerViewModel(exclusionManager: exclusionManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(exclusionManager)
                .environmentObject(fileManagerViewModel)
        }
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button(action: toggleSidebar) {
                    Text("Toggle Sidebar")
                }
                .keyboardShortcut("S", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(exclusionManager)
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

