import SwiftUI

struct CloudAIProviderSettingsCard: View {
    let provider: AIProviderKind
    @Bindable var settings: AppSettings
    var onSave: () -> Void

    @State private var apiKeyDraft: String = ""
    @State private var hasStoredKey = false
    @State private var connectionStatus: ProviderConnectionStatus = .unknown

    enum ProviderConnectionStatus: Equatable {
        case unknown, testing, connected, failed(String)

        var label: String {
            switch self {
            case .unknown: "Not tested"
            case .testing: "Testing…"
            case .connected: "Connected"
            case .failed(let msg): msg
            }
        }

        var color: Color {
            switch self {
            case .unknown: .secondary
            case .testing: .orange
            case .connected: .green
            case .failed: .red
            }
        }
    }

    var body: some View {
        AIProviderSettingsCard(
            systemImage: provider.systemImage,
            title: provider.displayName,
            subtitle: provider.subtitle,
            isEnabled: enabledBinding
        ) {
            VStack(alignment: .leading, spacing: 10) {
                apiKeyRow

                modelRow

                if connectionStatus != .unknown {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionStatus.color)
                            .frame(width: 6, height: 6)
                        Text(connectionStatus.label)
                            .font(.system(size: 11))
                            .foregroundStyle(connectionStatus.color)
                            .lineLimit(2)
                    }
                }

                Text(provider.apiKeyHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
        .onAppear {
            hasStoredKey = AIProviderCredentialStore.hasAPIKey(for: provider)
            if settings.selectedModel(for: provider).isEmpty {
                settings.setSelectedModel(provider, provider.defaultModel)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled(provider) },
            set: { newValue in
                settings.setEnabled(provider, newValue)
                onSave()
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.selectedModel(for: provider) },
            set: { newValue in
                settings.setSelectedModel(provider, newValue)
                onSave()
            }
        )
    }

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                SecureField(hasStoredKey && apiKeyDraft.isEmpty ? "••••••••  (saved in Keychain)" : "Paste API key",
                            text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { saveAPIKey() }
                Button("Save") { saveAPIKey() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }

            HStack(spacing: 8) {
                if hasStoredKey {
                    Label("Key saved in Keychain", systemImage: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button("Test") { testConnection() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .disabled(!hasStoredKey && apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasStoredKey {
                    Button("Remove Key") { removeAPIKey() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modelRow: some View {
        HStack(spacing: 8) {
            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            if provider.suggestedModels.isEmpty {
                TextField("Model name", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                Picker("", selection: modelBinding) {
                    ForEach(provider.suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty, hasStoredKey {
                return
            }
            try AIProviderCredentialStore.saveAPIKey(trimmed, for: provider)
            hasStoredKey = !trimmed.isEmpty || AIProviderCredentialStore.hasAPIKey(for: provider)
            if !trimmed.isEmpty {
                apiKeyDraft = ""
            }
            connectionStatus = .unknown
            onSave()
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func removeAPIKey() {
        AIProviderCredentialStore.deleteAPIKey(for: provider)
        apiKeyDraft = ""
        hasStoredKey = false
        connectionStatus = .unknown
        onSave()
    }

    private func testConnection() {
        connectionStatus = .testing
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIProviderCredentialStore.loadAPIKey(for: provider)
            : apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else {
            connectionStatus = .failed("Add an API key first.")
            return
        }

        let model = settings.selectedModel(for: provider)
        Task {
            let result = await CloudAICompletionService.testConnection(provider: provider,
                                                                       apiKey: key,
                                                                       model: model)
            await MainActor.run {
                switch result {
                case .success:
                    if !apiKeyDraft.isEmpty { saveAPIKey() }
                    connectionStatus = .connected
                case .failure(let error):
                    connectionStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
}

struct AIProviderSettingsCard<Content: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )

            if isEnabled {
                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 12)
    }
}
