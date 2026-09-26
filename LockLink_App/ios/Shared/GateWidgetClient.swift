import Foundation
import CryptoKit

final class NoGateRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor GateWidgetClient {
    static let shared = GateWidgetClient()
    private var running = false

    func unlock() async -> String {
        guard !running else { return "An unlock request is already running." }
        running = true
        defer { running = false }
        let started = Date()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: NoGateRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let config = try GateWidgetStore.load()
            let status = try await request(session, config: config, path: "/status")
            guard status["online"] as? Bool == true else {
                throw GateWidgetError.message("Device offline. Check Wi-Fi.")
            }
            guard status["state"] as? String != "unlocking" else {
                throw GateWidgetError.message("Gate is already unlocking.")
            }
            let mode = status["mode"] as? String ?? "led"
            var headers: [String: String] = [:]
            if mode == "relay" {
                guard status["armed"] as? Bool == true else {
                    throw GateWidgetError.message("Device not armed. Check setup.")
                }
                let challenge = try await request(session, config: config, path: "/challenge")
                guard let nonce = challenge["nonce"] as? String,
                      nonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
                    throw GateWidgetError.message("Unexpected device response.")
                }
                let keyBytes = stride(from: 0, to: 64, by: 2).map { offset -> UInt8 in
                    let start = config.signingKey.index(config.signingKey.startIndex, offsetBy: offset)
                    let end = config.signingKey.index(start, offsetBy: 2)
                    return UInt8(config.signingKey[start..<end], radix: 16)!
                }
                let signature = HMAC<SHA256>.authenticationCode(for: Data("unlock:\(nonce)".utf8),
                    using: SymmetricKey(data: Data(keyBytes)))
                    .map { String(format: "%02x", $0) }.joined()
                headers = ["X-LockLink-Nonce": nonce, "X-LockLink-Signature": signature]
            } else if mode != "led" {
                throw GateWidgetError.message("Unsupported device mode.")
            }
            guard Date().timeIntervalSince(started) < 15,
                  try GateWidgetStore.load() == config else {
                throw GateWidgetError.message("Settings changed. Tap again.")
            }
            let result: [String: Any]
            do {
                result = try await request(session, config: config, path: "/unlock", headers: headers)
            } catch let error as GateWidgetError {
                throw error
            } catch {
                throw GateWidgetError.message("No confirmation. Check gate before retrying.")
            }
            guard result["success"] as? Bool == true, result["state"] as? String == "unlocking",
                  let duration = result["duration_ms"] as? Int, duration >= 0 else {
                throw GateWidgetError.message("No confirmation. Check gate before retrying.")
            }
            return mode == "relay" ? "Unlock command accepted." : "LED command accepted."
        } catch let error as GateWidgetError {
            return error.text
        } catch {
            return "Cannot reach device. Check Wi-Fi and settings."
        }
    }

    private func request(_ session: URLSession, config: GateWidgetConfiguration, path: String,
                         headers: [String: String]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: config.address + path) else {
            throw GateWidgetError.message("Check the address in LockLink.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = headers == nil ? "GET" : "POST"
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401: throw GateWidgetError.message("Pairing key rejected. Update settings.")
        case 409: throw GateWidgetError.message("Gate is already unlocking.")
        case 503: throw GateWidgetError.message("Device not armed. Check setup.")
        default: throw GateWidgetError.message(headers == nil ? "Device refused the request."
            : "No confirmation. Check gate before retrying.")
        }
        guard data.count <= 8192,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GateWidgetError.message(headers == nil ? "Unexpected device response."
                : "No confirmation. Check gate before retrying.")
        }
        return json
    }
}
