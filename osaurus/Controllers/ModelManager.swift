//
//  ModelManager.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation
import SwiftUI
import Combine

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
    static let modelsDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                     in: .userDomainMask).first!
        let modelsPath = documentsPath.appendingPathComponent("MLXModels")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsPath, 
                                                 withIntermediateDirectories: true)
        return modelsPath
    }()
    
    private var urlSession: URLSession!
    private nonisolated(unsafe) var downloadTaskInfos: [URLSessionTask: DownloadTaskInfo] = [:]
    private var modelDownloadProgress: [String: [String: Double]] = [:] // modelId -> [fileName: progress]
    private var activeDownloads: [String: Set<URLSessionDownloadTask>] = [:] // modelId -> tasks
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = false
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
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
    
    /// Download a model
    func downloadModel(_ model: MLXModel) {
        guard downloadStates[model.id] == .notStarted || 
              downloadStates[model.id] == nil else { return }
        
        downloadStates[model.id] = .downloading(progress: 0.0)
        
        // Create model directory
        do {
            try FileManager.default.createDirectory(at: model.localDirectory, 
                                                   withIntermediateDirectories: true)
        } catch {
            downloadStates[model.id] = .failed(error: "Failed to create directory: \(error.localizedDescription)")
            return
        }
        
        // Initialize progress tracking
        modelDownloadProgress[model.id] = [:]
        activeDownloads[model.id] = []
        
        // Download each required file
        for (index, fileName) in model.requiredFiles.enumerated() {
            downloadFile(fileName: fileName, 
                        for: model, 
                        fileIndex: index,
                        totalFiles: model.requiredFiles.count)
        }
    }
    
    /// Cancel a download
    func cancelDownload(_ modelId: String) {
        // Cancel all active download tasks for this model
        if let tasks = activeDownloads[modelId] {
            for task in tasks {
                task.cancel()
                downloadTaskInfos.removeValue(forKey: task)
            }
        }
        
        // Clean up tracking
        activeDownloads.removeValue(forKey: modelId)
        modelDownloadProgress.removeValue(forKey: modelId)
        downloadStates[modelId] = .notStarted
    }
    
    /// Delete a downloaded model
    func deleteModel(_ model: MLXModel) {
        do {
            try FileManager.default.removeItem(at: model.localDirectory)
            downloadStates[model.id] = .notStarted
        } catch {
            print("Failed to delete model: \(error)")
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
    
    private func downloadFile(fileName: String, for model: MLXModel, fileIndex: Int, totalFiles: Int) {
        // Construct HuggingFace URL
        let urlString = "https://huggingface.co/\(model.id)/resolve/main/\(fileName)"
        guard let url = URL(string: urlString) else {
            downloadStates[model.id] = .failed(error: "Invalid URL for file: \(fileName)")
            return
        }
        
        let request = URLRequest(url: url)
        let downloadTask = urlSession.downloadTask(with: request)
        
        // Store task info
        let taskInfo = DownloadTaskInfo(modelId: model.id,
                                        fileName: fileName,
                                        fileIndex: fileIndex,
                                        totalFiles: totalFiles)
        downloadTaskInfos[downloadTask] = taskInfo
        
        // Track active downloads
        if activeDownloads[model.id] == nil {
            activeDownloads[model.id] = []
        }
        activeDownloads[model.id]?.insert(downloadTask)
        
        // Initialize progress for this file
        modelDownloadProgress[model.id]?[fileName] = 0.0
        
        downloadTask.resume()
    }
    
    private func updateOverallProgress(for modelId: String) {
        guard let fileProgress = modelDownloadProgress[modelId],
              !fileProgress.isEmpty else { return }
        
        // Calculate average progress across all files
        let totalProgress = fileProgress.values.reduce(0, +) / Double(fileProgress.count)
        downloadStates[modelId] = .downloading(progress: totalProgress)
    }
    
    nonisolated private func getModelId(for task: URLSessionTask) -> String? {
        return downloadTaskInfos[task]?.modelId
    }
}

// MARK: - URLSessionDownloadDelegate
extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, 
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let taskInfo = downloadTaskInfos[downloadTask],
              let modelId = getModelId(for: downloadTask) else { return }
        
        Task { @MainActor in
            guard let model = availableModels.first(where: { $0.id == modelId }) else { return }
            
            let destinationURL = model.localDirectory.appendingPathComponent(taskInfo.fileName)
            
            do {
                // Remove existing file if present
                try? FileManager.default.removeItem(at: destinationURL)
                
                // Move downloaded file to destination
                try FileManager.default.moveItem(at: location, to: destinationURL)
                
                // Update progress for this file
                modelDownloadProgress[model.id]?[taskInfo.fileName] = 1.0
                
                // Remove from active downloads
                activeDownloads[model.id]?.remove(downloadTask)
                downloadTaskInfos.removeValue(forKey: downloadTask)
                
                // Check if all files are downloaded
                if activeDownloads[model.id]?.isEmpty ?? true {
                    // Verify all files exist
                    if model.isDownloaded {
                        downloadStates[model.id] = .completed
                    } else {
                        downloadStates[model.id] = .failed(error: "Some files failed to download")
                    }
                    
                    // Clean up
                    activeDownloads.removeValue(forKey: model.id)
                    modelDownloadProgress.removeValue(forKey: model.id)
                } else {
                    updateOverallProgress(for: model.id)
                }
            } catch {
                downloadStates[model.id] = .failed(error: "Failed to save file: \(error.localizedDescription)")
                cancelDownload(model.id)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0,
              let taskInfo = downloadTaskInfos[downloadTask],
              let modelId = getModelId(for: downloadTask) else { return }
        
        let fileProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { @MainActor in
            modelDownloadProgress[modelId]?[taskInfo.fileName] = fileProgress
            updateOverallProgress(for: modelId)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error = error,
              let modelId = getModelId(for: task) else { return }
        
        Task { @MainActor in
            // Handle cancellation
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            
            // Handle other errors
            downloadStates[modelId] = .failed(error: error.localizedDescription)
            cancelDownload(modelId)
        }
    }
}
