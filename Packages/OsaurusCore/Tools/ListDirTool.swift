//
//  ListDirTool.swift
//  osaurus
//
//  Implements list_dir tool: list contents of a directory.
//

import Foundation

struct ListDirTool: OsaurusTool {
    let name: String = "list_dir"
    let description: String =
        "List files and directories at a specified path. Returns a summary plus JSON payload of entries."

    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Target directory path. Supports ~ expansion."),
                ])
            ]),
            "required": .array([.string("path")]),
        ])
    }

    func execute(argumentsJSON: String) async throws -> String {
        let args =
            (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]

        let expandedPath = Self.resolvePath((args["path"] as? String) ?? "")
        guard !expandedPath.isEmpty else {
            return Self.failureResult(reason: "Missing or empty path", path: nil)
        }
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return Self.failureResult(reason: "Path does not exist", path: url.path)
        }
        guard isDir.boolValue else {
            return Self.failureResult(reason: "Path is not a directory", path: url.path)
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let entries = contents.map { url -> [String: Any] in
                var entry: [String: Any] = ["name": url.lastPathComponent]
                if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                    let isDirectory = resourceValues.isDirectory
                {
                    entry["type"] = isDirectory ? "directory" : "file"
                } else {
                    entry["type"] = "unknown"
                }
                return entry
            }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }

            let payload: [String: Any] = [
                "pathResolved": url.path,
                "entries": entries,
                "count": entries.count,
            ]

            let json =
                (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

            let summary = "Listed \(entries.count) entries in \(url.path)"
            return summary + "\n" + json

        } catch {
            return Self.failureResult(reason: "Failed to list directory: \(error.localizedDescription)", path: url.path)
        }
    }

    // MARK: - Helpers
    private static func resolvePath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if path.hasPrefix("~") {
            let home = NSHomeDirectory()
            if path == "~" { return home }
            let idx = path.index(after: path.startIndex)
            return home + String(path[idx...])
        }
        return path
    }

    private static func failureResult(reason: String, path: String?) -> String {
        let summary = "List dir failed: \(reason)"
        var dict: [String: Any] = ["error": reason]
        if let p = path { dict["path"] = p }
        let data =
            (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return summary + "\n" + json
    }
}
