# OpenAI API Compatible Endpoints

This guide explains how to use the OpenAI-compatible API endpoints in Osaurus.

## Available Endpoints

### 1. List Models - `GET /models`

Returns a list of available models that are currently downloaded and ready to use.

```bash
curl http://localhost:8080/models
```

Example response:

```json
{
  "object": "list",
  "data": [
    {
      "id": "llama-3.2-3b-instruct",
      "object": "model",
      "created": 1738193123,
      "owned_by": "osaurus"
    },
    {
      "id": "qwen2.5-7b-instruct",
      "object": "model",
      "created": 1738193123,
      "owned_by": "osaurus"
    }
  ]
}
```

### 2. Chat Completions - `POST /chat/completions`

Generate chat completions using the specified model.

#### Non-streaming Request

```bash
curl http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-3b-instruct",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "temperature": 0.7,
    "max_tokens": 150
  }'
```

Example response:

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1738193123,
  "model": "llama-3.2-3b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "I'm doing well, thank you for asking! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 15,
    "total_tokens": 35
  }
}
```

#### Streaming Request

```bash
curl http://localhost:8080/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-3b-instruct",
    "messages": [
      {"role": "user", "content": "Tell me a short story"}
    ],
    "stream": true,
    "temperature": 0.8,
    "max_tokens": 200
  }'
```

Streaming responses use Server-Sent Events (SSE) format:

```
data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1738193123,"model":"llama-3.2-3b-instruct","choices":[{"index":0,"delta":{"content":"Once"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1738193123,"model":"llama-3.2-3b-instruct","choices":[{"index":0,"delta":{"content":" upon"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1738193123,"model":"llama-3.2-3b-instruct","choices":[{"index":0,"delta":{"content":" a"},"finish_reason":null}]}

data: [DONE]
```

## Model Mapping

The following models from ModelManager are mapped to OpenAI-compatible names:

| Downloaded Model ID                              | API Model Name        |
| ------------------------------------------------ | --------------------- |
| mlx-community/Llama-3.2-3B-Instruct-4bit         | llama-3.2-3b-instruct |
| mlx-community/Llama-3.2-1B-Instruct-4bit         | llama-3.2-1b-instruct |
| mlx-community/Qwen2.5-7B-Instruct-4bit           | qwen2.5-7b-instruct   |
| mlx-community/Qwen2.5-3B-Instruct-4bit           | qwen2.5-3b-instruct   |
| mlx-community/gemma-2-9b-it-4bit                 | gemma-2-9b-instruct   |
| mlx-community/gemma-2-2b-it-4bit                 | gemma-2-2b-instruct   |
| mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit | deepseek-r1-1.5b      |
| mlx-community/OpenELM-3B-Instruct-4bit           | openelm-3b-instruct   |

## Usage with OpenAI Python Library

You can use the official OpenAI Python library with Osaurus:

```python
from openai import OpenAI

# Point to your local Osaurus server
client = OpenAI(
    base_url="http://localhost:8080",
    api_key="not-needed"  # Osaurus doesn't require authentication
)

# List available models
models = client.models.list()
for model in models.data:
    print(model.id)

# Create a chat completion
response = client.chat.completions.create(
    model="llama-3.2-3b-instruct",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of France?"}
    ],
    temperature=0.7,
    max_tokens=100
)

print(response.choices[0].message.content)

# Stream a response
stream = client.chat.completions.create(
    model="llama-3.2-3b-instruct",
    messages=[
        {"role": "user", "content": "Write a haiku about coding"}
    ],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content is not None:
        print(chunk.choices[0].delta.content, end="")
```

## Notes

1. **Model Availability**: Only models that have been downloaded through the Osaurus UI will be available via the API.

2. **Performance**: The first request to a model may take longer as the model needs to be loaded into memory.

3. **Memory Usage**: Models are cached in memory after loading. Use the ModelManager UI to manage which models are downloaded.

4. **GPU Acceleration**: MLX automatically uses Apple Silicon GPU acceleration when available.

5. **Context Length**: Each model has different context length limitations. Refer to the model documentation for specifics.

6. **Vision Models**: Vision-language models (VLMs) are supported but require special handling for image inputs (not yet implemented in the API).
