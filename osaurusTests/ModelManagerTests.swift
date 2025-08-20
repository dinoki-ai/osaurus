//
//  ModelManagerTests.swift
//  osaurusTests
//
//  Created by Assistant on 8/20/25.
//

import Foundation
import Testing
@testable import osaurus

struct ModelManagerTests {

    @Test func loadAvailableModels_initializesStates() async throws {
        // Redirect models directory to a temp location for isolation
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        let models = await MainActor.run { manager.availableModels }
        #expect(models.count > 0)

        let states = await MainActor.run { manager.downloadStates }
        for model in models {
            #expect(states[model.id] != nil)
        }

        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func cancelDownload_resetsStateWithoutTask() async throws {
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        let modelId = await MainActor.run { manager.availableModels.first!.id }

        await MainActor.run { manager.downloadStates[modelId] = .downloading(progress: 0.5) }
        await MainActor.run { manager.cancelDownload(modelId) }
        let state = await MainActor.run { manager.downloadStates[modelId] }
        #expect(state == .notStarted)

        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func downloadProgress_matchesState() async throws {
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        let modelId = await MainActor.run { manager.availableModels.first!.id }

        await MainActor.run { manager.downloadStates[modelId] = .notStarted }
        var p = await MainActor.run { manager.downloadProgress(for: modelId) }
        #expect(p == 0.0)

        await MainActor.run { manager.downloadStates[modelId] = .downloading(progress: 0.25) }
        p = await MainActor.run { manager.downloadProgress(for: modelId) }
        #expect(abs(p - 0.25) < 0.0001)

        await MainActor.run { manager.downloadStates[modelId] = .completed }
        p = await MainActor.run { manager.downloadProgress(for: modelId) }
        #expect(p == 1.0)

        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func totalDownloadedSize_zeroWhenNoneDownloaded() async throws {
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        await MainActor.run {
            for model in manager.availableModels {
                manager.downloadStates[model.id] = .notStarted
            }
        }
        let size = await MainActor.run { manager.totalDownloadedSize }
        #expect(size == 0)

        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func isDownloaded_true_whenRequiredFilesPresent() async throws {
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        let model = await MainActor.run { manager.availableModels.first! }
        let dir = model.localDirectory

        // Ensure a clean slate
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create required JSON files
        let jsons = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json"
        ]
        for name in jsons {
            let url = dir.appendingPathComponent(name)
            try Data("{}".utf8).write(to: url)
        }

        // Create at least one weights file
        let weights = dir.appendingPathComponent("model.safetensors")
        try Data().write(to: weights)

        // Sanity: files exist where expected
        let fm = FileManager.default
        for name in jsons { #expect(fm.fileExists(atPath: dir.appendingPathComponent(name).path)) }
        #expect(fm.fileExists(atPath: weights.path))
        if let items = try? fm.contentsOfDirectory(atPath: dir.path) {
            #expect(items.contains("config.json"))
            #expect(items.contains("tokenizer.json"))
            #expect(items.contains("tokenizer_config.json"))
            #expect(items.contains("special_tokens_map.json"))
            #expect(items.contains("model.safetensors"))
        }

        // Validate detection
        let result = model.isDownloaded
        #expect(result == true)

        // Cleanup
        try? FileManager.default.removeItem(at: dir)
        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func deleteModel_removesDirectoryAndResetsState() async throws {
        let previous = await MainActor.run { ModelManager.modelsDirectory }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run { ModelManager.modelsDirectory = tempDir }

        let manager = await MainActor.run { ModelManager() }
        let model = await MainActor.run { manager.availableModels.first! }
        let dir = model.localDirectory

        // Prepare directory with a dummy file
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("dummy".utf8).write(to: dir.appendingPathComponent("file.txt"))

        await MainActor.run { manager.downloadStates[model.id] = .completed }
        await MainActor.run { manager.deleteModel(model) }

        // Directory should no longer exist and state should reset
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists == false)

        let state = await MainActor.run { manager.downloadStates[model.id] }
        #expect(state == .notStarted)

        await MainActor.run { ModelManager.modelsDirectory = previous }
        try? FileManager.default.removeItem(at: tempDir)
    }
}


