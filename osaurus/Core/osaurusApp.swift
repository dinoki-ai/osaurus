//
//  osaurusApp.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI

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
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))

        SwiftUI.MenuBarExtra("Osaurus", systemImage: "bird") {
            MenuBarControllerView(server: serverController)
                .onAppear {
                    // Ensure app delegate has reference
                    appDelegate.serverController = serverController
                }
        }
    }
}
