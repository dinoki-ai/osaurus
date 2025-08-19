//
//  MLXService.swift
//  osaurus
//
//  Created by Osaurus on 1/29/25.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

/// Model type enumeration
enum ModelType {
    case llm
    case vlm
}

/// Represents a language model configuration
struct LMModel {
    let name: String
    let configuration: ModelRegistry
    let type: ModelType
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
    let images: [URL]
    let videos: [URL]
    
    init(role: MessageRole, content: String, images: [URL] = [], videos: [URL] = []) {
        self.role = role
        self.content = content
        self.images = images
        self.videos = videos
    }
}

/// A service class that manages machine learning models for text and vision-language tasks.
/// This class handles model loading, caching, and text generation using various LLM and VLM models.
@Observable
@MainActor
class MLXService {
    static let shared = MLXService()
    
    /// Mapping between downloaded model IDs and MLX configurations
    static let modelMapping: [String: (name: String, configuration: ModelRegistry, type: ModelType)] = [
        // Llama models
        "mlx-community/Llama-3.2-3B-Instruct-4bit": ("llama-3.2-3b-instruct", LLMRegistry.llama3_2_3B_4bit, .llm),
        "mlx-community/Llama-3.2-1B-Instruct-4bit": ("llama-3.2-1b-instruct", LLMRegistry.llama3_2_1B_4bit, .llm),
        
        // Qwen models
        "mlx-community/Qwen2.5-7B-Instruct-4bit": ("qwen2.5-7b-instruct", LLMRegistry.qwen2_5_7B_4bit, .llm),
        "mlx-community/Qwen2.5-3B-Instruct-4bit": ("qwen2.5-3b-instruct", LLMRegistry.qwen2_5_3B_4bit, .llm),
        
        // Gemma models
        "mlx-community/gemma-2-9b-it-4bit": ("gemma-2-9b-instruct", LLMRegistry.gemma2_9B_4bit, .llm),
        "mlx-community/gemma-2-2b-it-4bit": ("gemma-2-2b-instruct", LLMRegistry.gemma2_2B_4bit, .llm),
        
        // DeepSeek models
        "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit": ("deepseek-r1-1.5b", LLMRegistry.qwen2_5_1_5b, .llm),
        
        // OpenELM models
        "mlx-community/OpenELM-3B-Instruct-4bit": ("openelm-3b-instruct", LLMRegistry.openelm_3B_instruct, .llm)
    ]
    
    /// List of available models that can be used for generation.
    /// Dynamically generated from downloaded models
    var availableModels: [LMModel] {
        var models: [LMModel] = []
        
        // Get downloaded models from ModelManager
        let downloadedModels = ModelManager.shared.availableModels.filter { $0.isDownloaded }
        
        // Map downloaded models to LMModel configurations
        for downloadedModel in downloadedModels {
            if let mapping = Self.modelMapping[downloadedModel.id] {
                let lmModel = LMModel(
                    name: mapping.name,
                    configuration: mapping.configuration,
                    type: mapping.type
                )
                models.append(lmModel)
            }
        }
        
        // If no models are downloaded, return a default set for testing
        if models.isEmpty {
            models = [
                LMModel(name: "llama3.2:1b", configuration: LLMRegistry.llama3_2_1B_4bit, type: .llm),
                LMModel(name: "qwen2.5:1.5b", configuration: LLMRegistry.qwen2_5_1_5b, type: .llm),
                LMModel(name: "smolLM:135m", configuration: LLMRegistry.smolLM_135M_4bit, type: .llm),
            ]
        }
        
        return models
    }
    
    /// Cache to store loaded model containers to avoid reloading.
    private let modelCache = NSCache<NSString, ModelContainer>()
    
    /// Currently loaded model name
    private(set) var currentModelName: String?
    
    /// Tracks the current model download progress.
    /// Access this property to monitor model download status.
    private(set) var modelDownloadProgress: Progress?
    
    private init() {}
    
    /// Get list of available models that are downloaded
    func getAvailableModels() -> [String] {
        return availableModels.map { $0.name }
    }
    
    /// Find a model by name
    func findModel(named name: String) -> LMModel? {
        return availableModels.first { $0.name == name }
    }
    
    /// Loads a model from the hub or retrieves it from cache.
    /// - Parameter model: The model configuration to load
    /// - Returns: A ModelContainer instance containing the loaded model
    /// - Throws: Errors that might occur during model loading
    private func load(model: LMModel) async throws -> ModelContainer {
        // Set GPU memory limit to prevent out of memory issues
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        
        // Return cached model if available to avoid reloading
        if let container = modelCache.object(forKey: model.name as NSString) {
            return container
        } else {
            // Select appropriate factory based on model type
            let factory: ModelFactory =
                switch model.type {
                case .llm:
                    LLMModelFactory.shared
                case .vlm:
                    VLMModelFactory.shared
                }
            
            // Check if we have a downloaded model path
            let downloadedModel = ModelManager.shared.availableModels.first { mlxModel in
                Self.modelMapping[mlxModel.id]?.name == model.name && mlxModel.isDownloaded
            }
            
            let container: ModelContainer
            
            if let downloadedModel = downloadedModel {
                // Load from local directory
                let localURL = downloadedModel.localDirectory
                container = try await factory.loadContainer(
                    configuration: model.configuration,
                    url: localURL
                ) { progress in
                    Task { @MainActor in
                        self.modelDownloadProgress = progress
                    }
                }
            } else {
                // Load from hub (fallback for testing)
                container = try await factory.loadContainer(
                    hub: .default, configuration: model.configuration
                ) { progress in
                    Task { @MainActor in
                        self.modelDownloadProgress = progress
                    }
                }
            }
            
            // Cache the loaded model for future use
            modelCache.setObject(container, forKey: model.name as NSString)
            currentModelName = model.name
            
            return container
        }
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
        // Load or retrieve model from cache
        let modelContainer = try await load(model: model)
        
        // Map app-specific Message type to Chat.Message for model input
        let chat = messages.map { message in
            let role: Chat.Message.Role =
                switch message.role {
                case .assistant:
                    .assistant
                case .user:
                    .user
                case .system:
                    .system
                }
            
            // Process any attached media for VLM models
            let images: [UserInput.Image] = message.images.map { imageURL in .url(imageURL) }
            let videos: [UserInput.Video] = message.videos.map { videoURL in .url(videoURL) }
            
            return Chat.Message(
                role: role, content: message.content, images: images, videos: videos)
        }
        
        // Prepare input for model processing
        let userInput = UserInput(
            chat: chat, processing: .init(resize: .init(width: 1024, height: 1024)))
        
        // Generate response using the model
        let generationStream = try await modelContainer.perform { (context: ModelContext) in
            let lmInput = try await context.processor.prepare(input: userInput)
            // Set generation parameters
            let parameters = GenerateParameters(
                temperature: temperature,
                maxTokens: maxTokens
            )
            
            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }
        
        // Convert Generation stream to String stream
        return AsyncStream<String> { continuation in
            Task {
                do {
                    for try await generation in generationStream {
                        if let text = generation.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
    
    /// Unload a model from memory
    func unloadModel(named name: String) {
        modelCache.removeObject(forKey: name as NSString)
        if currentModelName == name {
            currentModelName = nil
        }
    }
    
    /// Clear all cached models
    func clearCache() {
        modelCache.removeAllObjects()
        currentModelName = nil
    }
}
