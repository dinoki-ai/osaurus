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
    var serverController: ServerController? {
        didSet {
            setupObservers()
            updateStatusItemAndMenu()
        }
    }
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure app to stay in dock
        NSApp.setActivationPolicy(.regular)
        
        // App has launched
        print("Osaurus server app launched")

        // Create status bar item and attach menu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Osaurus") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Osaurus"
            }
            button.toolTip = "Osaurus Server"
        }
        statusItem = item
        updateStatusItemAndMenu()
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
    
    // MARK: - Status Item / Menu
    
    private func setupObservers() {
        cancellables.removeAll()
        guard let serverController else { return }
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
        statusItem.menu = buildMenu()
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let statusTitle: String
        if let server = serverController {
            switch server.serverHealth {
            case .stopped:
                statusTitle = "Server Stopped"
            case .starting:
                statusTitle = "Starting Server…"
            case .running:
                statusTitle = "Server Running (Port \(server.port))"
            case .stopping:
                statusTitle = "Stopping Server…"
            case .error(let message):
                statusTitle = "Server Error: \(message)"
            }
        } else {
            statusTitle = "Osaurus"
        }
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())
        
        // Start/Stop toggle
        if let server = serverController {
            let isBusy: Bool
            switch server.serverHealth {
            case .starting, .stopping: isBusy = true
            default: isBusy = false
            }
            let toggleTitle = server.isRunning ? "Stop Server" : "Start Server"
            let toggleAction: Selector = server.isRunning ? #selector(stopServerAction(_:)) : #selector(startServerAction(_:))
            let toggleItem = NSMenuItem(title: toggleTitle, action: toggleAction, keyEquivalent: "")
            toggleItem.target = self
            toggleItem.isEnabled = !isBusy
            menu.addItem(toggleItem)
            
            // Open in Browser
            let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowserAction(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.isEnabled = server.isRunning
            menu.addItem(openItem)
            
            // Set Port… (disabled while running)
            let setPortItem = NSMenuItem(title: "Set Port…", action: #selector(setPortAction(_:)), keyEquivalent: "")
            setPortItem.target = self
            setPortItem.isEnabled = !server.isRunning && !isBusy
            menu.addItem(setPortItem)
        } else {
            // No server available yet
            let disabledItem = NSMenuItem(title: "Server not ready", action: nil, keyEquivalent: "")
            disabledItem.isEnabled = false
            menu.addItem(disabledItem)
        }
        
        menu.addItem(.separator())
        
        // Show Window
        let showWindowItem = NSMenuItem(title: "Show Window", action: #selector(showWindowAction(_:)), keyEquivalent: "")
        showWindowItem.target = self
        menu.addItem(showWindowItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc private func startServerAction(_ sender: Any?) {
        guard let serverController else { return }
        Task { @MainActor in
            await serverController.startServer()
        }
    }
    
    @objc private func stopServerAction(_ sender: Any?) {
        guard let serverController else { return }
        Task { @MainActor in
            await serverController.stopServer()
        }
    }
    
    @objc private func openInBrowserAction(_ sender: Any?) {
        guard let serverController, serverController.isRunning else { return }
        let url = URL(string: "http://127.0.0.1:\(serverController.port)")!
        NSWorkspace.shared.open(url)
    }
    
    @objc private func showWindowAction(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }
    
    @objc private func setPortAction(_ sender: Any?) {
        guard let serverController else { return }
        let alert = NSAlert()
        alert.messageText = "Set Server Port"
        alert.informativeText = "Enter a port between 1 and 65535."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(string: String(serverController.port))
        textField.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let value = Int(textField.stringValue) ?? 0
            if (1..<65536).contains(value) {
                serverController.port = value
            } else {
                NSSound.beep()
            }
        }
    }
}
