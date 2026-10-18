import Foundation

/// Controls the iPhone through the Python helper (Sources/geospoof_helper.py), so Xcode is not needed.
///
/// The helper must stay alive while a location is set: iOS drops a simulated location as soon as the
/// connection that set it closes. Reconnect and explicitly clear after an unexpected disconnect.
actor PythonDeviceService: DeviceControlling {
    /// Splits a byte stream into lines; called from the pipe's reader thread.
    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) -> [Data]? {
            lock.lock(); defer { lock.unlock() }
            guard data.count + chunk.count <= 1_048_576 else { data.removeAll(); return nil }
            data.append(chunk)
            var lines: [Data] = []
            while let newline = data.firstIndex(of: 0x0A) {
                lines.append(Data(data[data.startIndex..<newline]))
                data = Data(data[data.index(after: newline)...])
            }
            return lines
        }
    }

    /// Drain stderr continuously, retaining only a bounded in-memory tail.
    private final class DiagnosticBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            bytes.append(data.suffix(8192))
            if bytes.count > 8192 { bytes = Data(bytes.suffix(8192)) }
        }
        func text() -> String {
            lock.lock(); defer { lock.unlock() }
            return String(String(decoding: bytes, as: UTF8.self).suffix(1200))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var process: Process?
    private var input: FileHandle?
    private var diagnosticLog: DiagnosticBuffer?
    private var errorPipe: Pipe?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 0

    // MARK: Finding the Python runtime

    /// Release apps only execute their bundled helper. Test overrides are compile-time gated.
    static func locate() throws -> (python: URL, helper: URL) {
        #if GEOSPOOF_DEVELOPMENT
        let environment = ProcessInfo.processInfo.environment
        if let python = environment["GEOSPOOF_PYTHON"], let helper = environment["GEOSPOOF_HELPER"] {
            return (URL(fileURLWithPath: python), URL(fileURLWithPath: helper))
        }
        #endif
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("device-helper/geospoof-helper"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw DeviceError.message("The bundled device helper is missing. Reinstall GeoSpoof.")
        }
        return (helper, helper)
    }

    // MARK: Process lifecycle

    private func start() throws {
        if let process, process.isRunning { return }
        signal(SIGPIPE, SIG_IGN)   // a dead helper must surface as an error, not kill the app
        let (python, helper) = try Self.locate()

        let process = Process()
        process.executableURL = python
        process.arguments = python == helper ? [] : [helper.path]
        // Keep loader, Python path, proxy, certificate and remote-usbmux overrides out.
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "LANG": "en_US.UTF-8",
            "PYTHONUNBUFFERED": "1",
            "PYTHONDONTWRITEBYTECODE": "1"
        ]
        process.currentDirectoryURL = Bundle.main.resourceURL

        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        let stderr = Pipe()
        let diagnostics = DiagnosticBuffer()
        process.standardError = stderr
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            diagnostics.append(data)
        }

        let lines = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            guard let messages = lines.append(chunk) else {
                handle.readabilityHandler = nil
                Task { await self?.stop("The device helper exceeded the response size limit.") }
                return
            }
            for line in messages { Task { await self?.received(line) } }
        }
        process.terminationHandler = { [weak self] finished in Task { await self?.ended(finished) } }
        do { try process.run() }
        catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        self.input = stdin.fileHandleForWriting
        self.diagnosticLog = diagnostics
        self.errorPipe = stderr
    }

    /// Ends the helper and fails anything still waiting.
    private func stop(_ message: String) {
        let running = process
        process = nil
        input = nil
        running?.terminate()
        if let running {
            Task.detached {
                try? await Task.sleep(for: .seconds(5))
                if running.isRunning { kill(running.processIdentifier, SIGKILL) }
            }
        }
        failAll(DeviceError.message(message))
        removeLog()
    }

    private func ended(_ finished: Process) {
        guard process === finished else { return }   // we already stopped it ourselves
        let tail = logTail()
        process = nil
        input = nil
        failAll(DeviceError.message(tail.isEmpty ? "The device helper stopped unexpectedly." : "The device helper stopped unexpectedly.\n\(tail)"))
        removeLog()
    }

    private func logTail() -> String { diagnosticLog?.text() ?? "" }

    private func removeLog() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
        diagnosticLog = nil
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending = [:]
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    // MARK: Requests

    private func received(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? Int,            // lines without an id are progress events
              let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: line)
    }

    private func expire(_ id: Int) {
        guard pending[id] != nil else { return }
        // Stop the stuck channel; the app retains the phone identity for explicit recovery.
        stop("The iPhone did not respond. Unlock it, check the connection, and try again.")
    }

    private func request(_ command: String, _ fields: [String: Any] = [:], timeout: TimeInterval) async throws -> [String: Any] {
        try start()
        nextID += 1
        let id = nextID
        var payload = fields
        payload["id"] = id
        payload["cmd"] = command
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)

        let reply: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try input?.write(contentsOf: data) }
            catch {
                pending[id] = nil
                continuation.resume(throwing: DeviceError.message("The device helper isn't running. Try again."))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.expire(id)
            }
        }
        guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
            throw DeviceError.message("The device helper returned an unreadable response.")
        }
        if object["ok"] as? Bool == true { return object["result"] as? [String: Any] ?? [:] }
        throw DeviceError.message(object["error"] as? String ?? "The device helper reported an error.")
    }

    // MARK: DeviceControlling

    func prepare() async throws {
        let result = try await request("hello", timeout: 30)
        guard result["protocol"] as? Int == 1 else {
            throw DeviceError.message("The bundled device helper is incompatible. Rebuild or reinstall GeoSpoof.")
        }
    }

    func discover() async throws -> [Phone] {
        let result = try await request("discover", timeout: 40)
        let rows = result["devices"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return Phone(id: id, name: row["name"] as? String ?? "iPhone", model: "iPhone",
                         productType: row["productType"] as? String ?? "")
        }
    }

    func verify(_ id: String) async throws -> String {
        let result = try await request("verify", ["udid": id], timeout: 30)
        return result["transport"] as? String ?? "Connected"
    }

    func set(_ id: String, latitude: Double, longitude: Double) async throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw DeviceError.message("Choose a valid location on the map.")
        }
        // Generous: the first time on a phone, the developer image is downloaded and installed.
        _ = try await request("set", ["udid": id, "latitude": latitude, "longitude": longitude], timeout: 180)
    }

    func clear(_ id: String) async throws {
        _ = try await request("clear", ["udid": id], timeout: 180)
    }

    func simulationActive(_ id: String) async -> Bool? {
        guard let process, process.isRunning else { return false }   // no helper, nothing holds a simulation
        guard let result = try? await request("status", timeout: 10) else { return nil }
        return result["active"] as? Bool == true && (result["udid"] as? String) == id
    }
}
