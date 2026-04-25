/*
 * UnicornEEGApp.swift
 * UnicornEEG
 *
 * Main entry point for the Unicorn EEG macOS GUI application.
 */

import SwiftUI

@main
struct UnicornEEGApp: App {
    @StateObject private var engine = StreamEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    engine.shutdown()
                }
        }
        .defaultSize(width: 1000, height: 700)
    }
}
