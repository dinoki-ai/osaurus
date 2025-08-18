//
//  ModelDownloadView.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI

struct ModelDownloadView: View {
    @StateObject private var modelManager = ModelManager.shared
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: MLXModel?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Model list
            modelListView
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    modelManager.deleteModel(model)
                }
            }
        } message: {
            Text("Are you sure you want to delete \(modelToDelete?.name ?? "this model")? This action cannot be undone.")
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "square.and.arrow.down")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("LLM Model Manager")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Download and manage Large Language Models for MLX")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Downloaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(modelManager.totalDownloadedSizeString)
                    .font(.headline)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var modelListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(modelManager.availableModels) { model in
                    ModelRowView(
                        model: model,
                        downloadState: modelManager.downloadStates[model.id] ?? .notStarted,
                        onDownload: { modelManager.downloadModel(model) },
                        onCancel: { modelManager.cancelDownload(model.id) },
                        onDelete: {
                            modelToDelete = model
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ModelRowView: View {
    let model: MLXModel
    let downloadState: DownloadState
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Model icon
                Image(systemName: "text.bubble")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                    .frame(width: 50)
                
                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        Label(model.sizeString, systemImage: "internaldrive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if model.isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                actionButton
            }
            .padding()
            
            // Progress bar
            if case .downloading(let progress) = downloadState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color(NSColor.controlColor) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch downloadState {
        case .notStarted:
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            
        case .downloading:
            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            
        case .completed:
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            
        case .failed(let error):
            VStack(alignment: .trailing) {
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Retry", action: onDownload)
                    .buttonStyle(.link)
            }
        }
    }
}

#Preview {
    ModelDownloadView()
}
