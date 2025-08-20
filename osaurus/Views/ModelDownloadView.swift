//
//  ModelDownloadView.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import SwiftUI

struct ModelDownloadView: View {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.theme) private var theme
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: MLXModel?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Themed background
            theme.primaryBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Model list
                modelListView
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .environment(\.theme, themeManager.currentTheme)
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
            // Logo with minimalistic outline
            ZStack {
                Circle()
                    .fill(theme.cardBackground)
                    .overlay(
                        Circle()
                            .stroke(theme.accentColor, lineWidth: 2)
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "cube.box")
                    .font(.system(size: 26))
                    .foregroundColor(theme.accentColor)
            }
            .shadow(color: theme.shadowColor.opacity(theme.shadowOpacity), radius: 6, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Manager")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(theme.primaryText)
                
                Text("Download and manage Large Language Models for MLX")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.secondaryText)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Downloaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Text(modelManager.totalDownloadedSizeString)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.accentColor)
            }
            .padding(.trailing, 12)
            
            GradientButton(
                title: "Done",
                icon: "checkmark",
                action: { dismiss() },
                isPrimary: false
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            theme.secondaryBackground
                .overlay(
                    Rectangle()
                        .fill(theme.primaryBorder)
                        .frame(height: 1),
                    alignment: .bottom
                )
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
    @Environment(\.theme) private var theme
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
                            .foregroundColor(theme.primaryText)
                        
                        Text(model.description)
                            .font(.system(size: 13))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(2)
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 11))
                                Text(model.sizeString)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(theme.tertiaryText)
                            
                            if model.isDownloaded {
                                                StatusBadge(
                    status: "Downloaded",
                    color: theme.successColor,
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
                            .foregroundColor(theme.secondaryText)
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
            GradientButton(
                title: "Cancel",
                icon: "xmark.circle",
                action: onCancel,
                isDestructive: true,
                isPrimary: false
            )
            
        case .completed:
            GradientButton(
                title: "Delete",
                icon: "trash",
                action: onDelete,
                isDestructive: true,
                isPrimary: false
            )
            
        case .failed(let error):
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(
                    status: "Failed",
                    color: theme.errorColor,
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
