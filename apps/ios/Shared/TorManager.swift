import Foundation
import CTor
import Network
import Zero

/// Embedded Tor daemon manager for iOS using iCepa/Tor.framework (CTor).
/// Starts a local SOCKS5 listener on 127.0.0.1:9050 when Tor protection is enabled.
final class TorManager {
    static let shared = TorManager()

    private let lock = NSLock()
    private var torThread: TorThread?

    private init() {}

    var isEnabledByUser: Bool {
        let raw = groupDefaults.string(forKey: GROUP_DEFAULT_NETWORK_SOCKS_PROXY)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty
    }

    func startIfEnabled() {
        guard isEnabledByUser else { return }
        startIfNeeded()
    }

    func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if torThread != nil || TorThread.active != nil { return }

        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dataDir = baseDir.appendingPathComponent("zero-tor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let config = TorConfiguration()
        config.ignoreMissingTorrc = true
        config.clientOnly = true
        config.avoidDiskWrites = true
        config.socksPort = 9050
        config.dataDirectory = dataDir

        let thread = TorThread(configuration: config)
        thread.start()
        torThread = thread
    }

    /// Ensures the embedded Tor SOCKS5 proxy is listening on 127.0.0.1:9050 before network calls.
    func ensureStarted(timeoutSeconds: TimeInterval = 25) async -> Bool {
        startIfEnabled()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await isLocalSocksListening() {
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return await isLocalSocksListening()
    }

    private func isLocalSocksListening() async -> Bool {
        await withCheckedContinuation { continuation in
            let conn = NWConnection(host: "127.0.0.1", port: 9050, using: .tcp)
            final class Once {
                var done = false
                let lock = NSLock()
                func finish(_ ok: Bool, _ conn: NWConnection, _ cont: CheckedContinuation<Bool, Never>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !done else { return }
                    done = true
                    conn.cancel()
                    cont.resume(returning: ok)
                }
            }
            let once = Once()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.finish(true, conn, continuation)
                case .failed, .cancelled:
                    once.finish(false, conn, continuation)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) {
                once.finish(false, conn, continuation)
            }
        }
    }
}
