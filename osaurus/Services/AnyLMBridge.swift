//
//  AnyLMBridge.swift
//  osaurus
//
//  Bridges OpenAI-style tool specs to AnyLanguageModel tools and schemas.
//

import AnyLanguageModel
import Foundation

// Shared error thrown when a model requests a tool invocation
struct ServiceToolInvocation: Error, Sendable {
  let toolName: String
  let jsonArguments: String
}

/// Internal bridge utilities for AnyLanguageModel
enum AnyLMBridge {

  // MARK: - Tool selection

  static func shouldEnableTool(_ tool: Tool, choice: ToolChoiceOption?) -> Bool {
    guard let choice else { return true }
    switch choice {
    case .auto: return true
    case .none: return false
    case .function(let n):
      return n.function.name == tool.function.name
    }
  }

  // MARK: - OpenAI -> AnyLanguageModel tool adapter

  private struct ToolInvocationError: Error {
    let toolName: String
    let jsonArguments: String
  }

  private struct OpenAIToolAdapter: AnyLanguageModel.Tool {
    typealias Output = AnyLanguageModel.GeneratedContent
    typealias Arguments = AnyLanguageModel.GeneratedContent

    let name: String
    let description: String
    let parameters: AnyLanguageModel.GenerationSchema
    var includesSchemaInInstructions: Bool { true }

    func call(arguments: AnyLanguageModel.GeneratedContent) async throws
      -> AnyLanguageModel.GeneratedContent
    {
      let json = arguments.jsonString
      throw ToolInvocationError(toolName: name, jsonArguments: json)
    }
  }

  private static func toAnyLMTool(_ tool: Tool) -> any AnyLanguageModel.Tool {
    let desc = tool.function.description ?? ""
    let schema: AnyLanguageModel.GenerationSchema = makeGenerationSchema(
      from: tool.function.parameters,
      toolName: tool.function.name,
      description: desc
    )
    return OpenAIToolAdapter(name: tool.function.name, description: desc, parameters: schema)
  }

  // Build bridged tools honoring tool_choice (auto/none/function)
  static func bridgedTools(from tools: [Tool], choice: ToolChoiceOption?) -> [any AnyLanguageModel
    .Tool]
  {
    let filtered: [Tool] = {
      guard let choice else { return tools }
      switch choice {
      case .auto: return tools
      case .none: return []
      case .function(let fn):
        return tools.filter { $0.function.name == fn.function.name }
      }
    }()
    return filtered.map { toAnyLMTool($0) }
  }

  // Translate AnyLanguageModel ToolCallError into our shared ServiceToolInvocation
  static func mapToolCallError(_ error: Error) -> ServiceToolInvocation? {
    if let toolError = error as? LanguageModelSession.ToolCallError,
      let inv = toolError.underlyingError as? ToolInvocationError
    {
      return ServiceToolInvocation(toolName: inv.toolName, jsonArguments: inv.jsonArguments)
    }
    return nil
  }

  // MARK: - JSON Schema -> GenerationSchema (minimal subset)

  static func makeGenerationSchema(
    from parameters: JSONValue?,
    toolName: String,
    description: String?
  ) -> AnyLanguageModel.GenerationSchema {
    guard let parameters else {
      return AnyLanguageModel.GenerationSchema(
        type: AnyLanguageModel.GeneratedContent.self,
        description: description,
        properties: []
      )
    }
    if let root = dynamicSchema(from: parameters, name: toolName) {
      if let schema = try? AnyLanguageModel.GenerationSchema(root: root, dependencies: []) {
        return schema
      }
    }
    return AnyLanguageModel.GenerationSchema(
      type: AnyLanguageModel.GeneratedContent.self,
      description: description,
      properties: []
    )
  }

  static func dynamicSchema(from json: JSONValue, name: String) -> AnyLanguageModel
    .DynamicGenerationSchema?
  {
    switch json {
    case .object(let dict):
      // enum of strings
      if case .array(let enumVals)? = dict["enum"], case .string = enumVals.first {
        let choices: [String] = enumVals.compactMap { v in
          if case .string(let s) = v { return s } else { return nil }
        }
        return AnyLanguageModel.DynamicGenerationSchema(
          name: name,
          description: jsonStringOrNil(dict["description"]),
          anyOf: choices
        )
      }

      // type can be string or array
      var typeString: String? = nil
      if let t = dict["type"] {
        switch t {
        case .string(let s): typeString = s
        case .array(let arr):
          typeString =
            arr.compactMap { v in
              if case .string(let s) = v, s != "null" { return s } else { return nil }
            }.first
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
        if let items = dict["items"],
          let itemSchema = dynamicSchema(from: items, name: name + "Item")
        {
          let minItems = jsonIntOrNil(dict["minItems"])
          let maxItems = jsonIntOrNil(dict["maxItems"])
          return AnyLanguageModel.DynamicGenerationSchema(
            arrayOf: itemSchema,
            minimumElements: minItems,
            maximumElements: maxItems
          )
        }
        // Fallback to array of strings
        return AnyLanguageModel.DynamicGenerationSchema(
          arrayOf: AnyLanguageModel.DynamicGenerationSchema(type: String.self),
          minimumElements: nil,
          maximumElements: nil
        )
      case "object": fallthrough
      default:
        // Build object properties
        var required: Set<String> = []
        if case .array(let reqArr)? = dict["required"] {
          required = Set(
            reqArr.compactMap { v in if case .string(let s) = v { return s } else { return nil } })
        }
        var properties: [AnyLanguageModel.DynamicGenerationSchema.Property] = []
        if case .object(let propsDict)? = dict["properties"] {
          for (propName, propSchemaJSON) in propsDict {
            let propSchema =
              dynamicSchema(from: propSchemaJSON, name: name + "." + propName)
              ?? AnyLanguageModel.DynamicGenerationSchema(type: String.self)
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
        return AnyLanguageModel.DynamicGenerationSchema(
          name: name, description: desc, properties: properties)
      }

    case .string:
      return AnyLanguageModel.DynamicGenerationSchema(type: String.self)
    case .number:
      return AnyLanguageModel.DynamicGenerationSchema(type: Double.self)
    case .bool:
      return AnyLanguageModel.DynamicGenerationSchema(type: Bool.self)
    case .array(let arr):
      if let first = arr.first, let item = dynamicSchema(from: first, name: name + "Item") {
        return AnyLanguageModel.DynamicGenerationSchema(
          arrayOf: item, minimumElements: nil, maximumElements: nil)
      }
      return AnyLanguageModel.DynamicGenerationSchema(
        arrayOf: AnyLanguageModel.DynamicGenerationSchema(type: String.self),
        minimumElements: nil,
        maximumElements: nil
      )
    case .null:
      return AnyLanguageModel.DynamicGenerationSchema(type: String.self)
    }
  }

  private static func jsonStringOrNil(_ value: JSONValue?) -> String? {
    guard let value else { return nil }
    if case .string(let s) = value { return s }
    return nil
  }

  private static func jsonIntOrNil(_ value: JSONValue?) -> Int? {
    guard let value else { return nil }
    switch value {
    case .number(let d): return Int(d)
    case .string(let s): return Int(s)
    default: return nil
    }
  }
}
