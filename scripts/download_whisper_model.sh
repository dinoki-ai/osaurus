#!/bin/bash

# Script to download Whisper model for osaurus app
# Models available: tiny, base, small, medium, large

MODEL_NAME="base"  # Change this to use a different model
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL_NAME}.bin"
RESOURCES_DIR="../osaurus/Resources"
MODEL_FILE="ggml-${MODEL_NAME}.bin"

echo "🎤 Downloading Whisper model: ${MODEL_NAME}"
echo "This may take a few minutes..."

# Create Resources directory if it doesn't exist
mkdir -p "${RESOURCES_DIR}"

# Download the model
curl -L "${MODEL_URL}" -o "${RESOURCES_DIR}/${MODEL_FILE}"

if [ $? -eq 0 ]; then
    echo "✅ Model downloaded successfully!"
    echo "📁 Location: ${RESOURCES_DIR}/${MODEL_FILE}"
    echo ""
    echo "Next steps:"
    echo "1. Add the model file to your Xcode project:"
    echo "   - Drag ${MODEL_FILE} from Finder into your Xcode project"
    echo "   - Make sure 'Copy items if needed' is checked"
    echo "   - Add to target: osaurus"
    echo ""
    echo "2. The WhisperController will automatically look for this model in the bundle"
else
    echo "❌ Failed to download model"
    exit 1
fi
