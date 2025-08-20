//
//  ContentView.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var server: ServerController
    // Popover customization
    var isPopover: Bool = false
    var onClose: (() -> Void)? = nil
    @State private var portString: String = "8080"
    @State private var showError: Bool = false
    @State private var isHealthy: Bool = false
    @State private var lastHealthCheck: Date?
    @State private var selectedModelId: String?
    @State private var showModelManager = false
    @State private var showConfigPopover = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: isPopover ? 12 : 16) {
                // Header
                headerView
                
                // Primary control button reflecting state
                HStack(spacing: 12) {
                    SimpleToggleButton(
                        isOn: server.serverHealth == .running,
                        title: primaryButtonTitle,
                        icon: primaryButtonIcon,
                        action: toggleServer
                    )
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy)
                }
                .padding(.horizontal, 20)
                
                // Server info when running
                if server.isRunning {
                    serverInfoCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
            }
        }
        .frame(
            width: isPopover ? 380 : 420,
            height: isPopover ? (server.isRunning ? 320 : 220) : (server.isRunning ? 380 : 200)
        )
        .onAppear {
            portString = String(server.port)
            startHealthCheck()
        }
        .alert("Server Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(server.lastErrorMessage ?? "An error occurred while managing the server.")
        }
        .sheet(isPresented: $showModelManager) {
            ModelDownloadView()
        }
        .popover(isPresented: $showConfigPopover) {
            configurationPopover
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Osaurus")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Configuration button
            Button(action: { showConfigPopover = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Configuration")

            if isPopover {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isPopover ? 12 : 16)
        .background(
            GlassBackground(cornerRadius: 0, opacity: 0.05)
        )
    }
    
    private var serverInfoCard: some View {
        SimpleCard(padding: 16) {
            VStack(spacing: 16) {
                Text("Your MLX server is ready!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    CopyableURLField(
                        label: "Server URL",
                        url: "http://127.0.0.1:\(server.port)"
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    

    private var configurationPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.system(size: 16, weight: .semibold))
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Port")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("8080", text: $portString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .frame(width: 60)
                        .disabled(server.isRunning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                    
                    Text("(1-65535)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                if server.isRunning {
                    Text("Stop the server to change port")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Models")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Button(action: {
                    showConfigPopover = false
                    showModelManager = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 14))
                        Text("Manage Models…")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 250)
    }
    
    private var statusText: String {
        switch server.serverHealth {
        case .stopped:
            return "Ready to start"
        case .starting:
            return "Starting..."
        case .running:
            return "Running on port \(server.port)"
        case .stopping:
            return "Stopping..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private var statusDescription: String {
        switch server.serverHealth {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .error: return "Error"
        }
    }
    
    private var statusColor: Color {
        switch server.serverHealth {
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
    
    private var isBusy: Bool {
        switch server.serverHealth {
        case .starting, .stopping: return true
        default: return false
        }
    }
    
    private func toggleServer() {
        if server.isRunning {
            Task { @MainActor in
                await server.stopServer()
            }
        } else {
            guard let port = Int(portString), (1..<65536).contains(port) else {
                server.lastErrorMessage = "Please enter a valid port between 1 and 65535"
                showError = true
                return
            }
            
            server.port = port
            Task { @MainActor in
                await server.startServer()
                if server.lastErrorMessage != nil {
                    showError = true
                }
            }
        }
    }
    
    private func startHealthCheck() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if server.isRunning {
                Task { @MainActor in
                    isHealthy = await server.checkServerHealth()
                    lastHealthCheck = Date()
                }
            }
        }
    }
}

private extension ContentView {
    var primaryButtonTitle: String {
        switch server.serverHealth {
        case .stopped: return "Start"
        case .starting: return "Starting…"
        case .running: return "Stop"
        case .stopping: return "Stopping…"
        case .error: return "Retry"
        }
    }
    
    var primaryButtonIcon: String {
        switch server.serverHealth {
        case .stopped: return "play.circle.fill"
        case .starting: return "hourglass"
        case .running: return "stop.circle.fill"
        case .stopping: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerController())
}
