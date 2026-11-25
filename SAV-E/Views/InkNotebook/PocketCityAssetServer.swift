import Foundation
import Network

/// Serves the bundled atlas with the HTTP origin required by MapLibre module workers.
@MainActor
final class PocketCityAssetServer {
    private let root: URL
    private let allowsRemoteTiles: Bool
    private var listener: PocketCityHTTPListener?
    private var readyURL: URL?
    private var callbacks: [(URL?) -> Void] = []

    init(root: URL, allowsRemoteTiles: Bool) {
        self.root = root
        self.allowsRemoteTiles = allowsRemoteTiles
    }

    func start(onReady: @escaping (URL?) -> Void) {
        if let readyURL {
            onReady(readyURL)
            return
        }
        callbacks.append(onReady)
        guard listener == nil else { return }
        let session = PocketCityHTTPListener(root: root, allowsRemoteTiles: allowsRemoteTiles)
        listener = session
        session.start { [weak self, weak session] url in
            Task { @MainActor in
                guard let self, let session, self.listener === session else { return }
                self.readyURL = url
                if url == nil { self.listener = nil }
                self.complete(with: url)
            }
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
        readyURL = nil
        complete(with: nil)
    }

    private func complete(with url: URL?) {
        let waiting = callbacks
        callbacks.removeAll()
        waiting.forEach { $0(url) }
    }

    deinit { listener?.stop() }
}

/// All mutable Network.framework state and file handles are confined to queue.
private nonisolated final class PocketCityHTTPListener: @unchecked Sendable {
    private let root: URL
    private let allowsRemoteTiles: Bool
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "savvy.pocket-city.assets", qos: .userInitiated)
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var headerTimers: [ObjectIdentifier: DispatchWorkItem] = [:]

    init(root: URL, allowsRemoteTiles: Bool) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.allowsRemoteTiles = allowsRemoteTiles
    }

    func start(ready: @escaping @Sendable (URL?) -> Void) {
        queue.async { [self] in
            guard FileManager.default.isReadableFile(atPath: root.appendingPathComponent("index.html").path) else {
                ready(nil)
                return
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            do {
                let server = try NWListener(using: parameters)
                listener = server
                server.newConnectionHandler = { [weak self] client in
                    guard let self, self.listener != nil, self.clients.count < 48 else {
                        client.cancel()
                        return
                    }
                    self.accept(client)
                }
                server.stateUpdateHandler = { [weak self, weak server] state in
                    guard let self, let server, self.listener === server else { return }
                    switch state {
                    case .ready:
                        guard let port = server.port else { self.shutDown(); ready(nil); return }
                        let query = self.allowsRemoteTiles ? "" : "?tiles=bundled"
                        ready(URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/index.html\(query)"))
                    case .failed:
                        self.shutDown()
                        ready(nil)
                    default:
                        break
                    }
                }
                server.start(queue: queue)
            } catch {
                ready(nil)
            }
        }
    }

    func stop() { queue.async { self.shutDown() } }

    private func shutDown() {
        listener?.cancel()
        listener = nil
        for timer in headerTimers.values { timer.cancel() }
        headerTimers.removeAll()
        for client in clients.values { client.cancel() }
        clients.removeAll()
    }

    private func accept(_ client: NWConnection) {
        let key = ObjectIdentifier(client)
        clients[key] = client
        let deadline = DispatchWorkItem { [weak self, weak client] in
            if let client { self?.finish(client) }
        }
        headerTimers[key] = deadline
        queue.asyncAfter(deadline: .now() + 10, execute: deadline)
        client.stateUpdateHandler = { [weak self, weak client] state in
            if case .failed = state, let client { self?.finish(client) }
        }
        client.start(queue: queue)
        readHeaders(client, buffer: Data())
    }

    private func finish(_ client: NWConnection) {
        let key = ObjectIdentifier(client)
        headerTimers.removeValue(forKey: key)?.cancel()
        clients.removeValue(forKey: key)
        client.cancel()
    }

    private func readHeaders(_ client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, done, error in
            guard let self, self.clients[ObjectIdentifier(client)] != nil else { return }
            var bytes = buffer
            if let chunk { bytes.append(chunk) }
            guard error == nil, bytes.count <= 16384 else { self.finish(client); return }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                self.headerTimers.removeValue(forKey: ObjectIdentifier(client))?.cancel()
                guard end.upperBound == bytes.endIndex,
                      let headers = String(data: bytes[..<end.lowerBound], encoding: .utf8) else {
                    self.reject(client, "400 Bad Request")
                    return
                }
                self.respond(client, headers: headers)
            } else if done {
                self.finish(client)
            } else {
                self.readHeaders(client, buffer: bytes)
            }
        }
    }

    private func respond(_ client: NWConnection, headers: String) {
        let lines = headers.components(separatedBy: "\r\n")
        let request = lines[0].split(separator: " ")
        guard request.count == 3, request[2] == "HTTP/1.1", let port = listener?.port else {
            reject(client, "400 Bad Request")
            return
        }
        guard request[0] == "GET" || request[0] == "HEAD" else {
            reject(client, "405 Method Not Allowed")
            return
        }
        let authority = "127.0.0.1:\(port.rawValue)"
        var hosts: [String] = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                reject(client, "400 Bad Request")
                return
            }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "host": hosts.append(value)
            case "origin" where value != "http://\(authority)",
                 "sec-fetch-site" where value == "cross-site":
                reject(client, "403 Forbidden")
                return
            case "transfer-encoding",
                 "content-length" where value != "0":
                reject(client, "400 Bad Request")
                return
            default: break
            }
        }
        guard hosts == [authority] else { reject(client, "403 Forbidden"); return }
        let target = request[1].prefix(while: { $0 != "?" })
        let prefix = "/\(token)/"
        guard target.hasPrefix(prefix),
              let decoded = target.dropFirst(prefix.count).removingPercentEncoding,
              !decoded.contains("\\"), !decoded.contains("\0") else {
            reject(client, "404 Not Found")
            return
        }
        let path = decoded.isEmpty ? "index.html" : decoded
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else {
            reject(client, "404 Not Found")
            return
        }
        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: file) else {
            reject(client, "404 Not Found")
            return
        }
        let ext = file.pathExtension.lowercased()
        let gzipPBF = ext == "pbf" && (try? handle.read(upToCount: 2)) == Data([0x1f, 0x8b])
        do { try handle.seek(toOffset: 0) } catch { finish(client); return }
        let head = [
            "HTTP/1.1 200 OK", "Connection: close", "Content-Length: \(size)",
            "Content-Type: \(Self.mimeTypes[ext] ?? "application/octet-stream")",
            "Referrer-Policy: no-referrer", "X-Content-Type-Options: nosniff",
            "Cross-Origin-Resource-Policy: same-origin", "Content-Security-Policy: \(policy)"
        ] + (gzipPBF ? ["Content-Encoding: gzip"] : [])
        send(client, headers: head) { [weak self] error in
            guard let self else { return }
            if error != nil || request[0] == "HEAD" { self.finish(client) }
            else { self.sendBody(client, handle: handle) }
        }
    }

    private func sendBody(_ client: NWConnection, handle: FileHandle) {
        guard clients[ObjectIdentifier(client)] != nil else { return }
        do {
            guard let bytes = try handle.read(upToCount: 128 * 1024), !bytes.isEmpty else {
                finish(client)
                return
            }
            client.send(content: bytes, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.finish(client) }
                else { self?.sendBody(client, handle: handle) }
            })
        } catch { finish(client) }
    }

    private func send(_ client: NWConnection, headers: [String], done: @escaping @Sendable (NWError?) -> Void) {
        let data = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        client.send(content: data, completion: .contentProcessed(done))
    }

    private func reject(_ client: NWConnection, _ status: String) {
        send(client, headers: ["HTTP/1.1 \(status)", "Connection: close", "Content-Length: 0"]) { [weak self] _ in
            self?.finish(client)
        }
    }

    private static let mimeTypes = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
        "json": "application/json", "geojson": "application/geo+json", "pbf": "application/x-protobuf",
        "gz": "application/gzip", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "webp": "image/webp", "svg": "image/svg+xml", "woff2": "font/woff2"
    ]
    private var policy: String {
        let tileOrigins = allowsRemoteTiles ? " https://tiles.openfreemap.org https://s3.amazonaws.com/elevation-tiles-prod/" : ""
        let floorGuideOrigin = allowsRemoteTiles ? " https://www.taipei-101.com.tw/asset/img/map/" : ""
        return [
            "default-src 'none'", "script-src 'self'", "worker-src 'self'", "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob:\(tileOrigins)\(floorGuideOrigin)", "connect-src 'self'\(tileOrigins)",
            "font-src 'self'", "frame-ancestors 'none'", "form-action 'none'", "base-uri 'none'"
        ].joined(separator: "; ")
    }
}
