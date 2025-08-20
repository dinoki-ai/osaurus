//
//  ModelManager.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation
import SwiftUI
import Combine
import Hub

/// Download task information
struct DownloadTaskInfo {
    let modelId: String
    let fileName: String
    let fileIndex: Int
    let totalFiles: Int
}

/// Manages MLX model downloads and storage
@MainActor
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()
    
    // MARK: - Published Properties
    @Published var availableModels: [MLXModel] = []
    @Published var downloadStates: [String: DownloadState] = [:]
    
    // MARK: - Properties
    nonisolated(unsafe) static var modelsDirectory: URL = {
        // Allow override (useful for tests) via environment variable
        if let overridePath = ProcessInfo.processInfo.environment["OSU_MODELS_DIR"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            return overrideURL
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let modelsPath = documentsPath.appendingPathComponent("MLXModels")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsPath,
                                                 withIntermediateDirectories: true)
        return modelsPath
    }()
    
    private var activeDownloadTasks: [String: Task<Void, Never>] = [:] // modelId -> Task
    private var downloadTokens: [String: UUID] = [:] // modelId -> token to gate progress/state updates
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        loadAvailableModels()
    }
    
    // MARK: - Public Methods
    
    /// Load popular MLX models
    func loadAvailableModels() {
        // Popular MLX-compatible LLM models
        availableModels = [
            MLXModel(
                id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                name: "Llama 3.2 3B Instruct",
                description: "Meta's latest efficient 3B parameter model with strong reasoning",
                size: 1_932_735_283, // ~1.8GB
                downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                name: "Llama 3.2 1B Instruct",
                description: "Meta's ultra-compact 1B model for edge deployment",
                size: 805_306_368, // ~768MB
                downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
                name: "DeepSeek-R1 Distill 1.5B",
                description: "DeepSeek's reasoning model distilled to 1.5B parameters",
                size: 1_073_741_824, // ~1GB
                downloadURL: "https://huggingface.co/mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/gemma-2-9b-it-4bit",
                name: "Gemma 2 9B Instruct",
                description: "Google's powerful 9B instruction-tuned model",
                size: 5_905_580_032, // ~5.5GB
                downloadURL: "https://huggingface.co/mlx-community/gemma-2-9b-it-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/gemma-2-2b-it-4bit",
                name: "Gemma 2 2B Instruct",
                description: "Google's efficient 2B model with strong capabilities",
                size: 1_503_238_553, // ~1.4GB
                downloadURL: "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                name: "Qwen 2.5 7B Instruct",
                description: "Alibaba's latest 7B multilingual model with 128K context",
                size: 4_831_838_208, // ~4.5GB
                downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                name: "Qwen 2.5 3B Instruct",
                description: "Alibaba's compact 3B model with strong performance",
                size: 2_040_109_465, // ~1.9GB
                downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            ),
            MLXModel(
                id: "mlx-community/OpenELM-3B-Instruct-4bit",
                name: "OpenELM 3B (GPT-style)",
                description: "Apple's efficient open-source language model",
                size: 1_879_048_192, // ~1.75GB
                downloadURL: "https://huggingface.co/mlx-community/OpenELM-3B-Instruct-4bit",
                requiredFiles: ["model.safetensors", "config.json", "tokenizer_config.json", "tokenizer.json", "special_tokens_map.json"]
            )
        ]
        
        // Initialize download states
        for model in availableModels {
            if model.isDownloaded {
                downloadStates[model.id] = .completed
            } else {
                downloadStates[model.id] = .notStarted
            }
        }
    }
    
    /// Download a model using Hugging Face Hub snapshot API
    func downloadModel(_ model: MLXModel) {
        let state = downloadStates[model.id] ?? .notStarted
        switch state {
        case .downloading, .completed:
            return
        default:
            break
        }
        
        // Reset any previous task
        activeDownloadTasks[model.id]?.cancel()
        // Create a new token for this download session
        let token = UUID()
        downloadTokens[model.id] = token
        
        downloadStates[model.id] = .downloading(progress: 0.0)
        
        // Ensure local directory exists
        do {
            try FileManager.default.createDirectory(
                at: model.localDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            downloadStates[model.id] = .failed(error: "Failed to create directory: \(error.localizedDescription)")
            return
        }
        
        // Start snapshot download task
        let task = Task { [weak self] in
            guard let self = self else { return }
            let repo = Hub.Repo(id: model.id)
            
            do {
                // Prefer grabbing common necessary files, but allow weights via wildcard
                let patterns = [
                    "config.json",
                    "tokenizer.json",
                    "tokenizer_config.json",
                    "special_tokens_map.json",
                    "generation_config.json",
                    "*.safetensors"
                ]
                
                // Download a snapshot to a temporary location managed by Hub
                let snapshotDirectory = try await Hub.snapshot(
                    from: repo,
                    matching: patterns,
                    progressHandler: { progress in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            // Ignore progress updates from stale/canceled tasks
                            guard self.downloadTokens[model.id] == token else { return }
                            // Clamp to [0, 1]
                            let fraction = max(0.0, min(1.0, progress.fractionCompleted))
                            self.downloadStates[model.id] = .downloading(progress: fraction)
                        }
                    }
                )
                
                // Copy snapshot contents into our managed models directory
                try self.copyContents(of: snapshotDirectory, to: model.localDirectory)
                
                // Attempt to remove the Hub snapshot cache directory to free disk space
                // This directory is a cached snapshot; we've already copied the contents
                // into our app-managed models directory above, so it's safe to delete.
                do {
                    try FileManager.default.removeItem(at: snapshotDirectory)
                } catch {
                    // Non-fatal cleanup failure
                    print("Warning: failed to remove Hub snapshot cache at \(snapshotDirectory.path): \(error)")
                }
                
                // Verify
                let completed = model.isDownloaded
                await MainActor.run {
                    // Only update state if this session is still current
                    if self.downloadTokens[model.id] == token {
                        self.downloadStates[model.id] = completed ? .completed : .failed(error: "Downloaded snapshot incomplete")
                        self.downloadTokens[model.id] = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self.downloadTokens[model.id] == token {
                        self.downloadStates[model.id] = .notStarted
                        self.downloadTokens[model.id] = nil
                    }
                }
            } catch {
                await MainActor.run {
                    if self.downloadTokens[model.id] == token {
                        self.downloadStates[model.id] = .failed(error: error.localizedDescription)
                        self.downloadTokens[model.id] = nil
                    }
                }
            }
            
            await MainActor.run {
                self.activeDownloadTasks[model.id] = nil
            }
        }
        
        activeDownloadTasks[model.id] = task
    }
    
    /// Cancel a download
    func cancelDownload(_ modelId: String) {
        // Cancel active snapshot task if any
        activeDownloadTasks[modelId]?.cancel()
        activeDownloadTasks[modelId] = nil
        downloadTokens[modelId] = nil
        downloadStates[modelId] = .notStarted
    }
    
    /// Delete a downloaded model
    func deleteModel(_ model: MLXModel) {
        // Cancel any active download task and reset state first
        activeDownloadTasks[model.id]?.cancel()
        activeDownloadTasks[model.id] = nil
        downloadTokens[model.id] = nil
        downloadStates[model.id] = .notStarted

        // Remove local files if present
        let fm = FileManager.default
        let path = model.localDirectory.path
        if fm.fileExists(atPath: path) {
            do {
                try fm.removeItem(atPath: path)
            } catch {
                // Log but keep state reset
                print("Failed to delete model: \(error)")
            }
        }
    }
    
    /// Get download progress for a model
    func downloadProgress(for modelId: String) -> Double {
        switch downloadStates[modelId] {
        case .downloading(let progress):
            return progress
        case .completed:
            return 1.0
        default:
            return 0.0
        }
    }
    
    /// Get total size of downloaded models
    var totalDownloadedSize: Int64 {
        availableModels
            .filter { $0.isDownloaded }
            .reduce(0) { $0 + $1.size }
    }
    
    var totalDownloadedSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalDownloadedSize, countStyle: .file)
    }
    
    // MARK: - Private Methods
    
    private func copyContents(of sourceDirectory: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure destination exists and is empty
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            // Remove any existing contents
            let existingItems = try fileManager.contentsOfDirectory(atPath: destinationDirectory.path)
            for item in existingItems {
                let url = destinationDirectory.appendingPathComponent(item)
                try fileManager.removeItem(at: url)
            }
        } else {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        
        // Copy all items
        let items = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
        for item in items {
            let src = sourceDirectory.appendingPathComponent(item)
            let dst = destinationDirectory.appendingPathComponent(item)
            // If src is a directory, recursively copy
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: src.path, isDirectory: &isDir)
            if isDir.boolValue {
                try fileManager.createDirectory(at: dst, withIntermediateDirectories: true)
                try copyContents(of: src, to: dst)
            } else {
                try fileManager.copyItem(at: src, to: dst)
            }
        }
    }
}

