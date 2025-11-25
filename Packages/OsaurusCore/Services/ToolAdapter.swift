//
//  ToolAdapter.swift
//  osaurus
//
//  Adapts OpenAI-style tool definitions to AnyLanguageModel's Tool protocol.
//

import AnyLanguageModel
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Tool Invocation Error

/// Error thrown when a tool is invoked, containing the tool name and arguments
/// This allows the caller to handle the tool call externally
public struct ToolInvocationRequest: Error, Sendable {
    public let toolName: String
    public let arguments: String  // JSON string of arguments

    public init(toolName: String, arguments: String) {
        self.toolName = toolName
        self.arguments = arguments
    }
}

// MARK: - Tool Adapter

#if canImport(FoundationModels)
    /// Adapter that wraps OpenAI tool definitions for use with AnyLanguageModel
    @available(macOS 26.0, *)
    public struct OpenAIToolAdapter: FoundationModels.Tool {
        public typealias Output = String
        public typealias Arguments = GeneratedContent

        public let name: String
        public let description: String
        public let parameters: GenerationSchema
        public var includesSchemaInInstructions: Bool { true }

        /// Initialize from an OpenAI Tool definition
        public init(from openAITool: Tool) {
            self.name = openAITool.function.name
            self.description = openAITool.function.description ?? ""
            self.parameters = Self.makeGenerationSchema(
                from: openAITool.function.parameters,
                toolName: openAITool.function.name,
                description: openAITool.function.description
            )
        }

        /// When called, throw an error with the tool name and arguments
        /// The caller should catch this and handle the tool invocation
        public func call(arguments: GeneratedContent) async throws -> String {
            let json = arguments.jsonString
            throw ToolInvocationRequest(toolName: name, arguments: json)
        }

        // MARK: - Schema Conversion

        /// Convert OpenAI JSON Schema to FoundationModels GenerationSchema
        private static func makeGenerationSchema(
            from parameters: JSONValue?,
            toolName: String,
            description: String?
        ) -> GenerationSchema {
            guard let parameters else {
                return GenerationSchema(
                    type: GeneratedContent.self,
                    description: description,
                    properties: []
                )
            }
            if let root = dynamicSchema(from: parameters, name: toolName) {
                if let schema = try? GenerationSchema(root: root, dependencies: []) {
                    return schema
                }
            }
            return GenerationSchema(type: GeneratedContent.self, description: description, properties: [])
        }

        /// Build a DynamicGenerationSchema recursively from JSON Schema
        private static func dynamicSchema(from json: JSONValue, name: String) -> DynamicGenerationSchema? {
            switch json {
            case .object(let dict):
                // Handle enum of strings
                if case .array(let enumVals)? = dict["enum"],
                    case .string = enumVals.first
                {
                    let choices: [String] = enumVals.compactMap { v in
                        if case .string(let s) = v { return s } else { return nil }
                    }
                    return DynamicGenerationSchema(
                        name: name,
                        description: jsonStringOrNil(dict["description"]),
                        anyOf: choices
                    )
                }

                // Determine type from schema
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
                    return DynamicGenerationSchema(type: String.self)
                case "integer":
                    return DynamicGenerationSchema(type: Int.self)
                case "number":
                    return DynamicGenerationSchema(type: Double.self)
                case "boolean":
                    return DynamicGenerationSchema(type: Bool.self)
                case "array":
                    if let items = dict["items"],
                        let itemSchema = dynamicSchema(from: items, name: name + "Item")
                    {
                        let minItems = jsonIntOrNil(dict["minItems"])
                        let maxItems = jsonIntOrNil(dict["maxItems"])
                        return DynamicGenerationSchema(
                            arrayOf: itemSchema,
                            minimumElements: minItems,
                            maximumElements: maxItems
                        )
                    }
                    return DynamicGenerationSchema(
                        arrayOf: DynamicGenerationSchema(type: String.self),
                        minimumElements: nil,
                        maximumElements: nil
                    )
                case "object": fallthrough
                default:
                    var required: Set<String> = []
                    if case .array(let reqArr)? = dict["required"] {
                        required = Set(
                            reqArr.compactMap { v in if case .string(let s) = v { return s } else { return nil } }
                        )
                    }
                    var properties: [DynamicGenerationSchema.Property] = []
                    if case .object(let propsDict)? = dict["properties"] {
                        for (propName, propSchemaJSON) in propsDict {
                            let propSchema =
                                dynamicSchema(from: propSchemaJSON, name: name + "." + propName)
                                ?? DynamicGenerationSchema(type: String.self)
                            let isOptional = !required.contains(propName)
                            let prop = DynamicGenerationSchema.Property(
                                name: propName,
                                description: nil,
                                schema: propSchema,
                                isOptional: isOptional
                            )
                            properties.append(prop)
                        }
                    }
                    return DynamicGenerationSchema(name: name, description: desc, properties: properties)
                }

            case .string:
                return DynamicGenerationSchema(type: String.self)
            case .number:
                return DynamicGenerationSchema(type: Double.self)
            case .bool:
                return DynamicGenerationSchema(type: Bool.self)
            case .array(let arr):
                if let first = arr.first, let item = dynamicSchema(from: first, name: name + "Item") {
                    return DynamicGenerationSchema(arrayOf: item, minimumElements: nil, maximumElements: nil)
                }
                return DynamicGenerationSchema(
                    arrayOf: DynamicGenerationSchema(type: String.self),
                    minimumElements: nil,
                    maximumElements: nil
                )
            case .null:
                return DynamicGenerationSchema(type: String.self)
            }
        }

        // MARK: - Helpers

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

    // MARK: - Tool Conversion Utilities

    @available(macOS 26.0, *)
    public enum ToolAdapterHelper {
        /// Convert an array of OpenAI tools to AnyLanguageModel-compatible tools
        public static func convertTools(_ openAITools: [Tool]) -> [any FoundationModels.Tool] {
            return openAITools.map { OpenAIToolAdapter(from: $0) }
        }

        /// Filter tools based on tool_choice option
        public static func filterTools(
            _ tools: [Tool],
            choice: ToolChoiceOption?
        ) -> [Tool] {
            guard let choice else { return tools }

            switch choice {
            case .auto:
                return tools
            case .none:
                return []
            case .function(let target):
                return tools.filter { $0.function.name == target.function.name }
            }
        }
    }
#endif

