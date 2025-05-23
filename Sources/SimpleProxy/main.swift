// Sources/SimpleProxy/main.swift

import Foundation
import NIO
import NIOHTTP1

final class HTTPProxyHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var clientChannel: Channel?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = self.unwrapInboundIn(data)

        switch requestPart {
        case .head(let requestHead):
            // Check for reload rules endpoint
            if requestHead.uri == "/__reload_rules" {
                RulesManager.shared.loadRules()
                sendOK(context: context, message: "Rules reloaded successfully.")
                return
            }

            if let matchedRule = RulesManager.shared.matchedRule(for: requestHead.uri) {
                serveLocalResponse(context: context, rule: matchedRule)
                return
            }

            // Continue real proxying...
            print("Received request: \(requestHead.method) \(requestHead.uri)")

            guard let url = URL(string: requestHead.uri), let host = url.host else {
                sendError(context: context, message: "Bad URL")
                return
            }

            let bootstrap = ClientBootstrap(group: context.eventLoop)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers()
                }

            bootstrap.connect(host: host, port: url.port ?? 80).whenSuccess { clientChannel in
                self.clientChannel = clientChannel

                var newRequestHead = HTTPRequestHead(version: requestHead.version,
                                                     method: requestHead.method,
                                                     uri: url.path.isEmpty ? "/" : url.path)
                newRequestHead.headers = requestHead.headers
                newRequestHead.headers.remove(name: "Host")
                newRequestHead.headers.add(name: "Host", value: host)

                clientChannel.write(HTTPClientRequestPart.head(newRequestHead), promise: nil)
                clientChannel.flush()

                clientChannel.pipeline.addHandler(ClientResponseHandler(context: context)).whenComplete { _ in }
            }
        case .body(let byteBuffer):
            clientChannel?.writeAndFlush(HTTPClientRequestPart.body(.byteBuffer(byteBuffer)), promise: nil)

        case .end:
            clientChannel?.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        }
    }
    private func sendOK(context: ChannelHandlerContext, message: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Reload Successful</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 2em; }
                h1 { color: #4CAF50; }
            </style>
        </head>
        <body>
            <h1>✅ Rules Reloaded</h1>
            <p>\(message)</p>
        </body>
        </html>
        """
        
        var buffer = context.channel.allocator.buffer(capacity: html.utf8.count)
        buffer.writeString(html)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
    
    private func serveLocalResponse(context: ChannelHandlerContext, rule: ProxyRule) {
        let fileURL = URL(fileURLWithPath: rule.localFilePath)
        if rule.localFilePath.hasSuffix("/") {
            let indexFile = fileURL.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: indexFile.path) {
                serveFile(context: context, fileURL: indexFile)
            } else {
                sendError(context: context, message: "Index file not found in folder")
            }
            return
        }
        serveFile(context: context, fileURL: fileURL)
    }

    private func serveFile(context: ChannelHandlerContext, fileURL: URL) {
        do {
            let data = try Data(contentsOf: fileURL)
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            
            let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
            
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            
            print("Served local file: \(fileURL.path)")
        } catch {
            sendError(context: context, message: "Failed to load local response")
        }
    }

    private func sendError(context: ChannelHandlerContext, message: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        let responseHead = HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}

final class ClientResponseHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    
    private let serverContext: ChannelHandlerContext

    init(context: ChannelHandlerContext) {
        self.serverContext = context
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let responsePart = self.unwrapInboundIn(data)

        switch responsePart {
        case .head(let responseHead):
            serverContext.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        case .body(let byteBuffer):
            serverContext.write(self.wrapOutboundOut(.body(.byteBuffer(byteBuffer))), promise: nil)
        case .end:
            serverContext.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(HTTPProxyHandler())
        }
    }
    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

defer {
    try! group.syncShutdownGracefully()
}

do {
    let channel = try bootstrap.bind(host: "0.0.0.0", port: 8080).wait()
    print("Server running on http://localhost:8080")
    try channel.closeFuture.wait()
} catch {
    fatalError("Failed to start server: \(error)")
}
