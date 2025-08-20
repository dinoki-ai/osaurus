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
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Model list
                modelListView
            }
        }
        .frame(minWidth: 700, minHeight: 600)
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
            // Logo with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Manager")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Download and manage Large Language Models for MLX")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Downloaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text(modelManager.totalDownloadedSizeString)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.trailing, 12)
            
            GradientButton(
                title: "Done",
                icon: "checkmark",
                action: { dismiss() }
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            GlassBackground(cornerRadius: 0, opacity: 0.05)
        )
    }
    
    private var modelListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .padding(24)
        }
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
        SimpleCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    // Model icon with gradient
                    IconBadge(
                        icon: "text.bubble.fill",
                        color: model.isDownloaded ? .green : .blue,
                        size: 50
                    )
                    
                    // Model info
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text(model.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 11))
                                Text(model.sizeString)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            
                            if model.isDownloaded {
                                StatusBadge(
                                    status: "Downloaded",
                                    color: .green,
                                    isAnimating: false
                                )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    actionButton
                }
                .padding(20)
                
                // Progress bar
                if case .downloading(let progress) = downloadState {
                    VStack(spacing: 8) {
                        SimpleProgressBar(progress: progress)
                            .padding(.horizontal, 20)
                        
                        Text("\(Int(progress * 100))% downloaded")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch downloadState {
        case .notStarted:
            GradientButton(
                title: "Download",
                icon: "arrow.down.circle.fill",
                action: onDownload
            )
            
        case .downloading:
            Button(action: onCancel) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
        case .completed:
            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                    Text("Delete")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
        case .failed(let error):
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(
                    status: "Failed",
                    color: .red,
                    isAnimating: false
                )
                
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    ModelDownloadView()
}
