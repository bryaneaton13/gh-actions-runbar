import RunBarCore
import SwiftUI

struct RepositoryPickerView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var repositories: [GitHubRepositorySummary] = []
    @State private var organizations: [String] = []
    @State private var searchResults: [GitHubRepositorySummary] = []
    @State private var selectedOwner = ""
    @State private var loadedOwners: Set<String> = []
    @State private var isLoading = false
    @State private var isLoadingOwner = false
    @State private var isSearchingRemote = false
    @State private var errorMessage: String?
    @State private var search = ""

    private var trackedIDs: Set<String> {
        Set(store.settings.repositories.map(\.id))
    }

    private var ownerChoices: [String] {
        RepositoryCatalog.ownerChoices(
            viewerLogin: store.login,
            organizations: organizations,
            repositories: repositories
        )
    }

    private var searchQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        searchQuery.count >= RepositoryCatalog.minimumSearchCharacters
    }

    private var remoteSearchKey: String {
        "\(selectedOwner.lowercased())|\(searchQuery.lowercased())|\(organizations.joined(separator: ",").lowercased())"
    }

    private var filtered: [GitHubRepositorySummary] {
        let owner = selectedOwner.isEmpty ? nil : selectedOwner
        let local = RepositoryCatalog.filtered(repositories, search: search, owner: owner)
        guard isSearching else { return local }
        return RepositoryCatalog.merging(local, with: searchResults)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && repositories.isEmpty {
                    ProgressView("Loading recent repositories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, repositories.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await load() }
                        }
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        ownerFilterBar
                        List(filtered) { repo in
                            repositoryRow(repo)
                        }
                        .searchable(text: $search, prompt: "Search repositories")
                    }
                }
            }
            .navigationTitle("Add a repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .task(id: remoteSearchKey) {
                await searchRemoteIfNeeded()
            }
            .onChange(of: selectedOwner) { _, owner in
                guard !owner.isEmpty else { return }
                Task { await loadOwnerIfNeeded(owner) }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var ownerFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("Organization", selection: $selectedOwner) {
                    Text("All organizations").tag("")
                    ForEach(ownerChoices, id: \.self) { owner in
                        Text(ownerLabel(owner)).tag(owner)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Filter by organization")
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoadingOwner || isSearchingRemote {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }

                Text("\(filtered.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filtered.count) repositories")
            }

            Text(catalogHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var catalogHint: String {
        if isSearching {
            return "Search includes GitHub results beyond this recent list."
        }
        if !selectedOwner.isEmpty {
            return "Recently updated repos in \(selectedOwner). Search to find older ones."
        }
        return "Showing \(repositories.count) recently updated repos. Search or pick an organization to find more."
    }

    private func repositoryRow(_ repo: GitHubRepositorySummary) -> some View {
        HStack {
            Image(systemName: repo.isPrivate ? "lock" : "book.closed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.fullName)
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if trackedIDs.contains(repo.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(RunBarTheme.success)
            } else {
                Button {
                    store.addRepository(repo.repository)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(RunBarTheme.inProgress)
                }
                .buttonStyle(.plain)
                .help("Add \(repo.fullName)")
            }
        }
    }

    private func ownerLabel(_ owner: String) -> String {
        if let login = store.login, owner.compare(login, options: .caseInsensitive) == .orderedSame {
            return "\(owner) (you)"
        }
        return owner
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let catalog = try await store.fetchRepositoryBrowserCatalog()
            repositories = catalog.repositories
            organizations = catalog.organizations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadOwnerIfNeeded(_ owner: String) async {
        let key = owner.lowercased()
        guard !loadedOwners.contains(key) else { return }
        loadedOwners.insert(key)
        isLoadingOwner = true
        defer { isLoadingOwner = false }
        do {
            let extra = try await store.fetchRepositories(ownedBy: owner)
            repositories = RepositoryCatalog.merging(repositories, with: extra)
        } catch {
            loadedOwners.remove(key)
        }
    }

    private func searchRemoteIfNeeded() async {
        guard isSearching else {
            searchResults = []
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearchingRemote = true
        defer { isSearchingRemote = false }

        let owners = selectedOwner.isEmpty ? ownerChoices : [selectedOwner]
        do {
            searchResults = try await store.searchRepositories(query: searchQuery, owners: owners)
        } catch {
            searchResults = []
        }
    }
}
