//
//  ContentView.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var server: ServerController
    @StateObject private var whisperController = WhisperController()
    @State private var portString: String = "8080"
    @State private var showError: Bool = false
    @State private var isHealthy: Bool = false
    @State private var lastHealthCheck: Date?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    serverStatusCard
                    serverControlsCard
                    serverInfoCard
                    whisperTestCard
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            portString = String(server.port)
            startHealthCheck()
        }
        .alert("Server Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(server.lastErrorMessage ?? "An error occurred while managing the server.")
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "bird")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Osaurus Server")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusIndicator
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var serverStatusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Server Status", systemImage: "server.rack")
                    .font(.headline)
                
                HStack {
                    Text("Status:")
                        .foregroundColor(.secondary)
                    Text(statusDescription)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                if server.isRunning {
                    HStack {
                        Text("Health:")
                            .foregroundColor(.secondary)
                        Text(isHealthy ? "Healthy" : "Checking...")
                            .fontWeight(.medium)
                            .foregroundColor(isHealthy ? .green : .orange)
                    }
                    
                    if let lastCheck = lastHealthCheck {
                        HStack {
                            Text("Last Check:")
                                .foregroundColor(.secondary)
                            Text(lastCheck, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let error = server.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var serverControlsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Server Controls", systemImage: "gearshape")
                    .font(.headline)
                
                HStack {
                    Text("Port:")
                        .frame(width: 50, alignment: .trailing)
                    
                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(server.isRunning)
                    
                    Text("(1-65535)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    Button(action: toggleServer) {
                        Label(
                            server.isRunning ? "Stop Server" : "Start Server",
                            systemImage: server.isRunning ? "stop.circle" : "play.circle"
                        )
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    
                    if server.isRunning {
                        Button(action: openInBrowser) {
                            Label("Open in Browser", systemImage: "safari")
                        }
                        .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var serverInfoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Server Information", systemImage: "info.circle")
                    .font(.headline)
                
                if server.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("URL:", value: "http://127.0.0.1:\(server.port)")
                        infoRow("Health Check:", value: "http://127.0.0.1:\(server.port)/health")
                        infoRow("Echo Endpoint:", value: "POST http://127.0.0.1:\(server.port)/echo")
                    }
                } else {
                    Text("Server is not running")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var whisperTestCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Whisper Speech Recognition Test", systemImage: "mic.circle")
                    .font(.headline)
                
                // Recording controls
                HStack(spacing: 12) {
                    Button(action: {
                        if whisperController.isRecording {
                            Task {
                                await whisperController.stopRecording()
                            }
                        } else {
                            whisperController.startRecording()
                        }
                    }) {
                        Label(
                            whisperController.isRecording ? "Stop Recording" : "Start Recording",
                            systemImage: whisperController.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                        )
                        .foregroundColor(whisperController.isRecording ? .red : .accentColor)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(whisperController.isProcessing)
                    
                    if whisperController.isRecording {
                        Text(String(format: "Recording: %.1fs", whisperController.recordingTime))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        whisperController.clearTranscription()
                    }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(whisperController.transcribedText.isEmpty)
                }
                
                // Status
                if whisperController.isProcessing {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing audio...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Error message
                if let error = whisperController.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                        .lineLimit(2)
                }
                
                // Transcription result
                if !whisperController.transcribedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcription:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView {
                            Text(whisperController.transcribedText)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        }
                        .frame(maxHeight: 100)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.system(.body, design: .monospaced))
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 4)
                    .scaleEffect(server.isRunning ? 1.5 : 1.0)
                    .opacity(server.isRunning ? 0 : 1)
                    .animation(
                        server.isRunning ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default,
                        value: server.isRunning
                    )
            )
    }
    
    private var statusText: String {
        switch server.serverHealth {
        case .stopped:
            return "Server is stopped"
        case .starting:
            return "Server is starting..."
        case .running:
            return "Server is running on port \(server.port)"
        case .stopping:
            return "Server is stopping..."
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
    
    private func openInBrowser() {
        let url = URL(string: "http://127.0.0.1:\(server.port)")!
        NSWorkspace.shared.open(url)
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

#Preview {
    ContentView()
        .environmentObject(ServerController())
}
