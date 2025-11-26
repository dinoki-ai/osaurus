//
//  ProviderConfiguration.swift
//  osaurus
//
//  Configuration model for LLM providers with Keychain-based API key storage.
//

import AnyLanguageModel
import Foundation
import Security

// MARK: - Provider Definition

/// Supported language model providers
public enum LLMProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case appleFoundation = "apple_foundation"
    case mlx = "mlx"
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleFoundation: return "Apple Intelligence"
        case .mlx: return "Local"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        }
    }

    /// Whether this provider requires an API key
    public var requiresAPIKey: Bool {
        switch self {
        case .appleFoundation, .mlx:
            return false
        case .openai, .anthropic, .gemini:
            return true
        }
    }

    /// Available models for cloud providers (local providers discover dynamically)
    public var availableModels: [String] {
        switch self {
        case .appleFoundation:
            return ["default"]
        case .mlx:
            return []  // Populated dynamically from installed models
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo", "o1", "o1-mini"]
        case .anthropic:
            return [
                "claude-sonnet-4-20250514",
                "claude-opus-4-20250514",
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
            ]
        case .gemini:
            return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-1.5-pro"]
        }
    }
}

// MARK: - Model Identifier

/// A unified model identifier that combines provider and model name
/// Format: "provider/model" (e.g., "openai/gpt-4o", "mlx/Qwen-4bit")
public struct ModelIdentifier: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let provider: LLMProvider
    public let modelName: String

    public var id: String { "\(provider.rawValue)/\(modelName)" }

    /// Display name shown in UI (e.g., "OpenAI / gpt-4o")
    public var displayName: String {
        "\(provider.displayName) / \(modelName)"
    }

    /// Short display name (just the model name)
    public var shortName: String {
        modelName
    }

    public init(provider: LLMProvider, modelName: String) {
        self.provider = provider
        self.modelName = modelName
    }

    /// Parse a model identifier string (e.g., "openai/gpt-4o")
    public init?(from string: String) {
        let parts = string.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
            let provider = LLMProvider(rawValue: String(parts[0]))
        else {
            return nil
        }
        self.provider = provider
        self.modelName = String(parts[1])
    }

    /// Create from a raw model name by inferring the provider
    public static func infer(from modelName: String) -> ModelIdentifier? {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if already in provider/model format
        if let parsed = ModelIdentifier(from: trimmed) {
            return parsed
        }

        // Check cloud providers' known models
        for provider in [LLMProvider.openai, .anthropic, .gemini] {
            if provider.availableModels.contains(trimmed) {
                return ModelIdentifier(provider: provider, modelName: trimmed)
            }
        }

        // Check if it's an installed MLX model
        let installedMLX = MLXService.getAvailableModels()
        if installedMLX.contains(trimmed) {
            return ModelIdentifier(provider: .mlx, modelName: trimmed)
        }

        // Default/foundation
        if trimmed.isEmpty || trimmed.lowercased() == "default" || trimmed.lowercased() == "foundation" {
            return ModelIdentifier(provider: .appleFoundation, modelName: "default")
        }

        return nil
    }
}

// MARK: - Available Models Helper

/// Provides a unified list of all available models across providers
public enum AvailableModels {
    
    /// Check if Apple Foundation Models (Apple Intelligence) is available
    public static func isAppleFoundationAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                NSLog("[AvailableModels] Apple Foundation is available")
                return true
            } else {
                NSLog("[AvailableModels] Apple Foundation is unavailable")
                return false
            }
        }
        #endif
        NSLog("[AvailableModels] FoundationModels not available on this OS")
        return false
    }
    
    /// Get all available models from all providers
    /// - Parameter includeUnconfigured: If false, excludes cloud providers without API keys
    public static func all(includeUnconfigured: Bool = true) -> [ModelIdentifier] {
        var models: [ModelIdentifier] = []

        for provider in LLMProvider.allCases {
            // Skip providers without API keys unless includeUnconfigured is true
            if provider.requiresAPIKey && !includeUnconfigured && !KeychainHelper.hasAPIKey(for: provider) {
                continue
            }

            switch provider {
            case .appleFoundation:
                if isAppleFoundationAvailable() {
                    models.append(ModelIdentifier(provider: provider, modelName: "default"))
                }
            case .mlx:
                let installed = MLXService.getAvailableModels()
                for modelName in installed {
                    models.append(ModelIdentifier(provider: provider, modelName: modelName))
                }
            case .openai, .anthropic, .gemini:
                for modelName in provider.availableModels {
                    models.append(ModelIdentifier(provider: provider, modelName: modelName))
                }
            }
        }

        return models
    }

    /// Get models grouped by provider
    public static func grouped(includeUnconfigured: Bool = true) -> [(provider: LLMProvider, models: [ModelIdentifier])] {
        var result: [(provider: LLMProvider, models: [ModelIdentifier])] = []

        for provider in LLMProvider.allCases {
            if provider.requiresAPIKey && !includeUnconfigured && !KeychainHelper.hasAPIKey(for: provider) {
                continue
            }

            var providerModels: [ModelIdentifier] = []

            switch provider {
            case .appleFoundation:
                if isAppleFoundationAvailable() {
                    providerModels.append(ModelIdentifier(provider: provider, modelName: "default"))
                }
            case .mlx:
                let installed = MLXService.getAvailableModels()
                for modelName in installed {
                    providerModels.append(ModelIdentifier(provider: provider, modelName: modelName))
                }
            case .openai, .anthropic, .gemini:
                for modelName in provider.availableModels {
                    providerModels.append(ModelIdentifier(provider: provider, modelName: modelName))
                }
            }

            if !providerModels.isEmpty {
                result.append((provider: provider, models: providerModels))
            }
        }

        return result
    }
}

// MARK: - Provider Configuration

/// Configuration for the selected LLM model
public struct ProviderConfiguration: Codable, Equatable, Sendable {
    /// The currently selected model (includes provider info)
    public var selectedModel: String  // Format: "provider/model"

    public init(selectedModel: String = "apple_foundation/default") {
        self.selectedModel = selectedModel
    }

    /// Get the parsed model identifier
    public var modelIdentifier: ModelIdentifier? {
        ModelIdentifier(from: selectedModel)
    }

    /// Get the provider from the selected model
    public var provider: LLMProvider? {
        modelIdentifier?.provider
    }

    /// Get the model name from the selected model
    public var modelName: String? {
        modelIdentifier?.modelName
    }

    public static var `default`: ProviderConfiguration {
        // Default to first available model
        if AvailableModels.isAppleFoundationAvailable() {
            return ProviderConfiguration(selectedModel: "apple_foundation/default")
        }
        let mlxModels = MLXService.getAvailableModels()
        if let first = mlxModels.first {
            return ProviderConfiguration(selectedModel: "mlx/\(first)")
        }
        // Fallback to OpenAI (user needs to configure API key)
        return ProviderConfiguration(selectedModel: "openai/gpt-4o")
    }
}

// MARK: - Keychain Helper

/// Secure storage for API keys using macOS Keychain
public enum KeychainHelper {
    private static let servicePrefix = "com.osaurus.provider"

    /// Save an API key for a provider
    public static func saveAPIKey(_ apiKey: String, for provider: LLMProvider) -> Bool {
        let service = "\(servicePrefix).\(provider.rawValue)"
        let account = "api_key"

        // Delete existing item first
        deleteAPIKey(for: provider)

        guard let data = apiKey.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve an API key for a provider
    public static func getAPIKey(for provider: LLMProvider) -> String? {
        let service = "\(servicePrefix).\(provider.rawValue)"
        let account = "api_key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return apiKey
    }

    /// Delete an API key for a provider
    @discardableResult
    public static func deleteAPIKey(for provider: LLMProvider) -> Bool {
        let service = "\(servicePrefix).\(provider.rawValue)"
        let account = "api_key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if an API key exists for a provider
    public static func hasAPIKey(for provider: LLMProvider) -> Bool {
        return getAPIKey(for: provider) != nil
    }
}
