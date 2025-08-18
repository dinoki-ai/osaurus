//
//  ModelListView.swift
//  osaurus
//
//  View for displaying and managing Whisper models
//

import SwiftUI

struct ModelListView: View {
    @EnvironmentObject var downloadManager: ModelDownloadManager
    @Binding var selectedModelId: String?
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: WhisperModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Whisper Models", systemImage: "square.stack.3d.up")
                    .font(.headline)
                
                Spacer()
                
                Text("\(downloadManager.downloadedModels.count) of \(WhisperModel.availableModels.count) models")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Model List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(WhisperModel.availableModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: selectedModelId == model.id,
                            isDownloaded: downloadManager.isModelDownloaded(model.id),
                            isDownloading: downloadManager.isModelDownloading(model.id),
                            downloadProgress: downloadManager.downloadProgress[model.id],
                            diskSize: downloadManager.getModelSize(for: model),
                            errorMessage: downloadManager.errorMessages[model.id],
                            onSelect: {
                                if downloadManager.isModelDownloaded(model.id) {
                                    selectedModelId = model.id
                                }
                            },
                            onDownload: {
                                downloadManager.downloadModel(model)
                            },
                            onCancelDownload: {
                                downloadManager.cancelDownload(model.id)
                            },
                            onDelete: {
                                modelToDelete = model
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
            
            // Storage Info
            Divider()
            
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.secondary)
                
                Text("Total storage used:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(totalStorageUsed.formattedFileSize)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    downloadManager.deleteModel(model)
                    if selectedModelId == model.id {
                        selectedModelId = nil
                    }
                }
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete the \(model.displayName) model? This will free up \(downloadManager.getModelSize(for: model)?.formattedFileSize ?? "unknown") of disk space.")
            }
        }
    }
    
    private var totalStorageUsed: Int64 {
        WhisperModel.availableModels.reduce(0) { total, model in
            total + (downloadManager.getModelSize(for: model) ?? 0)
        }
    }
}

struct ModelRowView: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let diskSize: Int64?
    let errorMessage: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .opacity(isDownloaded ? 1 : 0.3)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .font(.system(.body, weight: .medium))
                        
                        if isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        // Download size
                        Label(model.downloadSize.formattedFileSize, systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        // Disk usage
                        if let diskSize = diskSize {
                            Label(diskSize.formattedFileSize, systemImage: "internaldrive")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                if isDownloading {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Cancel") {
                            onCancelDownload()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        
                        if let progress = downloadProgress {
                            ProgressView(value: progress)
                                .frame(width: 100)
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if isDownloaded {
                    HStack(spacing: 8) {
                        Button(action: onSelect) {
                            Text("Select")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSelected)
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                } else {
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            // Error message
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    ModelListView(selectedModelId: .constant(nil))
        .frame(width: 600, height: 400)
        .environmentObject(ModelDownloadManager())
}
