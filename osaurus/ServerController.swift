import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

@MainActor
final class ServerController: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: Int = 8080
    @Published var lastErrorMessage: String?
    @Published var serverHealth: ServerHealth = .stopped
    
    // SwiftNIO runtime
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    
    enum ServerHealth {
        case stopped
        case starting
        case running
        case stopping
        case error(String)
    }

    func startServer() async {
        guard !isRunning else { return }
        
        serverHealth = .starting
        let selectedPort = port
        
        do {
            print("[Osaurus] Starting NIO server on port \(selectedPort)")

            // Ensure any previous instance is shut down
            try await stopServerIfNeeded()

            // Create event loop group
            let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            self.eventLoopGroup = group

            // Bootstrap a simple HTTP server
            let bootstrap = ServerBootstrap(group: group)
                // Server options
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                // Child channels (accepted connections)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(SimpleHTTPHandler())
                    }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

            // Bind to localhost only
            let channel = try bootstrap.bind(host: "127.0.0.1", port: selectedPort).wait()
            self.serverChannel = channel

            // Mark as running on the main actor
            isRunning = true
            serverHealth = .running
            lastErrorMessage = nil
            print("[Osaurus] NIO server started successfully on port \(selectedPort)")

            // When the server channel closes, update state
            channel.closeFuture.whenComplete { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRunning = false
                    self.serverHealth = .stopped
                    self.serverChannel = nil
                }
            }
        } catch {
            print("[Osaurus] Failed to start server: \(error)")
            serverHealth = .error(error.localizedDescription)
            
            isRunning = false
            lastErrorMessage = error.localizedDescription
            // Attempt cleanup
            await cleanupRuntime()
        }
    }
    
    // No routing logic here; see Router below

    func stopServer() async {
        // If nothing to stop, return
        guard serverChannel != nil || eventLoopGroup != nil else { return }

        serverHealth = .stopping
        print("[Osaurus] Stopping NIO server...")

        isRunning = false

        // Close the server channel if present
        if let channel = serverChannel {
            do { try channel.close().wait() } catch { print("[Osaurus] Error closing channel: \(error)") }
            serverChannel = nil
        }

        await cleanupRuntime()

        serverHealth = .stopped
        print("[Osaurus] Server stopped successfully")
    }
    
    /// Ensures the server is properly shut down before app termination
    func ensureShutdown() async {
        guard serverChannel != nil || eventLoopGroup != nil else { return }

        print("[Osaurus] Ensuring NIO server shutdown before app termination")
        isRunning = false
        serverHealth = .stopping

        if let channel = serverChannel {
            do { try channel.close().wait() } catch { print("[Osaurus] Error closing channel: \(error)") }
            serverChannel = nil
        }

        await cleanupRuntime()

        print("[Osaurus] Server shutdown completed")
    }
    
    /// Checks if the server is responsive
    func checkServerHealth() async -> Bool {
        guard isRunning else { return false }
        
        do {
            let url = URL(string: "http://127.0.0.1:\(port)/health")!
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[Osaurus] Health check failed: \(error)")
            return false
        }
    }

    // MARK: - Private helpers
    private func stopServerIfNeeded() async throws {
        if serverChannel != nil || eventLoopGroup != nil {
            await stopServer()
        }
    }

    private func cleanupRuntime() async {
        // Shutdown the event loop group gracefully
        if let group = eventLoopGroup {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                group.shutdownGracefully { error in
                    if let error {
                        print("[Osaurus] Error shutting down EventLoopGroup: \(error)")
                    }
                    continuation.resume()
                }
            }
            eventLoopGroup = nil
        }
    }
}

// MARK: - NIO HTTP Handler
final class SimpleHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?
    private let router = Router()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
        case .body:
            // Endpoints ignore body for now
            break
        case .end:
            guard let head = requestHead else {
                writeResponse(context: context, version: .init(major: 1, minor: 1), status: .badRequest, headers: [("Content-Type", "text/plain; charset=utf-8")], body: "Bad Request")
                return
            }

            // Route based on method/path (strip query if present)
            let pathOnly: String
            if let qIndex = head.uri.firstIndex(of: "?") {
                pathOnly = String(head.uri[..<qIndex])
            } else {
                pathOnly = head.uri
            }
            let routed = router.route(method: head.method.rawValue, path: pathOnly)
            writeResponse(context: context, version: head.version, status: routed.status, headers: routed.headers, body: routed.body)
            requestHead = nil
        }
    }

    private func writeResponse(context: ChannelHandlerContext, version: HTTPVersion, status: HTTPResponseStatus, headers: [(String, String)], body: String) {
        var responseHead = HTTPResponseHead(version: version, status: status)
        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)

        var nioHeaders: HTTPHeaders = HTTPHeaders()
        for (name, value) in headers { nioHeaders.add(name: name, value: value) }
        nioHeaders.add(name: "Content-Length", value: String(buffer.readableBytes))
        nioHeaders.add(name: "Connection", value: "close")
        responseHead.headers = nioHeaders

        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - Router (pure routing, thread-safe)
struct Router {
    func route(method: String, path: String) -> (status: HTTPResponseStatus, headers: [(String, String)], body: String) {
        if method == "GET" && path == "/health" {
            let json = "{" + "\"status\":\"healthy\",\"timestamp\":\"" + Date().ISO8601Format() + "\"}"
            return (.ok, [("Content-Type", "application/json; charset=utf-8")], json)
        } else if method == "GET" && path == "/" {
            return (.ok, [("Content-Type", "text/plain; charset=utf-8")], "Osaurus Server is running! 🦕")
        } else if method == "POST" && path == "/echo" {
            return (.ok, [("Content-Type", "text/plain; charset=utf-8")], "Echo endpoint received request")
        } else {
            return (.notFound, [("Content-Type", "text/plain; charset=utf-8")], "Not Found")
        }
    }
}
