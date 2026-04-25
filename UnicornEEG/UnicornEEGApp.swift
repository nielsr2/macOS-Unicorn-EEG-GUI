/*
 * UnicornEEGApp.swift
 * UnicornEEG
 *
 * Main entry point for the Unicorn EEG macOS GUI application.
 */

import SwiftUI

// Global reference for signal handler cleanup
private var globalEngine: StreamEngine?

@main
struct UnicornEEGApp: App {
    @StateObject private var engine = StreamEngine()

    init() {
        // Register SIGTERM handler so Xcode rebuilds get a clean shutdown.
        // Xcode sends SIGTERM before SIGKILL — this gives us time to stop
        // acquisition and close the port so the device isn't left streaming.
        signal(SIGTERM) { _ in
            globalEngine?.shutdown()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear {
                    globalEngine = engine
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    engine.shutdown()
                }
        }
        .defaultSize(width: 1000, height: 700)
    }
}
