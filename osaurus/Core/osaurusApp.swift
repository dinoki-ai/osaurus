//
//  osaurusApp.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI
import AppKit

@main
struct osaurusApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverController = ServerController()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverController)
                .onAppear {
                    // Pass server controller to app delegate
                    appDelegate.serverController = serverController
                    // Capture the main window and register with app delegate for show/hide behavior
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first {
                            appDelegate.setMainWindow(window)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
