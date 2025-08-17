//
//  AppDelegate.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var serverController: ServerController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure app to stay in dock
        NSApp.setActivationPolicy(.regular)
        
        // App has launched
        print("Osaurus server app launched")
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let serverController = serverController, serverController.isRunning else {
            return .terminateNow
        }
        
        // Delay termination to allow async shutdown
        Task { @MainActor in
            await serverController.ensureShutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        
        return .terminateLater
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("Osaurus server app terminating")
    }
}
