import Foundation

final class ObsidianService: @unchecked Sendable {

    private let baseURL: String
    private let apiKey: String
    private let localFallbackDir: URL

    private lazy var session: URLSession = {
        let delegate = InsecureTLSDelegate()
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }()

    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.localFallbackDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts", isDirectory: true)
    }

    func writeNote(path: String, content: String) async {
        if await writeToObsidian(path: path, content: content) {
            return
        }
        writeToLocal(path: path, content: content)
    }

    func appendToNote(path: String, content: String) async {
        if let existing = await readFromObsidian(path: path) {
            await writeNote(path: path, content: existing + content)
        } else {
            appendToLocal(path: path, content: content)
        }
    }

    private func writeToObsidian(path: String, content: String) async -> Bool {
        guard !baseURL.isEmpty, !apiKey.isEmpty,
              let url = URL(string: "\(baseURL)/vault/\(path)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/markdown", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(content.utf8)

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200 || (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            return false
        }
    }

    private func readFromObsidian(path: String) async -> String? {
        guard !baseURL.isEmpty, !apiKey.isEmpty,
              let url = URL(string: "\(baseURL)/vault/\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func ensureLocalDir() {
        try? FileManager.default.createDirectory(at: localFallbackDir, withIntermediateDirectories: true)
    }

    private func localURL(for path: String) -> URL {
        let filename = URL(string: path)?.lastPathComponent ?? path
        return localFallbackDir.appendingPathComponent(filename)
    }

    private func writeToLocal(path: String, content: String) {
        ensureLocalDir()
        let url = localURL(for: path)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendToLocal(path: String, content: String) {
        ensureLocalDir()
        let url = localURL(for: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(content.utf8))
            handle.closeFile()
        } else {
            writeToLocal(path: path, content: content)
        }
    }
}

private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == "127.0.0.1",
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
