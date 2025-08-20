//
//  AppDelegate.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI
import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let serverController = ServerController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as menu bar app (hide Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // App has launched
        print("Osaurus server app launched")

        // Set up observers for server state changes
        setupObservers()

        // Create status bar item and attach click handler
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Osaurus") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Osaurus"
            }
            button.toolTip = "Osaurus Server"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
        updateStatusItemAndMenu()
    }


    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard serverController.isRunning else {
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
    
    // MARK: - Status Item / Menu
    
    private func setupObservers() {
        cancellables.removeAll()
        serverController.$serverHealth
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
        serverController.$isRunning
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
        serverController.$configuration
            .sink { [weak self] _ in
                self?.updateStatusItemAndMenu()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusItemAndMenu() {
        guard let statusItem else { return }
        // Ensure no NSMenu is attached so button action is triggered
        statusItem.menu = nil
        if let button = statusItem.button {
            switch serverController.serverHealth {
                case .stopped:
                    button.toolTip = "Osaurus — Ready to start"
                case .starting:
                    button.toolTip = "Osaurus — Starting…"
                case .running:
                    button.toolTip = "Osaurus — Running on port \(serverController.port)"
                case .stopping:
                    button.toolTip = "Osaurus — Stopping…"
                case .error(let message):
                    button.toolTip = "Osaurus — Error: \(message)"
                }
        }
    }

    
    // MARK: - Actions

    @objc private func togglePopover(_ sender: Any?) {
        guard let statusButton = statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let contentView = ContentView(isPopover: true, onClose: { [weak self] in
            self?.popover?.performClose(nil)
        })
            .environmentObject(serverController)

        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover

        popover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
    

}
