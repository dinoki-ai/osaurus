import SwiftUI
import AppKit

struct MenuBarControllerView: SwiftUI.View {
    @ObservedObject var server: ServerController
    @State private var portString: String = "8080"
    @State private var showError: Bool = false

    var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
            HStack(spacing: 8) {
                statusIndicator
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    if server.isRunning {
                        Text("Port \(server.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider()

            // Port Configuration
            HStack(spacing: 8) {
                Text("Port:")
                    .foregroundColor(.secondary)
                TextField("Port", text: $portString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .disabled(server.isRunning)
                    .onAppear {
                        portString = String(server.port)
                    }
                    .onSubmit {
                        if !server.isRunning {
                            startServer()
                        }
                    }
            }

            // Action Buttons
            VStack(spacing: 8) {
                Button(action: toggleServer) {
                    HStack {
                        Image(systemName: server.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(server.isRunning ? "Stop Server" : "Start Server")
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isTransitioning)
                
                if server.isRunning {
                    Button(action: openInBrowser) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open in Browser")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Divider()
            
            // Additional Actions
            HStack(spacing: 8) {
                Button("Show Window") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            // Error Message
            if let error = server.lastErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
        .alert("Server Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(server.lastErrorMessage ?? "Please enter a port between 1 and 65535.")
        }
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 3)
                    .scaleEffect(isTransitioning ? 1.8 : 1.0)
                    .opacity(isTransitioning ? 0 : 1)
                    .animation(
                        isTransitioning ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                        value: isTransitioning
                    )
            )
    }
    
    private var statusTitle: String {
        switch server.serverHealth {
        case .stopped: return "Server Stopped"
        case .starting: return "Starting Server..."
        case .running: return "Server Running"
        case .stopping: return "Stopping Server..."
        case .error: return "Server Error"
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
    
    private var isTransitioning: Bool {
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
            startServer()
        }
    }
    
    private func startServer() {
        guard let port = Int(portString), (1..<65536).contains(port) else {
            server.lastErrorMessage = "Please enter a valid port between 1 and 65535"
            showError = true
            return
        }
        
        server.port = port
        server.lastErrorMessage = nil  // Clear previous errors
        
        Task { @MainActor in
            await server.startServer()
            if server.lastErrorMessage != nil {
                showError = true
            }
        }
    }
    
    private func openInBrowser() {
        let url = URL(string: "http://127.0.0.1:\(server.port)")!
        NSWorkspace.shared.open(url)
    }
}


