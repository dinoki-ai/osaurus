//
//  MLXService.swift
//  osaurus
//
//  Created by Osaurus on 1/29/25.
//

import Foundation
import MLXLMCommon
import MLXLLM

/// Represents a language model configuration
struct LMModel {
    let name: String
    let modelId: String  // The model ID from ModelManager (e.g., "mlx-community/Llama-3.2-3B-Instruct-4bit")
}

/// Message role for chat interactions
enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

/// Chat message structure
struct Message: Codable {
    let role: MessageRole
    let content: String
    
    init(role: MessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// A service class that manages machine learning models for text generation tasks.
/// This class handles model loading, caching, and text generation using various LLM models.
@Observable
@MainActor
class MLXService {
    static let shared = MLXService()
    
    /// Thread-safe cache of available model names
    private static let availableModelsCache = NSCache<NSString, NSArray>()
    
    /// List of available models that can be used for generation.
    /// Dynamically generated from downloaded models
    var availableModels: [LMModel] {
        // Get downloaded models from ModelManager
        let downloadedModels = ModelManager.shared.availableModels.filter { $0.isDownloaded }
        
        // Map downloaded models to LMModel
        return downloadedModels.map { downloadedModel in
            LMModel(
                name: downloadedModel.name.lowercased().replacingOccurrences(of: " ", with: "-"),
                modelId: downloadedModel.id
            )
        }
    }
    
    /// Cache to store loaded chat sessions to avoid reloading.
    private final class SessionHolder: NSObject {
        let container: ModelContainer
        let session: ChatSession
        init(container: ModelContainer, session: ChatSession) {
            self.container = container
            self.session = session
        }
    }
    private let modelCache = NSCache<NSString, SessionHolder>()
    
    /// Currently loaded model name
    private(set) var currentModelName: String?
    
    /// Tracks the current model download progress.
    /// Access this property to monitor model download status.
    private(set) var modelDownloadProgress: Progress?
    
    private init() {
        // Initialize the cache with current available models
        updateAvailableModelsCache()
        
        // Update cache whenever ModelManager changes
        Task { @MainActor in
            // Observe changes and update cache
            // This ensures the cache stays in sync
            updateAvailableModelsCache()
        }
    }
    
    /// Update the cached list of available models
    func updateAvailableModelsCache() {
        let modelNames = availableModels.map { $0.name }
        Self.availableModelsCache.setObject(modelNames as NSArray, forKey: "models" as NSString)
        
        // Also cache model info for findModel
        let modelInfo = availableModels.map { model in
            ["name": model.name, "id": model.modelId]
        }
        Self.availableModelsCache.setObject(modelInfo as NSArray, forKey: "modelInfo" as NSString)
    }
    
    /// Get list of available models that are downloaded (thread-safe)
    nonisolated func getAvailableModels() -> [String] {
        // Try to get from cache first
        if let cached = Self.availableModelsCache.object(forKey: "models" as NSString) as? [String] {
            return cached
        }
        
        // Return empty list if cache is not populated
        // The cache will be updated when models are loaded
        return []
    }
    
    /// Find a model by name
    nonisolated func findModel(named name: String) -> LMModel? {
        // Check if we have cached model info
        if let cachedModels = Self.availableModelsCache.object(forKey: "modelInfo" as NSString) as? [[String: String]] {
            for modelInfo in cachedModels {
                if let modelName = modelInfo["name"], let modelId = modelInfo["id"], modelName == name {
                    return LMModel(name: modelName, modelId: modelId)
                }
            }
        }
        
        return nil
    }
    
    /// Loads a model container from local storage or retrieves it from cache.
    private func load(model: LMModel) async throws -> SessionHolder {
        if let holder = modelCache.object(forKey: model.name as NSString) {
            return holder
        }

        guard let downloadedModel = ModelManager.shared.availableModels.first(
            where: { $0.id == model.modelId && $0.isDownloaded }
        ) else {
            throw NSError(domain: "MLXService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Model not downloaded: \(model.name)"
            ])
        }

        let localURL = downloadedModel.localDirectory
        let container = try await loadModelContainer(directory: localURL)
        let session = ChatSession(container)
        let holder = SessionHolder(container: container, session: session)
        modelCache.setObject(holder, forKey: model.name as NSString)
        currentModelName = model.name
        updateAvailableModelsCache()
        return holder
    }
    
    /// Generates text based on the provided messages using the specified model.
    /// - Parameters:
    ///   - messages: Array of chat messages including user, assistant, and system messages
    ///   - model: The language model to use for generation
    ///   - temperature: Controls randomness in generation (0.0 to 1.0)
    ///   - maxTokens: Maximum number of tokens to generate
    /// - Returns: An AsyncStream of generated text tokens
    /// - Throws: Errors that might occur during generation
    func generate(
        messages: [Message],
        model: LMModel,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> AsyncStream<String> {
        // Load or retrieve chat session from cache
        let holder = try await load(model: model)

        // Build a simple prompt from chat messages
        let prompt = buildPrompt(from: messages)

        // Run generation using MLXLMCommon's ChatSession
        return AsyncStream<String> { continuation in
            Task {
                // Stream if possible for responsiveness; if not, fall back to single response
                let stream = holder.session.streamResponse(to: prompt)
                do {
                    for try await token in stream {
                        continuation.yield(token)
                    }
                } catch {
                    // On error, finish the stream; upstream will send error JSON
                }
                continuation.finish()
            }
        }
    }
    
    /// Unload a model from memory
    func unloadModel(named name: String) {
        modelCache.removeObject(forKey: name as NSString)
        if currentModelName == name {
            currentModelName = nil
        }
        
        // Update available models cache
        updateAvailableModelsCache()
    }
    
    /// Clear all cached models
    func clearCache() {
        modelCache.removeAllObjects()
        currentModelName = nil
        
        // Update available models cache
        updateAvailableModelsCache()
    }
}

// MARK: - Prompt Formatting
private func buildPrompt(from messages: [Message]) -> String {
    var systemPrompt = ""
    var conversation = ""
    for message in messages {
        switch message.role {
        case .system:
            if !systemPrompt.isEmpty { systemPrompt += "\n" }
            systemPrompt += message.content
        case .user:
            conversation += "User: \(message.content)\n"
        case .assistant:
            conversation += "Assistant: \(message.content)\n"
        }
    }
    let fullPrompt: String
    if systemPrompt.isEmpty {
        fullPrompt = conversation
    } else {
        fullPrompt = "\(systemPrompt)\n\n\(conversation)Assistant:"
    }
    return fullPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
}
