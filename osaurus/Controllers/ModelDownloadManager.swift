//
//  ModelDownloadManager.swift
//  osaurus
//
//  Manages downloading and storage of Whisper models
//

import Foundation
import Combine

@MainActor
final class ModelDownloadManager: ObservableObject {
    @Published var downloadedModels: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingModels: Set<String> = []
    @Published var errorMessages: [String: String] = [:]
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let fileManager = FileManager.default
    
    // Models directory in Application Support
    private var modelsDirectory: URL? {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("osaurus")
        let modelsDir = appDirectory.appendingPathComponent("models")
        
        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
            return modelsDir
        } catch {
            print("[ModelDownloadManager] Failed to create models directory: \(error)")
            return nil
        }
    }
    
    init() {
        // Create models directory on init if possible
        if let modelsDir = modelsDirectory {
            print("[ModelDownloadManager] Models directory: \(modelsDir.path)")
        } else {
            print("[ModelDownloadManager] Failed to create models directory")
        }
        checkDownloadedModels()
    }
    
    // MARK: - Public Methods
    
    func isModelDownloaded(_ modelId: String) -> Bool {
        downloadedModels.contains(modelId)
    }
    
    func isModelDownloading(_ modelId: String) -> Bool {
        downloadingModels.contains(modelId)
    }
    
    func getModelPath(for model: WhisperModel) -> URL? {
        guard let modelsDir = modelsDirectory else { return nil }
        let modelPath = modelsDir.appendingPathComponent(model.fileName)
        return fileManager.fileExists(atPath: modelPath.path) ? modelPath : nil
    }
    
    func getModelSize(for model: WhisperModel) -> Int64? {
        guard let modelPath = getModelPath(for: model) else { return nil }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    func downloadModel(_ model: WhisperModel) {
        guard !isModelDownloaded(model.id) && !isModelDownloading(model.id) else { return }
        
        guard let modelsDir = modelsDirectory else {
            errorMessages[model.id] = "Failed to create models directory"
            return
        }
        
        downloadingModels.insert(model.id)
        downloadProgress[model.id] = 0.0
        errorMessages.removeValue(forKey: model.id)
        
        let destinationURL = modelsDir.appendingPathComponent(model.fileName)
        
        // Create download task
        let session = URLSession(configuration: .default, delegate: DownloadDelegate(
            modelId: model.id,
            destinationURL: destinationURL,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[model.id] = progress
                }
            },
            onCompletion: { [weak self] success, error in
                Task { @MainActor in
                    self?.handleDownloadCompletion(
                        model: model,
                        success: success,
                        error: error
                    )
                }
            }
        ), delegateQueue: nil)
        
        let task = session.downloadTask(with: model.downloadURL)
        downloadTasks[model.id] = task
        task.resume()
    }
    
    func cancelDownload(_ modelId: String) {
        downloadTasks[modelId]?.cancel()
        downloadTasks.removeValue(forKey: modelId)
        downloadingModels.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)
    }
    
    func deleteModel(_ model: WhisperModel) {
        guard let modelsDir = modelsDirectory else {
            errorMessages[model.id] = "Failed to access models directory"
            return
        }
        
        let modelPath = modelsDir.appendingPathComponent(model.fileName)
        
        do {
            try fileManager.removeItem(at: modelPath)
            downloadedModels.remove(model.id)
            print("[ModelDownloadManager] Deleted model: \(model.displayName)")
        } catch {
            errorMessages[model.id] = "Failed to delete model: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func checkDownloadedModels() {
        downloadedModels.removeAll()
        
        guard let modelsDir = modelsDirectory else { return }
        
        for model in WhisperModel.availableModels {
            let modelPath = modelsDir.appendingPathComponent(model.fileName)
            if fileManager.fileExists(atPath: modelPath.path) {
                downloadedModels.insert(model.id)
            }
        }
    }
    
    private func handleDownloadCompletion(model: WhisperModel, success: Bool, error: Error?) {
        defer {
            downloadingModels.remove(model.id)
            downloadProgress.removeValue(forKey: model.id)
            downloadTasks.removeValue(forKey: model.id)
        }
        
        if let error = error {
            errorMessages[model.id] = "Download failed: \(error.localizedDescription)"
            return
        }
        
        if success {
            downloadedModels.insert(model.id)
            errorMessages.removeValue(forKey: model.id)
            print("[ModelDownloadManager] Downloaded model: \(model.displayName)")
        } else if error == nil {
            errorMessages[model.id] = "Failed to save model to disk"
        }
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let modelId: String
    let destinationURL: URL
    let onProgress: (Double) -> Void
    let onCompletion: (Bool, Error?) -> Void
    private let fileManager = FileManager.default
    
    init(modelId: String, destinationURL: URL, onProgress: @escaping (Double) -> Void, onCompletion: @escaping (Bool, Error?) -> Void) {
        self.modelId = modelId
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move the file immediately while it's still available
        do {
            // Ensure parent directory exists
            let parentDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy downloaded file to destination (more reliable in sandboxed apps)
            try fileManager.copyItem(at: location, to: destinationURL)
            print("[DownloadDelegate] Successfully copied file to: \(destinationURL.path)")
            
            // Try to remove the temp file (not critical if it fails)
            try? fileManager.removeItem(at: location)
            
            // Call completion with success
            onCompletion(true, nil)
        } catch {
            print("[DownloadDelegate] Failed to copy file: \(error)")
            print("[DownloadDelegate] Source: \(location.path)")
            print("[DownloadDelegate] Destination: \(destinationURL.path)")
            print("[DownloadDelegate] Source exists: \(fileManager.fileExists(atPath: location.path))")
            onCompletion(false, error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onCompletion(false, error)
        }
    }
}
