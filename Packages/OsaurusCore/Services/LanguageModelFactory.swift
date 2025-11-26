//
//  LanguageModelFactory.swift
//  osaurus
//
//  Factory for creating AnyLanguageModel providers based on configuration.
//

import AnyLanguageModel
import Foundation

/// Factory for creating language model instances based on provider configuration
public enum LanguageModelFactory {

    public enum FactoryError: Error, LocalizedError {
        case missingAPIKey(provider: LLMProvider)
        case modelNotFound(name: String)
        case providerNotAvailable(provider: LLMProvider)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider.displayName)"
            case .modelNotFound(let name):
                return "Model not found: \(name)"
            case .providerNotAvailable(let provider):
                return "\(provider.displayName) is not available on this system"
            }
        }
    }

    /// Create a language model based on the current provider configuration
    @MainActor
    public static func createModel(
        provider: LLMProvider,
        modelId: String
    ) throws -> any LanguageModel {
        switch provider {
        case .appleFoundation:
            return try createAppleFoundationModel()

        case .mlx:
            return try createMLXModel(modelName: modelId)

        case .openai:
            return try createOpenAIModel(modelId: modelId)

        case .anthropic:
            return try createAnthropicModel(modelId: modelId)

        case .gemini:
            return try createGeminiModel(modelId: modelId)
        }
    }
    
    /// Create Apple Foundation model (requires macOS 26+)
    private static func createAppleFoundationModel() throws -> any LanguageModel {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            NSLog("[LanguageModelFactory] Creating SystemLanguageModel for Apple Foundation")
            return SystemLanguageModel.default
        } else {
            throw FactoryError.providerNotAvailable(provider: .appleFoundation)
        }
        #else
        throw FactoryError.providerNotAvailable(provider: .appleFoundation)
        #endif
    }

    /// Create MLX model from local installation
    private static func createMLXModel(modelName: String) throws -> any LanguageModel {
        NSLog("[LanguageModelFactory] createMLXModel called with modelName: \(modelName)")
        
        // Find the installed model by name
        guard let model = ModelManager.findInstalledModel(named: modelName) else {
            NSLog("[LanguageModelFactory] Model not found: \(modelName)")
            throw FactoryError.modelNotFound(name: modelName)
        }
        
        NSLog("[LanguageModelFactory] Found model - name: \(model.name), id: \(model.id)")

        // Build the path to the model directory
        // Models are stored at: {modelsDirectory}/{org}/{model}/
        // e.g., ~/Documents/MLXModels/mlx-community/Llama-3.2-3B-Instruct-4bit/
        let modelsDirectory = DirectoryPickerService.defaultModelsDirectory()
        let modelDirectory = modelsDirectory.appendingPathComponent(model.id)
        
        NSLog("[LanguageModelFactory] Using model directory: \(modelDirectory.path)")
        
        // Verify directory exists
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            NSLog("[LanguageModelFactory] Model directory does not exist: \(modelDirectory.path)")
            throw FactoryError.modelNotFound(name: modelName)
        }

        NSLog("[LanguageModelFactory] Creating MLXLanguageModel with directory: \(modelDirectory.path)")
        return MLXLanguageModel(modelId: model.id, directory: modelDirectory)
    }

    /// Create OpenAI model
    @MainActor
    private static func createOpenAIModel(modelId: String) throws -> any LanguageModel {
        guard let apiKey = KeychainHelper.getAPIKey(for: .openai) else {
            throw FactoryError.missingAPIKey(provider: .openai)
        }

        return OpenAILanguageModel(
            apiKey: apiKey,
            model: modelId
        )
    }

    /// Create Anthropic model
    @MainActor
    private static func createAnthropicModel(modelId: String) throws -> any LanguageModel {
        guard let apiKey = KeychainHelper.getAPIKey(for: .anthropic) else {
            throw FactoryError.missingAPIKey(provider: .anthropic)
        }

        return AnthropicLanguageModel(
            apiKey: apiKey,
            model: modelId
        )
    }

    /// Create Google Gemini model
    @MainActor
    private static func createGeminiModel(modelId: String) throws -> any LanguageModel {
        guard let apiKey = KeychainHelper.getAPIKey(for: .gemini) else {
            throw FactoryError.missingAPIKey(provider: .gemini)
        }

        return GeminiLanguageModel(
            apiKey: apiKey,
            model: modelId
        )
    }
}
