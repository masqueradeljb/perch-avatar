import Foundation
import Network
import AvatarCore

/// Newline-delimited JSON over a Unix socket. Each request line gets one response line.
/// Handlers run on the main queue.
final class SocketServer {
    static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["PERCH_SOCK"], !p.isEmpty { return p }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".perch/perch.sock").path
    }

    static let maxLine = 64 * 1024

    private let path: String
    private let onRequest: (Envelope) -> Response
    private var listener: NWListener?

    init(path: String = SocketServer.defaultPath, onRequest: @escaping (Envelope) -> Response) {
        self.path = path
        self.onRequest = onRequest
    }

    func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: path)  // stale socket from a previous run
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state { fputs("Perch: socket listener failed: \(error)\n", stderr) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer + (data ?? Data())
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                if !line.isEmpty { self.reply(connection, self.handle(Data(line))) }
            }
            if buffer.count > SocketServer.maxLine {
                self.reply(connection, Response(ok: false, error: "line too long"), thenClose: true)
                return
            }
            if isComplete || error != nil {
                if !buffer.isEmpty { self.reply(connection, self.handle(buffer), thenClose: true) }
                else { connection.cancel() }
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func handle(_ line: Data) -> Response {
        do {
            return onRequest(try JSONDecoder().decode(Envelope.self, from: line))
        } catch {
            return Response(ok: false, error: "bad request: \(error)")
        }
    }

    /// Sends one response line; with `thenClose`, cancels the connection once the send has completed.
    private func reply(_ connection: NWConnection, _ response: Response, thenClose: Bool = false) {
        var data = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false}"#.utf8)
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in if thenClose { connection.cancel() } })
    }
}
