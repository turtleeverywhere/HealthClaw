import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var syncManager: SyncManager
    @State private var showingTestResult = false
    @State private var testResult: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("API Connection") {
                    HStack {
                        Image(systemName: "link")
                        TextField("Endpoint (e.g. 100.x.x.x:8099)", text: $settings.apiEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    HStack {
                        Image(systemName: "key")
                        SecureField("API Key", text: $settings.apiKey)
                            .textInputAutocapitalization(.never)
                    }
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(!settings.isConfigured)
                }

                Section("Sync Schedule") {
                    Picker("Interval", selection: $settings.syncIntervalMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("Manual only").tag(0)
                    }
                    .onChange(of: settings.syncIntervalMinutes) { _, _ in
                        syncManager.startSyncTimer()
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        if let date = settings.lastSyncDate {
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(syncManager.lastSyncStatus.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    if let error = syncManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Sync Now") {
                    Button {
                        Task { await syncManager.performSync() }
                    } label: {
                        HStack {
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(syncManager.isSyncing ? "Syncing..." : "Sync Health Data")
                            Spacer()
                        }
                    }
                    .disabled(syncManager.isSyncing || !settings.isConfigured)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Connection Test", isPresented: $showingTestResult) {
                Button("OK") {}
            } message: {
                Text(testResult)
            }
        }
    }

    func testConnection() async {
        guard let url = URL(string: "\(settings.baseURL)/api/health/ping") else {
            testResult = "Invalid URL"
            showingTestResult = true
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                testResult = "✅ Connection successful!"
            } else {
                testResult = "❌ Server returned error"
            }
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
        showingTestResult = true
    }
}
