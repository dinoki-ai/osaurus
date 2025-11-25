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
            // Apple Foundation models require macOS 26
            // Use legacy FoundationModelService for now
            throw FactoryError.providerNotAvailable(provider: .appleFoundation)

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

    /// Create MLX model from local installation
    private static func createMLXModel(modelName: String) throws -> any LanguageModel {
        // Find the installed model by name
        guard let model = ModelManager.findInstalledModel(named: modelName) else {
            throw FactoryError.modelNotFound(name: modelName)
        }

        // Use the HuggingFace model ID (e.g., "mlx-community/Qwen3-0.6B-4bit")
        // MLXLanguageModel will load from the HuggingFace cache or download if needed
        return MLXLanguageModel(modelId: model.id)
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
