import AppKit
import RunBarCore
import SwiftUI

struct SettingsView: View {
    let store: AppStore
    @State private var repositoryInput = ""
    @State private var repositoryInputError: String?
    @State private var showRepositoryPicker = false
    @State private var showPinEditor = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                repositoriesSection
                filtersSection
                pinsSection
                generalSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 540, minHeight: 520)
        .sheet(isPresented: $showRepositoryPicker) {
            RepositoryPickerView(store: store)
        }
        .sheet(isPresented: $showPinEditor) {
            PinEditorView(store: store)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            switch store.authState {
            case .checking:
                LabeledContent("GitHub CLI") {
                    ProgressView().controlSize(.small)
                }
            case .missingCLI:
                Label("gh is not installed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Install with `brew install gh`, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check again") {
                    Task { await store.refreshAuth() }
                }
            case let .loggedOut(message):
                Label("gh is not signed in", systemImage: "person.crop.circle.badge.questionmark")
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text("Run `gh auth login` in Terminal, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check again") {
                    Task { await store.refreshAuth() }
                }
            case let .ready(login):
                LabeledContent("Signed in as") {
                    Text(login)
                        .font(.body.monospaced())
                }
                LabeledContent("Status") {
                    Text("gh ok")
                        .foregroundStyle(RunBarTheme.success)
                }
            }
        }
    }

    private var repositoriesSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("owner/name", text: $repositoryInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRepository)
                Button("Add", action: addRepository)
                    .disabled(repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let repositoryInputError {
                Text(repositoryInputError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                showRepositoryPicker = true
            } label: {
                Label("Browse GitHub repos", systemImage: "magnifyingglass")
            }
            .disabled(!store.authState.isReady)

            if store.settings.repositories.isEmpty {
                Text("No tracked repositories yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.settings.repositories) { repository in
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                        Text(repository.fullName)
                            .font(.body.monospaced())
                        Spacer()
                        Button {
                            store.removeRepository(repository)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(RunBarTheme.failure)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
            }
        } header: {
            Text("Repositories")
        } footer: {
            Text("Poll only these repositories. Browse personal, organization, and collaborator repos you can access.")
        }
    }

    private var filtersSection: some View {
        Section {
            Toggle("Only my runs", isOn: onlyMyRunsBinding)
            Text("Uses `gh run list -u` so you see commits, PRs, and dispatches you triggered.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(WorkflowEvent.allCases) { event in
                Toggle(isOn: eventBinding(event)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                        Text(event.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Filters")
        } footer: {
            Text("Pinned workflows ignore these filters and always appear at the top of the panel.")
        }
    }

    private var pinsSection: some View {
        Section {
            Button {
                showPinEditor = true
            } label: {
                Label("Pin a workflow", systemImage: "pin")
            }
            .disabled(store.settings.repositories.isEmpty && !store.authState.isReady)

            if store.settings.pins.isEmpty {
                Text("Pin Deploy to prod (or any workflow) to always show its latest run.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.settings.pins) { pin in
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(RunBarTheme.inProgress)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pin.workflowName)
                            Text(pin.repository.fullName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.removePin(pin)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(RunBarTheme.failure)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Pinned workflows")
        }
    }

    private var generalSection: some View {
        Section("General") {
            LabeledContent("Refresh") {
                Text(store.summary.activeRunCount > 0 || store.isPopoverOpen ? "15s while active" : "45s while idle")
            }

            Toggle("Launch at login", isOn: launchAtLoginBinding)

            Button("Open config folder") {
                let directory = SettingsStore.configDirectory
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(directory)
            }
        }
    }

    private var onlyMyRunsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.watchRule.onlyMyRuns },
            set: { enabled in
                var rule = store.settings.watchRule
                rule.onlyMyRuns = enabled
                store.updateWatchRule(rule)
            }
        )
    }

    private func eventBinding(_ event: WorkflowEvent) -> Binding<Bool> {
        Binding(
            get: { store.settings.watchRule.events.contains(event) },
            set: { enabled in
                var rule = store.settings.watchRule
                if enabled {
                    rule.events.insert(event)
                } else {
                    rule.events.remove(event)
                }
                store.updateWatchRule(rule)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        )
    }

    private func addRepository() {
        do {
            try store.addRepository(from: repositoryInput)
            repositoryInput = ""
            repositoryInputError = nil
        } catch {
            repositoryInputError = error.localizedDescription
        }
    }
}

struct PinEditorView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRepo: Repository?
    @State private var workflows: [GhWorkflowDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var workflowName = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Repository", selection: $selectedRepo) {
                    Text("Choose a repo").tag(Optional<Repository>.none)
                    ForEach(store.settings.repositories) { repository in
                        Text(repository.fullName).tag(Optional(repository))
                    }
                }
                .onChange(of: selectedRepo) { _, _ in
                    Task { await loadWorkflows() }
                }

                if isLoading {
                    ProgressView("Loading workflows…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if !workflows.isEmpty {
                    Picker("Workflow", selection: $workflowName) {
                        Text("Choose a workflow").tag("")
                        ForEach(workflows) { workflow in
                            Text(workflow.name).tag(workflow.name)
                        }
                    }
                } else {
                    TextField("Workflow name", text: $workflowName)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Pins ignore actor and event filters. Use this for Deploy to prod and other always-on workflows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle("Pin a workflow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin") { pin() }
                        .disabled(selectedRepo == nil || workflowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                selectedRepo = store.settings.repositories.first
                Task { await loadWorkflows() }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }

    private func loadWorkflows() async {
        guard let selectedRepo else {
            workflows = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            workflows = try await store.fetchWorkflows(in: selectedRepo)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
            workflows = []
        }
    }

    private func pin() {
        guard let selectedRepo else { return }
        let name = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addPin(PinnedWorkflow(repository: selectedRepo, workflowName: name))
        dismiss()
    }
}
