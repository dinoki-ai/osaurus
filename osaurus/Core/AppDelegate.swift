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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var serverController: ServerController? {
        didSet {
            setupObservers()
            updateStatusItemAndMenu()
        }
    }
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private weak var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as menu bar app (hide Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
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

    // MARK: - Window Management

    func setMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
        configureMainWindowAppearance(window)
    }

    private var isMainWindowVisible: Bool {
        guard let window = mainWindow else { return false }
        return window.isVisible
    }
    
    private func configureMainWindowAppearance(_ window: NSWindow) {
        // Hide title bar visuals but keep close button
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbar = nil
        
        // Only allow close; disable resize/minimize/zoom
        window.styleMask.remove(.resizable)
        window.styleMask.remove(.miniaturizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Keep the window always on top
        window.level = .floating
    }

    @objc private func toggleWindowAction(_ sender: Any?) {
        toggleMainWindowVisibility()
    }

    private func toggleMainWindowVisibility() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        } else if let window = NSApp.windows.first {
            // Fallback: if we haven't captured it yet, capture and show
            setMainWindow(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
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
        menu.delegate = self

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

        // Show/Hide Window toggle
        let toggleTitle = isMainWindowVisible ? "Hide Window" : "Show Window"
        let toggleWindowItem = NSMenuItem(title: toggleTitle, action: #selector(toggleWindowAction(_:)), keyEquivalent: "")
        toggleWindowItem.target = self
        toggleWindowItem.tag = 1001
        menu.addItem(toggleWindowItem)
        
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
    
    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of closing
        sender.orderOut(nil)
        updateStatusItemAndMenu()
        return false
    }

    // MARK: - NSMenuDelegate
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let toggleItem = menu.item(withTag: 1001) {
            toggleItem.title = isMainWindowVisible ? "Hide Window" : "Show Window"
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
