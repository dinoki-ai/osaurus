//
//  ProviderSettingsView.swift
//  osaurus
//
//  UI for configuring LLM providers and API keys with unified model selection.
//

import SwiftUI

struct ProviderSettingsView: View {
    @Environment(\.theme) private var theme
    @Binding var providerConfig: ProviderConfiguration
    @State private var apiKeyInputs: [LLMProvider: String] = [:]
    @State private var showAPIKey: [LLMProvider: Bool] = [:]
    @State private var saveStatus: [LLMProvider: SaveStatus] = [:]
    @State private var showAPIKeyConfig: Bool = false

    private enum SaveStatus {
        case idle
        case saving
        case saved
        case error(String)
    }

    /// Get all available models grouped by provider
    private var groupedModels: [(provider: LLMProvider, models: [ModelIdentifier])] {
        AvailableModels.grouped(includeUnconfigured: true)
    }

    /// Currently selected model identifier
    private var selectedModelId: ModelIdentifier? {
        providerConfig.modelIdentifier
    }

    /// Providers that require API key configuration
    private var unconfiguredProviders: [LLMProvider] {
        LLMProvider.allCases.filter { provider in
            provider.requiresAPIKey && !KeychainHelper.hasAPIKey(for: provider)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model", systemImage: "brain")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.primaryText)

            // Unified Model Selection
            modelSelectionMenu

            // Status indicator
            modelStatusView

            // API Key Configuration Section (collapsible)
            apiKeyConfigSection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.secondaryBackground)
        )
        .onAppear {
            // Initialize API key inputs from stored values
            for provider in LLMProvider.allCases where provider.requiresAPIKey {
                if let storedKey = KeychainHelper.getAPIKey(for: provider) {
                    apiKeyInputs[provider] = storedKey
                } else {
                    apiKeyInputs[provider] = ""
                }
                showAPIKey[provider] = false
            }
        }
    }

    // MARK: - Model Selection Menu

    @ViewBuilder
    private var modelSelectionMenu: some View {
        Menu {
            ForEach(groupedModels, id: \.provider) { group in
                Section(header: Text(group.provider.displayName)) {
                    ForEach(group.models) { model in
                        Button(action: {
                            providerConfig.selectedModel = model.id
                        }) {
                            HStack {
                                Text(model.shortName)
                                if model.id == providerConfig.selectedModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(group.provider.requiresAPIKey && !KeychainHelper.hasAPIKey(for: group.provider))
                    }
                }
            }
        } label: {
            HStack {
                if let selected = selectedModelId {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.shortName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(selected.provider.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(theme.secondaryText)
                    }
                } else {
                    Text("Select a model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.inputBorder, lineWidth: 1)
                    )
            )
            .foregroundColor(theme.primaryText)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Status View

    @ViewBuilder
    private var modelStatusView: some View {
        if let model = selectedModelId {
            HStack(spacing: 6) {
                Circle()
                    .fill(isModelReady(model) ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(modelStatusText(model))
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
            }
        }
    }

    // MARK: - API Key Configuration

    @ViewBuilder
    private var apiKeyConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle button for API key configuration
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAPIKeyConfig.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(showAPIKeyConfig ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showAPIKeyConfig)

                    Text("API Keys")
                        .font(.system(size: 11, weight: .medium))

                    Spacer()

                    // Show unconfigured count
                    if !unconfiguredProviders.isEmpty {
                        Text("\(unconfiguredProviders.count) unconfigured")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    } else {
                        Text("All configured")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                .foregroundColor(theme.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if showAPIKeyConfig {
                VStack(spacing: 12) {
                    ForEach([LLMProvider.openai, .anthropic, .gemini], id: \.self) { provider in
                        apiKeyRow(for: provider)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func apiKeyRow(for provider: LLMProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(provider.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.primaryText)

                Spacer()

                // Status indicator
                if case .saved = saveStatus[provider] {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .foregroundColor(.green)
                    }
                    .font(.system(size: 10))
                } else if case .saving = saveStatus[provider] {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Saving...")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
                } else if case .error(let msg) = saveStatus[provider] {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else if KeychainHelper.hasAPIKey(for: provider) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Configured")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)
                }
            }

            HStack(spacing: 6) {
                Group {
                    if showAPIKey[provider] == true {
                        TextField(apiKeyPlaceholder(for: provider), text: binding(for: provider))
                    } else {
                        SecureField(apiKeyPlaceholder(for: provider), text: binding(for: provider))
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.inputBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(theme.inputBorder, lineWidth: 1)
                        )
                )
                .foregroundColor(theme.primaryText)

                Button(action: { showAPIKey[provider]?.toggle() }) {
                    Image(systemName: showAPIKey[provider] == true ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { saveAPIKey(for: provider) }) {
                    Text("Save")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.buttonBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(theme.buttonBorder, lineWidth: 1)
                                )
                        )
                        .foregroundColor(theme.primaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private func binding(for provider: LLMProvider) -> Binding<String> {
        Binding(
            get: { apiKeyInputs[provider] ?? "" },
            set: { apiKeyInputs[provider] = $0 }
        )
    }

    private func apiKeyPlaceholder(for provider: LLMProvider) -> String {
        switch provider {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        default: return "Enter API key"
        }
    }

    private func saveAPIKey(for provider: LLMProvider) {
        guard let key = apiKeyInputs[provider], !key.isEmpty else {
            saveStatus[provider] = .error("Empty key")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus[provider] = .idle
            }
            return
        }

        saveStatus[provider] = .saving

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let success = KeychainHelper.saveAPIKey(key, for: provider)
            if success {
                saveStatus[provider] = .saved
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    saveStatus[provider] = .idle
                }
            } else {
                saveStatus[provider] = .error("Failed")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    saveStatus[provider] = .idle
                }
            }
        }
    }

    private func isModelReady(_ model: ModelIdentifier) -> Bool {
        switch model.provider {
        case .appleFoundation:
            return FoundationModelService.isDefaultModelAvailable()
        case .mlx:
            return MLXService.getAvailableModels().contains(model.modelName)
        case .openai, .anthropic, .gemini:
            return KeychainHelper.hasAPIKey(for: model.provider)
        }
    }

    private func modelStatusText(_ model: ModelIdentifier) -> String {
        switch model.provider {
        case .appleFoundation:
            return FoundationModelService.isDefaultModelAvailable()
                ? "Apple Intelligence available"
                : "Requires macOS 26+"
        case .mlx:
            return "Local model"
        case .openai, .anthropic, .gemini:
            return KeychainHelper.hasAPIKey(for: model.provider)
                ? "Ready"
                : "API key required"
        }
    }
}
