import Darwin
import Foundation

/// One hook event from `notch-hook`: the agent in the path, its hook payload in the body.
struct AgentHookRequest: Sendable {
    var path: String
    /// Lowercased names.
    var headers: [String: String]
    var body: Data
}

/// Receives hook events on a Unix domain socket that only this user can open. It speaks just
/// enough HTTP/1.1 for `curl --unix-socket`, so the hook script needs nothing beyond macOS.
final class AgentHookServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case pathTooLong(String)
        case pathOccupied(String)
        case system(String, Int32)

        var errorDescription: String? {
            switch self {
            case .pathTooLong(let path):
                "The socket path is too long: \(path)"
            case .pathOccupied(let path):
                "Something other than a socket exists at \(path)"
            case .system(let call, let code):
                "\(call) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    static let maxBodySize = 1 << 20
    /// Longest Notch holds a `/decide/` request; the hook script gives curl a bit more.
    static let decisionWait: TimeInterval = 45

    /// Answers a `/decide/` request: JSON for the hook to print, or nil for no decision.
    typealias Decider = @Sendable (AgentHookRequest, @escaping @Sendable (Data?) -> Void) -> Void

    let socketPath: String
    private let handler: @Sendable (AgentHookRequest) -> Void
    private let decider: Decider?
    private let queue = DispatchQueue(label: "com.djui.notch.agent-hooks")
    private var listenSource: DispatchSourceRead?
    private var socketInode: ino_t = 0

    init(
        socketPath: String,
        handler: @escaping @Sendable (AgentHookRequest) -> Void,
        decider: Decider? = nil
    ) {
        self.socketPath = socketPath
        self.handler = handler
        self.decider = decider
    }

    deinit {
        listenSource?.cancel()
    }

    func start() throws {
        try queue.sync { try openSocket() }
    }

    func stop() {
        queue.sync { closeSocket() }
    }

    private func openSocket() throws {
        guard listenSource == nil else { return }
        let path = socketPath
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try removeStaleSocket(at: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.system("socket", errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ServerError.pathTooLong(path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw ServerError.system("bind", code)
        }
        // Connecting needs write permission on the socket file.
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ServerError.system("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var info = stat()
        if lstat(path, &info) == 0 {
            socketInode = info.st_ino
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPending(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        listenSource = source
        source.resume()
    }

    private func closeSocket() {
        guard let source = listenSource else { return }
        source.cancel()
        listenSource = nil
        // Leave the path alone if another Notch instance has taken it over since.
        var info = stat()
        if lstat(socketPath, &info) == 0, info.st_ino == socketInode {
            unlink(socketPath)
        }
    }

    private func removeStaleSocket(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw ServerError.pathOccupied(path)
        }
        unlink(path)
    }

    private func acceptPending(on listenFD: Int32) {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            Self.configure(client)
            let handler = self.handler
            let decider = self.decider
            DispatchQueue.global(qos: .utility).async {
                Self.serve(client, handler: handler, decider: decider)
            }
        }
    }

    /// Blocking reads with a short timeout, so a stalled client cannot hold a thread for long.
    private static func configure(_ fd: Int32) {
        // Accepted sockets inherit O_NONBLOCK from the listener on BSD.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func serve(_ fd: Int32, handler: @Sendable (AgentHookRequest) -> Void, decider: Decider?) {
        defer { close(fd) }
        do {
            let request = try readRequest(fd)
            if request.path.hasPrefix("/decide/"), let decider {
                let answer = DecisionBox()
                decider(request) { answer.finish($0) }
                if let body = answer.wait(seconds: decisionWait), !body.isEmpty {
                    reply(fd, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n")
                    _ = body.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
                } else {
                    reply(fd, "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
                }
                return
            }
            reply(fd, "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
            handler(request)
        } catch let failure as HTTPFailure {
            reply(fd, "HTTP/1.1 \(failure.status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        } catch {
            return
        }
    }

    /// Holds a connection's thread until the decision arrives or time runs out.
    private final class DecisionBox: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var body: Data?
        private var done = false

        func finish(_ data: Data?) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body = data
            semaphore.signal()
        }

        func wait(seconds: TimeInterval) -> Data? {
            _ = semaphore.wait(timeout: .now() + seconds)
            lock.lock()
            defer { lock.unlock() }
            done = true
            return body
        }
    }

    private struct HTTPFailure: Error {
        var status: String
    }

    private static func readRequest(_ fd: Int32) throws -> AgentHookRequest {
        let separator = Data("\r\n\r\n".utf8)
        var buffer = Data()
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            guard buffer.count <= 16_384 else {
                throw HTTPFailure(status: "431 Request Header Fields Too Large")
            }
            guard let chunk = receive(fd) else {
                throw HTTPFailure(status: "400 Bad Request")
            }
            buffer.append(chunk)
            headerEnd = buffer.range(of: separator)
        }
        guard let headerEnd else { throw HTTPFailure(status: "400 Bad Request") }

        var lines = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            .components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { throw HTTPFailure(status: "400 Bad Request") }
        guard requestLine[0] == "POST" else { throw HTTPFailure(status: "405 Method Not Allowed") }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = headers["content-length"].flatMap({ Int($0) }), length >= 0 else {
            throw HTTPFailure(status: "411 Length Required")
        }
        guard length <= maxBodySize else { throw HTTPFailure(status: "413 Content Too Large") }

        var body = Data(buffer[headerEnd.upperBound...])
        if body.count < length, headers["expect"]?.lowercased() == "100-continue" {
            reply(fd, "HTTP/1.1 100 Continue\r\n\r\n")
        }
        while body.count < length {
            guard let chunk = receive(fd) else { throw HTTPFailure(status: "400 Bad Request") }
            body.append(chunk)
        }
        return AgentHookRequest(path: String(requestLine[1]), headers: headers, body: body.prefix(length))
    }

    private static func receive(_ fd: Int32) -> Data? {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = recv(fd, &bytes, bytes.count, 0)
        guard count > 0 else { return nil }
        return Data(bytes[..<count])
    }

    private static func reply(_ fd: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
    }
}
