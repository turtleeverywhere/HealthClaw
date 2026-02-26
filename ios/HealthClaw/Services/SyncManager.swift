import Foundation
import Combine

@MainActor
class SyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncStatus: SyncStatus = .idle
    @Published var lastError: String?

    private var healthManager: HealthKitManager?
    private var settings: AppSettings?
    private var syncTimer: Timer?

    enum SyncStatus: String {
        case idle = "Not synced"
        case syncing = "Syncing..."
        case success = "Synced"
        case error = "Error"
    }

    func configure(healthManager: HealthKitManager, settings: AppSettings) {
        self.healthManager = healthManager
        self.settings = settings
        startSyncTimer()
    }

    func startSyncTimer() {
        syncTimer?.invalidate()
        guard let settings else { return }
        let interval = TimeInterval(settings.syncIntervalMinutes * 60)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncIfNeeded()
            }
        }
    }

    func syncIfNeeded() async {
        guard let settings, settings.isConfigured else { return }
        await performSync()
    }

    func performSync() async {
        guard let healthManager, let settings, settings.isConfigured else {
            lastSyncStatus = .error
            lastError = "API not configured"
            return
        }

        isSyncing = true
        lastSyncStatus = .syncing
        lastError = nil

        // Always sync from start of day — HealthKit cumulative stats (steps, calories)
        // only return data within the queried window, so short incremental windows
        // would miss most of the day's data. Sleep needs 2 days back to catch
        // overnight sessions.
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let sleepStart = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        let payload = await healthManager.collectData(from: startOfDay, to: now, sleepFrom: sleepStart)

        do {
            try await sendPayload(payload, settings: settings)
            settings.lastSyncTimestamp = now.timeIntervalSince1970
            lastSyncStatus = .success
        } catch {
            lastSyncStatus = .error
            lastError = error.localizedDescription
        }

        isSyncing = false
    }

    private func sendPayload(_ payload: HealthSyncPayload, settings: AppSettings) async throws {
        let url = URL(string: "\(settings.baseURL)/api/health/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.serverError(httpResponse.statusCode, body)
        }
    }
}

enum SyncError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code, let body): return "Server error \(code): \(body)"
        }
    }
}
