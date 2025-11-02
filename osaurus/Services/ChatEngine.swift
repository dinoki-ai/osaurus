//
//  ChatEngine.swift
//  osaurus
//
//  Actor encapsulating model routing and generation streaming.
//

import AnyLanguageModel
import Foundation

actor ChatEngine: Sendable, ChatEngineProtocol {
  struct EngineError: Error {}

  func streamChat(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<String, Error>
  {
    // Build prompt directly from OpenAI-format messages to preserve tool_calls and tool results
    let prompt = OpenAIPromptBuilder.buildPrompt(from: request.messages)

    let temperature = request.temperature ?? 1.0
    let maxTokens = request.max_tokens ?? 512
    _ = request.top_p  // currently unused

    // Resolve model (SystemLanguageModel for default/foundation, otherwise MLX by name/id)
    let (model, _) = try AnyLMSelection.resolveModel(requested: request.model)

    // Bridge tools (provide empty array when none)
    let tools: [any AnyLanguageModel.Tool] = {
      if let t = request.tools, !t.isEmpty {
        return AnyLMBridge.bridgedTools(from: t, choice: request.tool_choice)
      } else {
        return []
      }
    }()

    let options = AnyLanguageModel.GenerationOptions(
      sampling: nil,
      temperature: Double(temperature),
      maximumResponseTokens: maxTokens
    )

    let session = AnyLanguageModel.LanguageModelSession(
      model: model, tools: tools, instructions: nil)
    let stopSequences = request.stop ?? []

    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    Task {
      var previous = ""
      do {
        var iterator = session.streamResponse(to: prompt, options: options).makeAsyncIterator()
        while let snapshot = try await iterator.next() {
          var current = snapshot.content
          if !stopSequences.isEmpty,
            let r = stopSequences.compactMap({ current.range(of: $0)?.lowerBound }).first
          {
            current = String(current[..<r])
          }
          let delta: String
          if current.hasPrefix(previous) {
            delta = String(current.dropFirst(previous.count))
          } else {
            delta = current
          }
          if !delta.isEmpty { continuation.yield(delta) }
          previous = current
        }
        continuation.finish()
      } catch {
        if let inv = AnyLMBridge.mapToolCallError(error) {
          continuation.finish(throwing: inv)
        } else {
          continuation.finish(throwing: error)
        }
      }
    }
    return stream
  }

  func completeChat(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
    // Build prompt directly from OpenAI-format messages to preserve tool_calls and tool results
    let prompt = OpenAIPromptBuilder.buildPrompt(from: request.messages)

    let temperature = request.temperature ?? 1.0
    let maxTokens = request.max_tokens ?? 512

    let created = Int(Date().timeIntervalSince1970)
    let responseId =
      "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

    let (model, effectiveModel) = try AnyLMSelection.resolveModel(requested: request.model)
    let tools: [any AnyLanguageModel.Tool] = {
      if let t = request.tools, !t.isEmpty {
        return AnyLMBridge.bridgedTools(from: t, choice: request.tool_choice)
      } else {
        return []
      }
    }()

    let options = AnyLanguageModel.GenerationOptions(
      sampling: nil,
      temperature: Double(temperature),
      maximumResponseTokens: maxTokens
    )
    let session = AnyLanguageModel.LanguageModelSession(
      model: model, tools: tools, instructions: nil)

    // If tools provided, AnyLanguageModel will surface a ToolCallError.
    do {
      let text = try await session.respond(to: prompt, options: options).content
      let choice = ChatChoice(
        index: 0,
        message: ChatMessage(role: "assistant", content: text, tool_calls: nil, tool_call_id: nil),
        finish_reason: "stop"
      )
      let usage = Usage(prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
      return ChatCompletionResponse(
        id: responseId,
        created: created,
        model: effectiveModel,
        choices: [choice],
        usage: usage,
        system_fingerprint: nil
      )
    } catch {
      if let inv = AnyLMBridge.mapToolCallError(error) {
        // Convert tool invocation to OpenAI-style non-stream response
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
          model: effectiveModel,
          choices: [choice],
          usage: usage,
          system_fingerprint: nil
        )
      }
      throw error
    }
  }
}
