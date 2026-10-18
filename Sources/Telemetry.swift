import CryptoKit
import Foundation

/// Anonymous usage signals sent to TelemetryDeck's ingest API (https://telemetrydeck.com/docs/ingest/v2).
/// Off when the build has no app ID (e.g. built from source without TELEMETRYDECK_APP_ID) or the user opts out.
enum Telemetry {
    private static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")!
    private static let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String ?? ""
    private static let isTestMode = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckTestMode") as? Bool ?? true
    private static let sessionID = UUID().uuidString

    /// Whether this build can send anything at all; the opt-out switch is hidden otherwise.
    static var isAvailable: Bool { !appID.isEmpty }

    static var isEnabled: Bool {
        isAvailable && (UserDefaults.standard.object(forKey: "shareAnalytics") as? Bool ?? true)
    }

    /// A random per-install ID, hashed so the raw value never leaves the Mac.
    private static let clientUser: String = {
        let key = "telemetryInstallID"
        let id = UserDefaults.standard.string(forKey: key) ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: key)
            return new
        }()
        return SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }()

    private static let defaultPayload: [String: String] = {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "TelemetryDeck.AppInfo.version": info["CFBundleShortVersionString"] as? String ?? "",
            "TelemetryDeck.AppInfo.buildNumber": info["CFBundleVersion"] as? String ?? "",
            "TelemetryDeck.Device.operatingSystem": "macOS",
            "TelemetryDeck.Device.platform": "macOS",
            "TelemetryDeck.Device.architecture": "arm64",
            "TelemetryDeck.Device.systemVersion": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "TelemetryDeck.Device.systemMajorMinorVersion": "\(os.majorVersion).\(os.minorVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "\(os.majorVersion)",
            "TelemetryDeck.RunContext.locale": Locale.current.identifier,
            "TelemetryDeck.UserPreference.region": Locale.current.region?.identifier ?? "",
        ]
    }()

    static func send(_ type: String, payload: [String: String] = [:]) {
        guard isEnabled else { return }
        let signal: [String: Any] = [
            "appID": appID,
            "clientUser": clientUser,
            "sessionID": sessionID,
            "type": type,
            "isTestMode": isTestMode,
            "payload": defaultPayload.merging(payload) { _, new in new },
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [signal])
        URLSession.shared.dataTask(with: request).resume()
    }
}
