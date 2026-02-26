import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    @AppStorage("apiEndpoint") var apiEndpoint: String = ""
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("syncIntervalMinutes") var syncIntervalMinutes: Int = 30
    @AppStorage("lastSyncDate") var lastSyncTimestamp: Double = 0

    var lastSyncDate: Date? {
        lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil
    }

    var isConfigured: Bool {
        !apiEndpoint.isEmpty && !apiKey.isEmpty
    }

    /// Normalized base URL (no trailing slash)
    var baseURL: String {
        var url = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        if !url.hasPrefix("http") { url = "http://\(url)" }
        return url
    }
}
