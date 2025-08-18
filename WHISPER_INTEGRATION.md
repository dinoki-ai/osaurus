# Whisper Integration Guide

This guide explains how to complete the Whisper speech recognition integration in your osaurus app.

## ✅ What's Been Done

1. **Created Local Whisper Package**

   - Located at `vendors/Whisper/`
   - Contains the XCFramework binary target

2. **Added WhisperController**

   - Handles speech recognition functionality
   - Located at `osaurus/Controllers/WhisperController.swift`

3. **Updated Router**

   - Added `/transcribe` and `/transcribe/status` endpoints
   - Ready for audio file handling

4. **Created Model Download Script**
   - Located at `Scripts/download_whisper_model.sh`

## 📋 Next Steps

### 1. Add the Whisper Package to Xcode

1. Open `osaurus.xcodeproj` in Xcode
2. Select the project in the navigator
3. Go to "Package Dependencies" tab
4. Click "+" → "Add Local..."
5. Navigate to `vendors/Whisper`
6. Add the package

### 2. Link WhisperFramework to Your Target

1. Select your "osaurus" target
2. Go to "General" tab
3. Under "Frameworks, Libraries, and Embedded Content"
4. Click "+" and add "WhisperFramework"

### 3. Download the Whisper Model

```bash
cd Scripts
./download_whisper_model.sh
```

Then add the downloaded `ggml-base.bin` file to your Xcode project.

### 4. Update HTTPHandler for File Uploads

The current HTTPHandler needs to be updated to handle multipart/form-data for audio file uploads. This will allow the `/transcribe` endpoint to receive audio files.

### 5. Test the Integration

Once everything is set up, you can test the transcription:

```bash
# Check status
curl http://localhost:8080/transcribe/status

# Upload an audio file (after implementing file upload handling)
curl -X POST -F "audio=@test.wav" http://localhost:8080/transcribe
```

## 🎤 Using WhisperController in Your App

```swift
// Example usage in your app
let whisperController = WhisperController()

// Transcribe from file
await whisperController.transcribeAudio(from: audioFileURL)

// Access the transcribed text
let text = whisperController.transcribedText
```

**Important Note**: The whisper module uses C API naming conventions. When importing the framework, use:

```swift
import whisper  // lowercase module name
```

The controller now properly uses the C API functions like `whisper_init_from_file_with_params()` and `whisper_full()`.

## 📝 Notes

- The base model provides a good balance between speed and accuracy
- Larger models (small, medium, large) provide better accuracy but require more resources
- The first transcription may take longer as the model initializes
- Supported audio formats: WAV, MP3, M4A (may require additional audio processing)

## 🔧 Troubleshooting

If you encounter issues:

1. **Model not found**: Ensure the model file is added to your app bundle
2. **Framework not found**: Check that WhisperFramework is properly linked
3. **Transcription fails**: Verify audio format is supported and file is valid

For more information about Whisper.cpp, visit: https://github.com/ggerganov/whisper.cpp
