//
//  WhisperModel.swift
//  osaurus
//
//  Model representing Whisper model metadata
//

import Foundation

struct WhisperModel: Identifiable, Codable {
    let id: String
    let name: String
    let displayName: String
    let size: String // e.g., "tiny", "base", "small", "medium", "large"
    let downloadSize: Int64 // Size in bytes
    let description: String
    
    var fileName: String {
        "ggml-\(size).bin"
    }
    
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
    
    // Available Whisper models with their metadata
    static let availableModels: [WhisperModel] = [
        WhisperModel(
            id: "whisper-tiny",
            name: "tiny",
            displayName: "Tiny",
            size: "tiny",
            downloadSize: 39_000_000, // ~39 MB
            description: "Fastest, least accurate. Good for quick transcriptions."
        ),
        WhisperModel(
            id: "whisper-base",
            name: "base",
            displayName: "Base",
            size: "base",
            downloadSize: 142_000_000, // ~142 MB
            description: "Balanced speed and accuracy. Recommended for most use cases."
        ),
        WhisperModel(
            id: "whisper-small",
            name: "small",
            displayName: "Small",
            size: "small",
            downloadSize: 466_000_000, // ~466 MB
            description: "Better accuracy, slower processing. Good for detailed transcriptions."
        ),
        WhisperModel(
            id: "whisper-medium",
            name: "medium",
            displayName: "Medium",
            size: "medium",
            downloadSize: 1_457_000_000, // ~1.5 GB
            description: "High accuracy, slower processing. For professional use."
        ),
        WhisperModel(
            id: "whisper-large",
            name: "large",
            displayName: "Large",
            size: "large",
            downloadSize: 2_889_000_000, // ~2.9 GB
            description: "Best accuracy, slowest processing. For critical transcriptions."
        )
    ]
}

// Extension for formatting file sizes
extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
