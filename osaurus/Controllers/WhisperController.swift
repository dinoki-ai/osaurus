//
//  WhisperController.swift
//  osaurus
//
//  Controller for handling speech recognition using Whisper

import Foundation
import AVFoundation
import whisper

@MainActor
final class WhisperController: ObservableObject {
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?

    private var ctx: OpaquePointer? = nil
    private let modelPath: String

    init(modelPath: String = Bundle.main.path(forResource: "ggml-base", ofType: "bin") ?? "") {
        self.modelPath = modelPath
        setupWhisper()
    }

    private func setupWhisper() {
        guard !modelPath.isEmpty else {
            errorMessage = "Model file not found in bundle."
            return
        }
        ctx = modelPath.withCString { whisper_init_from_file($0) }
        if ctx == nil {
            errorMessage = "Failed to initialize Whisper context."
        } else {
            print("[Whisper] Initialized with model at: \(modelPath)")
        }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    // MARK: - Public

    func transcribeAudio(from url: URL, language: String? = "en", translateToEnglish: Bool = false) async {
        guard let ctx else {
            errorMessage = "Whisper context not initialized"
            return
        }
        isProcessing = true
        errorMessage = nil
        do {
            let pcm = try Self.loadFileAsMono16kFloat32(url: url) // [Float]
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = true
            params.translate = translateToEnglish
            
            // Handle language parameter with proper memory management
            var langCStr: UnsafeMutablePointer<CChar>? = nil
            if let lang = language {
                langCStr = strdup(lang)
                if let langPtr = langCStr {
                    params.language = UnsafePointer(langPtr)
                }
            }
            
            // Ensure we free the allocated memory in a defer block
            defer {
                if let ptr = langCStr {
                    free(ptr)
                }
            }

            let rc = pcm.withUnsafeBufferPointer { buf -> Int32 in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            if rc != 0 {
                throw NSError(domain: "Whisper", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "whisper_full failed (\(rc))"])
            }

            // collect segments
            var text = ""
            let n = whisper_full_n_segments(ctx)
            for i in 0..<n {
                if let cstr = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: cstr)
                }
            }
            await MainActor.run {
                self.transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }

    // MARK: - Audio helpers

    /// Decode any file CoreAudio can read, convert to mono 16 kHz Float32, return samples
    private static func loadFileAsMono16kFloat32(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat

        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16_000,
                                      channels: 1,
                                      interleaved: false)!

        let converter = AVAudioConverter(from: inFormat, to: outFormat)!
        let frameCount = AVAudioFrameCount(file.length)
        let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount)!
        try file.read(into: inBuffer)

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1.0)
        let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames)!

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }

        guard let ch0 = outBuffer.floatChannelData?.pointee else { return [] }
        let count = Int(outBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: ch0, count: count))
    }
}