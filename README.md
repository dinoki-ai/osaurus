# Osaurus 🦕

A lightweight macOS server application built with SwiftUI and SwiftNIO, featuring a menu bar interface for easy server management.

## Project Structure

```
osaurus/
├── Core/                  # Core application files
│   ├── AppDelegate.swift  # macOS app delegate
│   └── osaurusApp.swift   # Main SwiftUI app entry point
├── Controllers/           # View controllers and business logic
│   ├── ServerController.swift  # Main server lifecycle controller
│   └── ModelManager.swift      # MLX model download manager
├── Models/               # Data models
│   ├── ServerConfiguration.swift  # Server configuration settings
│   ├── ServerHealth.swift        # Server health state enum
│   ├── MLXModel.swift            # MLX model definitions
│   └── OpenAIAPI.swift           # OpenAI API structures
├── Networking/           # Network layer components
│   ├── HTTPHandler.swift         # SwiftNIO HTTP request handler
│   ├── Router.swift              # HTTP request router
│   └── AsyncHTTPHandler.swift    # Async handler for streaming
├── Services/             # Service layer
│   └── MLXService.swift          # MLX model loading and inference
├── Views/               # SwiftUI views
│   ├── ContentView.swift         # Main window view
│   ├── MenuBarControllerView.swift  # Menu bar UI
│   └── ModelDownloadView.swift   # Model download interface
└── osaurus.entitlements  # App entitlements
```

## Features

- **Menu Bar Control**: Quick server management from the macOS menu bar
- **SwiftNIO Based**: High-performance HTTP server using SwiftNIO
- **Health Monitoring**: Built-in health check endpoint
- **Clean Architecture**: Well-organized code with separation of concerns
- **MLX Model Support**: Download and manage Apple MLX models for local AI inference
- **OpenAI API Compatibility**: Compatible with OpenAI API clients and libraries

## API Endpoints

- `GET /` - Root endpoint, returns server status
- `GET /health` - Health check endpoint with JSON response
- `POST /echo` - Echo endpoint for testing
- `GET /models` - List available MLX models (OpenAI-compatible)
- `POST /chat/completions` - Generate chat completions (OpenAI-compatible)

## Architecture

### Core Components

1. **ServerController**: Manages the server lifecycle, including starting, stopping, and health monitoring
2. **HTTPHandler**: Processes incoming HTTP requests using SwiftNIO
3. **Router**: Routes requests to appropriate handlers based on method and path
4. **ServerHealth**: Tracks server state (stopped, starting, running, stopping, error)
5. **ServerConfiguration**: Holds server settings like port, host, and thread configuration

### Design Patterns

- **MVVM**: Views observe the ServerController for state changes
- **Dependency Injection**: Server controller is passed through environment
- **Protocol-Oriented**: Router and handlers follow SwiftNIO protocols

## Usage

The application provides both a main window interface and a menu bar controller for managing the server. Users can:

1. Start/stop the server
2. Configure the port
3. View server status
4. Open the server URL in a browser
5. Monitor server health

## Dependencies

- SwiftNIO for networking
- SwiftUI for the user interface
- AppKit for macOS-specific features
- MLX-Swift for machine learning model inference
- MLXLLM for language model support
