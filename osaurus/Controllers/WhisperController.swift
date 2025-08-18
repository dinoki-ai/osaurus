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
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var currentModelPath: String?
    @Published var isModelLoaded = false
    @Published var isRealTimeTranscription = false
    @Published var realTimeTranscribedText = ""
    
    // Real-time transcription properties
    private var audioBuffer: [Float] = []
    private var audioBufferLock = NSLock()
    private var lastProcessedSampleCount = 0
    private var realTimeTimer: Timer?
    private let processingInterval: TimeInterval = 2.0 // Process every 2 seconds
    private let minAudioLength: TimeInterval = 0.5 // Minimum audio length to process
    
    private var ctx: OpaquePointer? = nil
    private var audioEngine: AVAudioEngine?
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    init() {
        // Don't load any model by default
    }

    func loadModel(at path: String) {
        // Free existing context if any
        if let ctx = ctx {
            whisper_free(ctx)
            self.ctx = nil
            isModelLoaded = false
        }
        
        guard !path.isEmpty else {
            errorMessage = "Model path is empty."
            currentModelPath = nil
            return
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Model file not found at path: \(path)"
            currentModelPath = nil
            return
        }
        
        currentModelPath = path
        setupWhisper()
    }

    private func setupWhisper() {
        guard let modelPath = currentModelPath, !modelPath.isEmpty else {
            errorMessage = "No model path set."
            isModelLoaded = false
            return
        }
        
        ctx = modelPath.withCString { whisper_init_from_file($0) }
        if ctx == nil {
            errorMessage = "Failed to initialize Whisper context."
            isModelLoaded = false
        } else {
            print("[Whisper] Initialized with model at: \(modelPath)")
            errorMessage = nil
            isModelLoaded = true
        }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    // MARK: - Public
    
    func toggleRealTimeTranscription() {
        isRealTimeTranscription.toggle()
        print("[Real-time] Toggled real-time transcription: \(isRealTimeTranscription)")
        if !isRealTimeTranscription {
            // Clear real-time text when disabling
            realTimeTranscribedText = ""
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        
        // Check if model is loaded
        guard isModelLoaded else {
            errorMessage = "Please download and select a model first."
            return
        }
        
        // Request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.errorMessage = "Microphone access denied. Please enable microphone access in System Preferences."
                }
                return
            }
            
            Task { @MainActor in
                self?.setupRecording()
            }
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // Close the recording file to ensure all audio is flushed to disk
        recordingFile = nil
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop real-time processing
        realTimeTimer?.invalidate()
        realTimeTimer = nil
        
        isRecording = false
        recordingTime = 0
        
        if isRealTimeTranscription {
            print("[Real-time] Stopping real-time mode, processing final buffer")
            
            // Process any remaining audio in the buffer
            await processRealTimeAudioBuffer(isFinal: true)
            
            // Move real-time transcription to final transcription
            transcribedText = realTimeTranscribedText
            print("[Real-time] Final transcription: '\(transcribedText)'")
            
            // Clear buffer
            audioBufferLock.lock()
            audioBuffer.removeAll()
            lastProcessedSampleCount = 0
            audioBufferLock.unlock()
        } else {
            // Regular transcription mode - transcribe the entire recorded audio
            if let recordingURL = recordingURL {
                // Give the system a brief moment to finalize the file on disk
                try? await Task.sleep(nanoseconds: 150_000_000)
                await transcribeAudio(from: recordingURL)
                
                // Clean up the temporary file
                try? FileManager.default.removeItem(at: recordingURL)
                self.recordingURL = nil
            }
        }
    }
    
    private func setupRecording() {
        do {
            // Create a temporary file for recording
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "recording_\(Date().timeIntervalSince1970).wav"
            recordingURL = tempDir.appendingPathComponent(fileName)
            
            guard let recordingURL = recordingURL else { return }
            
            // Setup audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            // Create file for writing
            recordingFile = try AVAudioFile(forWriting: recordingURL,
                                          settings: inputFormat.settings,
                                          commonFormat: inputFormat.commonFormat,
                                          interleaved: inputFormat.isInterleaved)
            
            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                // Always write to file for backup
                if let recordingFile = self.recordingFile {
                    do {
                        try recordingFile.write(from: buffer)
                    } catch {
                        Task { @MainActor in
                            self.errorMessage = "Recording error: \(error.localizedDescription)"
                        }
                    }
                }
                
                // If real-time transcription is enabled, convert and add to buffer
                if self.isRealTimeTranscription {
                    // Convert buffer to mono 16kHz for Whisper
                    let convertedSamples = self.convertBufferToMono16k(buffer)
                    
                    if !convertedSamples.isEmpty {
                        self.audioBufferLock.lock()
                        self.audioBuffer.append(contentsOf: convertedSamples)
                        let currentBufferSize = self.audioBuffer.count
                        self.audioBufferLock.unlock()
                        
                        // Debug logging
                        if currentBufferSize % 16000 == 0 { // Log every second of audio
                            print("[Real-time] Buffer size: \(currentBufferSize) samples (\(currentBufferSize/16000) seconds)")
                        }
                    }
                }
            }
            
            // Start the engine
            try audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            recordingStartTime = Date()
            
            // Start timer to update recording time
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                Task { @MainActor in
                    self.recordingTime = Date().timeIntervalSince(startTime)
                }
            }
            
            // Start real-time processing timer if enabled
            if isRealTimeTranscription {
                print("[Real-time] Starting real-time transcription mode")
                realTimeTranscribedText = ""
                lastProcessedSampleCount = 0
                audioBuffer.removeAll()
                
                // Ensure timer is scheduled on main run loop
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.realTimeTimer = Timer.scheduledTimer(withTimeInterval: self.processingInterval, repeats: true) { _ in
                        print("[Real-time] Timer fired")
                        Task {
                            await self.processRealTimeAudioBuffer(isFinal: false)
                        }
                    }
                    print("[Real-time] Timer scheduled with interval: \(self.processingInterval)s")
                }
            }
            
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func clearTranscription() {
        transcribedText = ""
        realTimeTranscribedText = ""
        errorMessage = nil
    }
    
    func transcribeAudio(from url: URL, language: String? = "en", translateToEnglish: Bool = false) async {
        guard let ctx else {
            errorMessage = "Whisper context not initialized. Please download and select a model."
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
        
        // Guard against empty recordings
        if file.length == 0 {
            throw NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recorded file is empty (no audio captured)"])
        }

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
    
    // MARK: - Real-time transcription helpers
    
    /// Convert audio buffer to mono 16kHz Float32 for real-time processing
    private func convertBufferToMono16k(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let inFormat = buffer.format
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16_000,
                                     channels: 1,
                                     interleaved: false)!
        
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else { 
            print("[Real-time] Failed to create audio converter")
            return [] 
        }
        
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1.0)
        
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else { 
            print("[Real-time] Failed to create output buffer")
            return [] 
        }
        
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error { 
            print("[Real-time] Conversion error: \(error)")
            return [] 
        }
        
        guard let ch0 = outBuffer.floatChannelData?.pointee else { 
            print("[Real-time] No float channel data")
            return [] 
        }
        
        let count = Int(outBuffer.frameLength)
        print("[Real-time] Converted \(buffer.frameLength) frames to \(count) frames")
        return Array(UnsafeBufferPointer(start: ch0, count: count))
    }
    
    /// Process accumulated audio buffer for real-time transcription
    private func processRealTimeAudioBuffer(isFinal: Bool) async {
        guard let ctx else { 
            print("[Real-time] No whisper context")
            return 
        }
        
        audioBufferLock.lock()
        let sampleCount = audioBuffer.count
        audioBufferLock.unlock()
        
        print("[Real-time] Processing buffer: \(sampleCount) samples, last processed: \(lastProcessedSampleCount)")
        
        // Check if we have enough new samples to process (at least minAudioLength seconds)
        let newSamples = sampleCount - lastProcessedSampleCount
        let newDuration = Double(newSamples) / 16_000.0 // 16kHz sample rate
        
        if newDuration < minAudioLength && !isFinal {
            print("[Real-time] Not enough new audio: \(newDuration)s (need \(minAudioLength)s)")
            return
        }
        
        // Get a copy of the audio buffer
        audioBufferLock.lock()
        let pcm = Array(audioBuffer)
        audioBufferLock.unlock()
        
        if pcm.isEmpty { return }
        
        // Process with Whisper
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_timestamps = true
        
        // Use English by default for real-time
        let lang = "en"
        let langCStr = strdup(lang)
        defer {
            if let ptr = langCStr {
                free(ptr)
            }
        }
        
        if let langPtr = langCStr {
            params.language = UnsafePointer(langPtr)
        }
        
        let rc = pcm.withUnsafeBufferPointer { buf -> Int32 in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        
        print("[Real-time] Whisper processing result: \(rc)")
        
        if rc == 0 {
            // Collect all segments - for real-time, we'll just replace the entire text
            var fullText = ""
            let n = whisper_full_n_segments(ctx)
            
            print("[Real-time] Found \(n) segments")
            
            // Get all segments
            for i in 0..<n {
                if let cstr = whisper_full_get_segment_text(ctx, i) {
                    let text = String(cString: cstr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let segmentTime = whisper_full_get_segment_t0(ctx, i)
                        print("[Real-time] Segment \(i) at \(segmentTime)s: '\(text)'")
                        fullText += text + " "
                    }
                }
            }
            
            // Update the UI with the complete transcription
            if !fullText.isEmpty {
                let finalText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Real-time] Full transcription: '\(finalText)'")
                await MainActor.run {
                    self.realTimeTranscribedText = finalText
                    print("[Real-time] Updated UI with text length: \(self.realTimeTranscribedText.count)")
                }
            } else {
                print("[Real-time] No text found in segments")
            }
            
            // Keep only recent audio in buffer to prevent memory growth
            if sampleCount > 16_000 * 60 { // Keep last 60 seconds
                audioBufferLock.lock()
                let samplesToKeep = 16_000 * 30 // Keep 30 seconds
                audioBuffer = Array(audioBuffer.suffix(samplesToKeep))
                lastProcessedSampleCount = audioBuffer.count
                audioBufferLock.unlock()
            }
        }
    }
}