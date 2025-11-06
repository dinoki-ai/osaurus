//
//  AnyLanguageModelService.swift
//  osaurus
//
//  Unified model service backed by AnyLanguageModel. Routes "default" to the
//  system model when available and short model names to MLX by resolving with
//  ModelManager. Supports one-shot, streaming, and OpenAI-style tools.
//

import Foundation
import AnyLanguageModel

enum AnyLanguageModelServiceError: Error {
  case notAvailable
  case modelNotFound(String)
}

actor AnyLanguageModelService: ToolCapableService {
  nonisolated var id: String { "anylm" }

  // MARK: - System model availability helper

  nonisolated static func isDefaultSystemModelAvailable() -> Bool {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) { return true }
    #endif
    return false
  }

  // MARK: - Availability / Routing

  nonisolated func isAvailable() -> Bool {
    let hasInstalledMLX = !ModelManager.installedModelNames().isEmpty
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        // System model interface is available on supported OS
        return true || hasInstalledMLX
      } else {
        return hasInstalledMLX
      }
    #else
      return hasInstalledMLX
    #endif
  }

  nonisolated func handles(requestedModel: String?) -> Bool {
    let trimmed = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return isAvailable() }
    if trimmed.caseInsensitiveCompare("default") == .orderedSame { return isAvailable() }
    if trimmed.caseInsensitiveCompare("foundation") == .orderedSame { return isAvailable() }
    if ModelManager.findInstalledModel(named: trimmed) != nil { return true }
    if trimmed.contains("/") { return true }
    return false
  }

  // MARK: - ModelService (plain generation)

  func generateOneShot(
    messages: [ChatMessage],
    parameters: GenerationParameters,
    requestedModel: String?
  ) async throws -> String {
    let prompt = OpenAIPromptBuilder.buildPrompt(from: messages)
    let backend = try resolveBackend(for: requestedModel)
    let session: AnyLanguageModel.LanguageModelSession = try {
      if case .mlx(let modelId) = backend {
        let model = AnyLanguageModel.MLXLanguageModel(modelId: modelId)
        return AnyLanguageModel.LanguageModelSession(model: model)
      }
      throw AnyLanguageModelServiceError.notAvailable
    }()

    let options = AnyLanguageModel.GenerationOptions(
      sampling: nil,
      temperature: Double(parameters.temperature),
      maximumResponseTokens: parameters.maxTokens
    )
    let response = try await session.respond(to: prompt, options: options)
    return response.content
  }

  func streamDeltas(
    messages: [ChatMessage],
    parameters: GenerationParameters,
    requestedModel: String?,
    stopSequences: [String]
  ) async throws -> AsyncThrowingStream<String, Error> {
    let prompt = OpenAIPromptBuilder.buildPrompt(from: messages)
    let backend = try resolveBackend(for: requestedModel)
    let session: LanguageModelSession = try {
      if case .mlx(let modelId) = backend {
        let model = MLXLanguageModel(modelId: modelId)
        return LanguageModelSession(model: model)
      }
      throw AnyLanguageModelServiceError.notAvailable
    }()

    let options = GenerationOptions(
      sampling: nil,
      temperature: Double(parameters.temperature),
      maximumResponseTokens: parameters.maxTokens
    )

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
          if !delta.isEmpty {
            continuation.yield(delta)
          }
          previous = current
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return stream
  }

  // MARK: - ToolCapableService (OpenAI-style Tools)

  func respondWithTools(
    messages: [ChatMessage],
    parameters: GenerationParameters,
    stopSequences: [String],
    tools: [Tool],
    toolChoice: ToolChoiceOption?,
    requestedModel: String?
  ) async throws -> String {
    let prompt = OpenAIPromptBuilder.buildPrompt(from: messages)
    let backend = try resolveBackend(for: requestedModel)
    guard case .mlx(let modelId) = backend else { throw AnyLanguageModelServiceError.notAvailable }

    let amlTools: [any AnyLanguageModel.Tool] = tools
      .filter { self.shouldEnableTool($0, choice: toolChoice) }
      .map { self.toAMLTool($0) }

    let session = AnyLanguageModel.LanguageModelSession(
      model: AnyLanguageModel.MLXLanguageModel(modelId: modelId),
      tools: amlTools,
      instructions: nil
    )
    let options = AnyLanguageModel.GenerationOptions(
      sampling: nil,
      temperature: Double(parameters.temperature),
      maximumResponseTokens: parameters.maxTokens
    )

    do {
      let response = try await session.respond(to: prompt, options: options)
      var reply = response.content
      if !stopSequences.isEmpty {
        for s in stopSequences {
          if let r = reply.range(of: s) {
            reply = String(reply[..<r.lowerBound])
            break
          }
        }
      }
      return reply
    } catch let error as AnyLanguageModel.LanguageModelSession.ToolCallError {
      if let inv = error.underlyingError as? ToolInvocationError {
        throw ServiceToolInvocation(toolName: inv.toolName, jsonArguments: inv.jsonArguments)
      }
      throw error
    }
  }

  func streamWithTools(
    messages: [ChatMessage],
    parameters: GenerationParameters,
    stopSequences: [String],
    tools: [Tool],
    toolChoice: ToolChoiceOption?,
    requestedModel: String?
  ) async throws -> AsyncThrowingStream<String, Error> {
    let prompt = OpenAIPromptBuilder.buildPrompt(from: messages)
    let backend = try resolveBackend(for: requestedModel)
    guard case .mlx(let modelId) = backend else { throw AnyLanguageModelServiceError.notAvailable }

    let amlTools: [any AnyLanguageModel.Tool] = tools
      .filter { self.shouldEnableTool($0, choice: toolChoice) }
      .map { self.toAMLTool($0) }

    let session = AnyLanguageModel.LanguageModelSession(
      model: AnyLanguageModel.MLXLanguageModel(modelId: modelId),
      tools: amlTools,
      instructions: nil
    )
    let options = AnyLanguageModel.GenerationOptions(
      sampling: nil,
      temperature: Double(parameters.temperature),
      maximumResponseTokens: parameters.maxTokens
    )

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
          if !delta.isEmpty {
            continuation.yield(delta)
          }
          previous = current
        }
        continuation.finish()
      } catch let error as AnyLanguageModel.LanguageModelSession.ToolCallError {
        if let inv = error.underlyingError as? ToolInvocationError {
          continuation.finish(
            throwing: ServiceToolInvocation(toolName: inv.toolName, jsonArguments: inv.jsonArguments)
          )
        } else {
          continuation.finish(throwing: error)
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return stream
  }

  // MARK: - Backend resolution & session factory

  private enum BackendModel {
    case system
    case mlx(modelId: String)
  }

  private func resolveBackend(for requested: String?) throws -> BackendModel {
    let trimmed = (requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    // Default / foundation → system model
    if trimmed.isEmpty
      || trimmed.caseInsensitiveCompare("default") == .orderedSame
      || trimmed.caseInsensitiveCompare("foundation") == .orderedSame
    {
      // Prefer installed MLX model when available on current OS
      if let first = ModelManager.installedModelNames().first,
        let found = ModelManager.findInstalledModel(named: first)
      {
        return .mlx(modelId: found.id)
      }
      #if canImport(AnyLanguageModel)
        if #available(macOS 26.0, *) {
          return .system
        }
      #endif
      throw AnyLanguageModelServiceError.notAvailable
    }

    // Try installed short name or full id
    if let found = ModelManager.findInstalledModel(named: trimmed) {
      return .mlx(modelId: found.id)
    }
    if trimmed.contains("/") {
      return .mlx(modelId: trimmed)
    }
    throw AnyLanguageModelServiceError.modelNotFound(trimmed)
  }

  private func makeSession(
    backend: BackendModel,
    tools: [any AnyLanguageModel.Tool]?
  ) throws -> LanguageModelSession {
    switch backend {
    case .system:
      throw AnyLanguageModelServiceError.notAvailable
    case .mlx(let modelId):
      let model = MLXLanguageModel(modelId: modelId)
      if let tools, !tools.isEmpty {
        return LanguageModelSession(model: model, tools: tools, instructions: nil)
      } else {
        return LanguageModelSession(model: model)
      }
    }
  }

  // MARK: - Tools bridging (OpenAI -> AnyLanguageModel Tool)

  #if canImport(AnyLanguageModel)
    private struct ToolInvocationError: Error { let toolName: String; let jsonArguments: String }

    private struct OpenAIToolAdapter: AnyLanguageModel.Tool {
      typealias Output = Never
      typealias Arguments = AnyLanguageModel.GeneratedContent

      let name: String
      let description: String
      let parameters: AnyLanguageModel.GenerationSchema
      var includesSchemaInInstructions: Bool { true }

      func call(arguments: AnyLanguageModel.GeneratedContent) async throws -> Never {
        let json = arguments.jsonString
        throw ToolInvocationError(toolName: name, jsonArguments: json)
      }
    }

    private func toAMLTool(_ tool: Tool) -> any AnyLanguageModel.Tool {
      let desc = tool.function.description ?? ""
      let schema: AnyLanguageModel.GenerationSchema = makeGenerationSchema(
        from: tool.function.parameters, toolName: tool.function.name, description: desc)
      return OpenAIToolAdapter(name: tool.function.name, description: desc, parameters: schema)
    }

    // Convert OpenAI JSON Schema (as JSONValue) to AnyLanguageModel GenerationSchema
    private func makeGenerationSchema(
      from parameters: JSONValue?,
      toolName: String,
      description: String?
    ) -> AnyLanguageModel.GenerationSchema {
      guard let parameters else {
        return AnyLanguageModel.GenerationSchema(type: AnyLanguageModel.GeneratedContent.self, description: description, properties: [])
      }
      if let root = dynamicSchema(from: parameters, name: toolName) {
        if let schema = try? AnyLanguageModel.GenerationSchema(root: root, dependencies: []) { return schema }
      }
      return AnyLanguageModel.GenerationSchema(type: AnyLanguageModel.GeneratedContent.self, description: description, properties: [])
    }

    // Build a DynamicGenerationSchema recursively from a minimal subset of JSON Schema
    private func dynamicSchema(from json: JSONValue, name: String) -> AnyLanguageModel.DynamicGenerationSchema? {
      switch json {
      case .object(let dict):
        if case .array(let enumVals)? = dict["enum"], case .string = enumVals.first {
          let choices: [String] = enumVals.compactMap { v in
            if case .string(let s) = v { return s } else { return nil }
          }
          return AnyLanguageModel.DynamicGenerationSchema(name: name, description: jsonStringOrNil(dict["description"]), anyOf: choices)
        }

        var typeString: String? = nil
        if let t = dict["type"] {
          switch t {
          case .string(let s): typeString = s
          case .array(let arr):
            typeString = arr.compactMap { v in if case .string(let s) = v, s != "null" { return s } else { return nil } }.first
          default: break
          }
        }

        let desc = jsonStringOrNil(dict["description"])
        switch typeString ?? "object" {
        case "string":
          return AnyLanguageModel.DynamicGenerationSchema(type: String.self)
        case "integer":
          return AnyLanguageModel.DynamicGenerationSchema(type: Int.self)
        case "number":
          return AnyLanguageModel.DynamicGenerationSchema(type: Double.self)
        case "boolean":
          return AnyLanguageModel.DynamicGenerationSchema(type: Bool.self)
        case "array":
          if let items = dict["items"], let itemSchema = dynamicSchema(from: items, name: name + "Item") {
            let minItems = jsonIntOrNil(dict["minItems"]) 
            let maxItems = jsonIntOrNil(dict["maxItems"]) 
            return AnyLanguageModel.DynamicGenerationSchema(arrayOf: itemSchema, minimumElements: minItems, maximumElements: maxItems)
          }
          return AnyLanguageModel.DynamicGenerationSchema(arrayOf: AnyLanguageModel.DynamicGenerationSchema(type: String.self), minimumElements: nil, maximumElements: nil)
        case "object": fallthrough
        default:
          var required: Set<String> = []
          if case .array(let reqArr)? = dict["required"] {
            required = Set(reqArr.compactMap { v in if case .string(let s) = v { return s } else { return nil } })
          }
          var properties: [AnyLanguageModel.DynamicGenerationSchema.Property] = []
          if case .object(let propsDict)? = dict["properties"] {
            for (propName, propSchemaJSON) in propsDict {
              let propSchema = dynamicSchema(from: propSchemaJSON, name: name + "." + propName) ?? AnyLanguageModel.DynamicGenerationSchema(type: String.self)
              let isOptional = !required.contains(propName)
              let prop = AnyLanguageModel.DynamicGenerationSchema.Property(
                name: propName,
                description: nil,
                schema: propSchema,
                isOptional: isOptional
              )
              properties.append(prop)
            }
          }
          return AnyLanguageModel.DynamicGenerationSchema(name: name, description: desc, properties: properties)
        }

      case .string:
        return AnyLanguageModel.DynamicGenerationSchema(type: String.self)
      case .number:
        return AnyLanguageModel.DynamicGenerationSchema(type: Double.self)
      case .bool:
        return AnyLanguageModel.DynamicGenerationSchema(type: Bool.self)
      case .array(let arr):
        if let first = arr.first, let item = dynamicSchema(from: first, name: name + "Item") {
          return AnyLanguageModel.DynamicGenerationSchema(arrayOf: item, minimumElements: nil, maximumElements: nil)
        }
        return AnyLanguageModel.DynamicGenerationSchema(arrayOf: AnyLanguageModel.DynamicGenerationSchema(type: String.self), minimumElements: nil, maximumElements: nil)
      case .null:
        return AnyLanguageModel.DynamicGenerationSchema(type: String.self)
      }
    }

    private func jsonStringOrNil(_ value: JSONValue?) -> String? {
      guard let value else { return nil }
      if case .string(let s) = value { return s }
      return nil
    }
    private func jsonIntOrNil(_ value: JSONValue?) -> Int? {
      guard let value else { return nil }
      switch value {
      case .number(let d): return Int(d)
      case .string(let s): return Int(s)
      default: return nil
      }
    }

    private func shouldEnableTool(_ tool: Tool, choice: ToolChoiceOption?) -> Bool {
      guard let choice else { return true }
      switch choice {
      case .auto: return true
      case .none: return false
      case .function(let n):
        return n.function.name == tool.function.name
      }
    }
  #endif
}


