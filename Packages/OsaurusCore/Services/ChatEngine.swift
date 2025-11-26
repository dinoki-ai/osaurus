//
//  ChatEngine.swift
//  osaurus
//
//  Actor encapsulating model routing and generation streaming via AnyLanguageModel.
//

import AnyLanguageModel
import Foundation

actor ChatEngine: Sendable, ChatEngineProtocol {
    struct EngineError: Error, LocalizedError {
        let message: String

        init(_ message: String = "Engine error") {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    // Legacy services for backward compatibility during migration
    private let legacyServices: [ModelService]
    private let installedModelsProvider: @Sendable () -> [String]

    init(
        services: [ModelService] = [MLXService()],  // MLXService kept for model discovery
        installedModelsProvider: @escaping @Sendable () -> [String] = {
            MLXService.getAvailableModels()
        }
    ) {
        self.legacyServices = services
        self.installedModelsProvider = installedModelsProvider
    }

    // MARK: - Provider Resolution

    private func resolveProvider(requestedModel: String?) async -> (LLMProvider, String)? {
        let trimmed = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as "provider/model" format first
        if let modelId = ModelIdentifier(from: trimmed) {
            return (modelId.provider, modelId.modelName)
        }

        // Try to infer provider from model name
        if let inferred = ModelIdentifier.infer(from: trimmed) {
            return (inferred.provider, inferred.modelName)
        }

        // Fall back to configured model
        let config = await MainActor.run { ProviderConfigurationStore.load() }
        if let configuredModel = config.modelIdentifier {
            return (configuredModel.provider, configuredModel.modelName)
        }

        // Last resort: check if it's a known model name
        for provider in [LLMProvider.openai, .anthropic, .gemini] {
            if provider.availableModels.contains(trimmed) {
                return (provider, trimmed)
            }
        }

        // Check installed MLX models
        let installedModels = installedModelsProvider()
        if installedModels.contains(trimmed) {
            return (.mlx, trimmed)
        }

        return nil
    }

    private func enrichMessagesWithSystemPrompt(_ messages: [ChatMessage]) async -> [ChatMessage] {
        // Check if a system prompt is already present
        if messages.contains(where: { $0.role == "system" }) {
            return messages
        }

        // If not, fetch the global system prompt
        let systemPrompt = await MainActor.run {
            ChatConfigurationStore.load().systemPrompt
        }

        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return messages }

        // Prepend the system prompt
        let systemMessage = ChatMessage(role: "system", content: trimmed)
        return [systemMessage] + messages
    }

    // MARK: - Streaming Chat

    func streamChat(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<String, Error> {
        let messages = await enrichMessagesWithSystemPrompt(request.messages)

        // Resolve provider
        guard let (provider, modelId) = await resolveProvider(requestedModel: request.model) else {
            throw EngineError("Unable to resolve model provider for: \(request.model)")
        }

        NSLog("[ChatEngine] streamChat - request.model: \(request.model), resolved provider: \(provider.rawValue), modelId: \(modelId)")

        // All providers now use AnyLanguageModel
        NSLog("[ChatEngine] Creating model via LanguageModelFactory for provider: \(provider.rawValue), modelId: \(modelId)")
        let model = try await MainActor.run {
            try LanguageModelFactory.createModel(provider: provider, modelId: modelId)
        }
        NSLog("[ChatEngine] Model created successfully")

        // Build the prompt from messages
        let prompt = buildPromptContent(from: messages)
        NSLog("[ChatEngine] Built prompt: \(prompt.prefix(200))...")

        // Create streaming response
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        Task {
            do {
                NSLog("[ChatEngine] Creating LanguageModelSession...")
                let session = LanguageModelSession(model: model)

                // MLX doesn't support streaming (returns empty), use non-streaming respond()
                // Other providers (Apple Foundation, OpenAI, Anthropic, Gemini) support streaming
                if provider == .mlx {
                    NSLog("[ChatEngine] Using respond() (non-streaming) for MLX")
                    let response = try await session.respond(to: prompt)
                    let content = response.content
                    NSLog("[ChatEngine] Response received, length: \(content.count)")
                    
                    if !content.isEmpty {
                        continuation.yield(content)
                    }
                    continuation.finish()
                } else {
                    NSLog("[ChatEngine] Using streamResponse() for \(provider.rawValue)")
                    var previousContent = ""
                    var chunkCount = 0
                    for try await partial in session.streamResponse(to: prompt) {
                        chunkCount += 1
                        let currentContent = partial.content
                        // Extract delta (new content since last update)
                        let delta: String
                        if currentContent.hasPrefix(previousContent) {
                            delta = String(currentContent.dropFirst(previousContent.count))
                        } else {
                            delta = currentContent
                        }
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        previousContent = currentContent
                    }
                    NSLog("[ChatEngine] Stream completed with \(chunkCount) chunks, final content length: \(previousContent.count)")
                    continuation.finish()
                }
            } catch {
                NSLog("[ChatEngine] Response error: \(error)")
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    // MARK: - Non-Streaming Chat

    func completeChat(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let messages = await enrichMessagesWithSystemPrompt(request.messages)

        // Resolve provider
        guard let (provider, modelId) = await resolveProvider(requestedModel: request.model) else {
            throw EngineError("Unable to resolve model provider for: \(request.model)")
        }

        // All providers use AnyLanguageModel
        let model = try await MainActor.run {
            try LanguageModelFactory.createModel(provider: provider, modelId: modelId)
        }

        // Build the prompt from messages
        let prompt = buildPromptContent(from: messages)

        // Create session and get response
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt)

        // Build OpenAI-compatible response
        let created = Int(Date().timeIntervalSince1970)
        let responseId =
            "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        let choice = ChatChoice(
            index: 0,
            message: ChatMessage(
                role: "assistant",
                content: response.content,
                tool_calls: nil,
                tool_call_id: nil
            ),
            finish_reason: "stop"
        )

        let usage = Usage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)

        return ChatCompletionResponse(
            id: responseId,
            created: created,
            model: modelId,
            choices: [choice],
            usage: usage,
            system_fingerprint: nil
        )
    }

    // MARK: - Prompt Building

    private func buildPromptContent(from messages: [ChatMessage]) -> String {
        return OpenAIPromptBuilder.buildPrompt(from: messages)
    }

    // MARK: - Legacy Service Support (for MLX during migration)

    private func streamWithLegacyService(
        request: ChatCompletionRequest,
        messages: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        NSLog("[ChatEngine] streamWithLegacyService - request.model: \(request.model)")

        let temperature = request.temperature ?? 1.0
        let maxTokens = request.max_tokens ?? 512
        let repPenalty: Float? = {
            if let fp = request.frequency_penalty, fp > 0 { return 1.0 + fp }
            if let pp = request.presence_penalty, pp > 0 { return 1.0 + pp }
            return nil
        }()
        let params = GenerationParameters(
            temperature: temperature,
            maxTokens: maxTokens,
            topPOverride: request.top_p,
            repetitionPenalty: repPenalty
        )

        let route = ModelServiceRouter.resolve(
            requestedModel: request.model,
            services: legacyServices
        )

        NSLog("[ChatEngine] streamWithLegacyService - route resolved: \(String(describing: route))")

        switch route {
        case .service(let service, _):
            let hasTools = request.tools != nil && !request.tools!.isEmpty
            let isToolCapable = service is ToolCapableService
            NSLog("[ChatEngine] service found: \(service.id), hasTools: \(hasTools), isToolCapable: \(isToolCapable)")

            if hasTools, let toolSvc = service as? ToolCapableService {
                NSLog("[ChatEngine] using streamWithTools path")
                let stopSequences = request.stop ?? []
                return try await toolSvc.streamWithTools(
                    messages: messages,
                    parameters: params,
                    stopSequences: stopSequences,
                    tools: request.tools!,
                    toolChoice: request.tool_choice,
                    requestedModel: request.model
                )
            }

            NSLog("[ChatEngine] using streamDeltas path")
            return try await service.streamDeltas(
                messages: messages,
                parameters: params,
                requestedModel: request.model,
                stopSequences: request.stop ?? []
            )
        case .none:
            NSLog("[ChatEngine] route is .none for model: \(request.model)")
            throw EngineError("No service available for model: \(request.model)")
        }
    }

    private func completeWithLegacyService(
        request: ChatCompletionRequest,
        messages: [ChatMessage],
        effectiveModel: String
    ) async throws -> ChatCompletionResponse {
        let temperature = request.temperature ?? 1.0
        let maxTokens = request.max_tokens ?? 512
        let repPenalty: Float? = {
            if let fp = request.frequency_penalty, fp > 0 { return 1.0 + fp }
            if let pp = request.presence_penalty, pp > 0 { return 1.0 + pp }
            return nil
        }()
        let params = GenerationParameters(
            temperature: temperature,
            maxTokens: maxTokens,
            topPOverride: request.top_p,
            repetitionPenalty: repPenalty
        )

        let route = ModelServiceRouter.resolve(
            requestedModel: request.model,
            services: legacyServices
        )

        let created = Int(Date().timeIntervalSince1970)
        let responseId =
            "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        switch route {
        case .service(let service, let routedModel):
            if let tools = request.tools, !tools.isEmpty, let toolSvc = service as? ToolCapableService {
                let stopSequences = request.stop ?? []
                do {
                    let text = try await toolSvc.respondWithTools(
                        messages: messages,
                        parameters: params,
                        stopSequences: stopSequences,
                        tools: tools,
                        toolChoice: request.tool_choice,
                        requestedModel: request.model
                    )
                    let choice = ChatChoice(
                        index: 0,
                        message: ChatMessage(
                            role: "assistant",
                            content: text,
                            tool_calls: nil,
                            tool_call_id: nil
                        ),
                        finish_reason: "stop"
                    )
                    let usage = Usage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
                    return ChatCompletionResponse(
                        id: responseId,
                        created: created,
                        model: routedModel,
                        choices: [choice],
                        usage: usage,
                        system_fingerprint: nil
                    )
                } catch let inv as ServiceToolInvocation {
                    let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    let callId = "call_" + String(raw.prefix(24))
                    let toolCall = ToolCall(
                        id: callId,
                        type: "function",
                        function: ToolCallFunction(name: inv.toolName, arguments: inv.jsonArguments)
                    )
                    let assistant = ChatMessage(
                        role: "assistant",
                        content: nil,
                        tool_calls: [toolCall],
                        tool_call_id: nil
                    )
                    let choice = ChatChoice(index: 0, message: assistant, finish_reason: "tool_calls")
                    let usage = Usage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
                    return ChatCompletionResponse(
                        id: responseId,
                        created: created,
                        model: routedModel,
                        choices: [choice],
                        usage: usage,
                        system_fingerprint: nil
                    )
                }
            }

            let text = try await service.generateOneShot(
                messages: messages,
                parameters: params,
                requestedModel: request.model
            )
            let choice = ChatChoice(
                index: 0,
                message: ChatMessage(role: "assistant", content: text, tool_calls: nil, tool_call_id: nil),
                finish_reason: "stop"
            )
            let usage = Usage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
            return ChatCompletionResponse(
                id: responseId,
                created: created,
                model: routedModel,
                choices: [choice],
                usage: usage,
                system_fingerprint: nil
            )
        case .none:
            throw EngineError("No service available for model: \(request.model)")
        }
    }
}
