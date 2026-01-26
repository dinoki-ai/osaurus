//
//  ToolDetection.swift
//  osaurus
//
//  Best-effort detection of inline tool-call JSON in generated text.
//

import Foundation

enum ToolDetection {
    // MARK: - Configuration

    /// Max characters to scan backwards for tool calls.
    /// Matched to StreamAccumulator.maxBufferSize to ensure we can detect large tool calls.
    private static let maxScanWindow = 45_000

    /// Max characters to search when finding the enclosing JSON object.
    private static let maxJSONSearchLimit = 10_000

    /// Best-effort detector for inline tool-call JSON in generated text. Returns (toolName, argsJSON).
    static func detectInlineToolCall(
        in text: String,
        tools: [Tool]
    ) -> (String, String)? {
        guard !tools.isEmpty, !text.isEmpty else { return nil }

        let window = String(text.suffix(maxScanWindow))
        let toolNames = Set(tools.map { $0.function.name })

        for name in toolNames {
            let pattern = #""(?:tool_)?name"\s*:\s*"\#(name)""#

            // Search backwards from the end of the string.
            // The valid tool call is most likely the last thing generated.
            // This avoids scanning through earlier "thought process" mentions unnecessarily.
            var searchRange = window.startIndex ..< window.endIndex

            while let range = window.range(of: pattern, options: [.regularExpression, .backwards], range: searchRange) {
                // Check if this name occurrence is inside a valid JSON object
                if let jsonRange = findEnclosingJSONObject(around: range.lowerBound, in: window) {
                    let candidate = String(window[jsonRange])
                    if let (detectedName, argsJSON) = extractToolCall(fromJSON: candidate) {
                        if toolNames.contains(detectedName) {
                            return (detectedName, argsJSON)
                        }
                    }
                }

                // Continue searching backwards for other occurrences
                if range.lowerBound > window.startIndex {
                    searchRange = window.startIndex ..< range.lowerBound
                } else {
                    break
                }
            }
        }
        return nil
    }

    /// Locate the smallest JSON object enclosing a character index.
    private static func findEnclosingJSONObject(
        around index: String.Index,
        in text: String
    ) -> Range<String.Index>? {
        var startPositions: [String.Index] = []
        var i = index

        // Scan backwards for opening braces
        while i > text.startIndex {
            i = text.index(before: i)
            if text[i] == "{" { startPositions.append(i) }
            if startPositions.count > maxJSONSearchLimit { break }
        }

        // Try to match closing braces for each candidate start
        for start in startPositions {
            if let end = matchJSONObjectEnd(from: start, in: text) {
                if start <= index && index < end { return start ..< end }
            }
        }
        return nil
    }

    /// Return index just after the end of the JSON object that starts at `start`.
    private static func matchJSONObjectEnd(
        from start: String.Index,
        in text: String
    ) -> String.Index? {
        var depth = 0
        var inString = false
        var isEscaped = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return text.index(after: i)
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// Attempt to parse a tool-call from JSON text. Supports {"function":{"name":...,"arguments":...}}
    /// and {"tool_name":..., "arguments": ...}. Returns (toolName, argsJSON) if found.
    private static func extractToolCall(fromJSON jsonText: String) -> (String, String)? {
        guard let data = jsonText.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let function = obj["function"] as? [String: Any], let name = function["name"] as? String {
            if let argsString = function["arguments"] as? String {
                return (name, argsString)
            }
            if let argsObj = function["arguments"],
                let argsData = try? JSONSerialization.data(withJSONObject: argsObj),
                let argsJSON = String(data: argsData, encoding: .utf8)
            {
                return (name, argsJSON)
            }
        }
        if let name = obj["tool_name"] as? String {
            if let argsString = obj["arguments"] as? String {
                return (name, argsString)
            }
            if let argsObj = obj["arguments"],
                let argsData = try? JSONSerialization.data(withJSONObject: argsObj),
                let argsJSON = String(data: argsData, encoding: .utf8)
            {
                return (name, argsJSON)
            }
        }
        if let name = obj["name"] as? String {
            if let argsString = obj["arguments"] as? String { return (name, argsString) }
            if let argsObj = obj["arguments"],
                let argsData = try? JSONSerialization.data(withJSONObject: argsObj),
                let argsJSON = String(data: argsData, encoding: .utf8)
            {
                return (name, argsJSON)
            }
        }
        return nil
    }
}
