import AppKit
import RunBarCore
import SwiftUI

struct WorkflowDispatchView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var context: WorkflowDispatchContext?
    @State private var selectedRef = ""
    @State private var values: [String: String] = [:]
    @State private var ignoreNextRefChange = false

    var body: some View {
        NavigationStack {
            Group {
                if store.dispatchRequest == nil {
                    Text("Choose Run workflow from a pinned row.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Run workflow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.clearDispatch()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run workflow") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 440, minHeight: 280, idealHeight: 390)
        .task(id: store.dispatchRequest?.id) {
            values = [:]
            context = nil
            errorMessage = nil
            await load(ref: store.dispatchRequest?.preferredRef, userChangedRef: false)
        }
    }

    @ViewBuilder
    private var form: some View {
        Form {
            if let pin = store.dispatchRequest?.pin {
                Section {
                    LabeledContent("Workflow") {
                        Text(pin.workflowName)
                            .lineLimit(1)
                    }
                    LabeledContent("Repository") {
                        Text(pin.repository.fullName)
                            .font(.body.monospaced())
                    }
                }
            }

            if isLoading && context == nil {
                Section {
                    ProgressView("Loading workflow…")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(RunBarTheme.failure)
                    if Self.needsWorkflowScope(errorMessage) {
                        Text("Run `gh auth refresh -s workflow` in Terminal, then try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Copy gh auth refresh") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("gh auth refresh -s workflow", forType: .string)
                        }
                    }
                }
            }

            if let context {
                Section {
                    Picker("Use workflow from", selection: $selectedRef) {
                        ForEach(pickerBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .disabled(context.branches.isEmpty || isLoading)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                } footer: {
                    Text("Inputs come from this branch, the same as Run workflow on GitHub.")
                }

                if !context.spec.supportsDispatch {
                    Section {
                        Text("This workflow has no workflow_dispatch trigger on this branch.")
                            .foregroundStyle(.secondary)
                        if let url = context.githubURL {
                            Button("Open on GitHub") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else if context.spec.inputs.isEmpty {
                    Section {
                        Text("No inputs. This starts the workflow on the selected branch.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Inputs") {
                        ForEach(context.spec.inputs) { input in
                            inputRow(input, environments: context.environments)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isSubmitting)
        .onChange(of: selectedRef) { _, newValue in
            if ignoreNextRefChange {
                ignoreNextRefChange = false
                return
            }
            guard context != nil, GitRef.isValid(newValue) else { return }
            Task { await load(ref: newValue, userChangedRef: true) }
        }
    }

    private var pickerBranches: [String] {
        var branches = context?.branches ?? []
        if GitRef.isValid(selectedRef), !branches.contains(selectedRef) {
            branches.insert(selectedRef, at: 0)
        }
        return branches
    }

    private var canSubmit: Bool {
        guard !isLoading, !isSubmitting, let context, context.spec.supportsDispatch else {
            return false
        }
        guard GitRef.isValid(selectedRef) else { return false }
        return WorkflowDispatchValues.missingRequired(spec: context.spec, values: values).isEmpty
    }

    @ViewBuilder
    private func inputRow(_ input: WorkflowInput, environments: [String]) -> some View {
        switch input.type {
        case .boolean:
            Toggle(input.label, isOn: booleanBinding(input))
                .toggleStyle(.checkbox)
        case .choice:
            picker(input, options: input.options)
        case .environment:
            picker(input, options: input.options.isEmpty ? environments : input.options)
        case .string, .number:
            TextField(input.required ? "\(input.label) (required)" : input.label, text: stringBinding(input))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func picker(_ input: WorkflowInput, options: [String]) -> some View {
        Picker(input.label, selection: stringBinding(input)) {
            if input.required == false {
                Text("").tag("")
            }
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }

    private func stringBinding(_ input: WorkflowInput) -> Binding<String> {
        Binding(
            get: { values[input.name] ?? input.resolvedDefault },
            set: { values[input.name] = $0 }
        )
    }

    private func booleanBinding(_ input: WorkflowInput) -> Binding<Bool> {
        Binding(
            get: { WorkflowDispatchValues.isTrue(values[input.name] ?? input.resolvedDefault) },
            set: { values[input.name] = $0 ? "true" : "false" }
        )
    }

    private func load(ref: String?, userChangedRef: Bool) async {
        guard store.dispatchRequest != nil else { return }
        isLoading = true
        if !userChangedRef {
            errorMessage = nil
        }
        defer { isLoading = false }
        do {
            let loaded = try await store.loadDispatchContext(ref: ref)
            context = loaded
            let preferred = GitRef.parse(ref ?? "") ?? loaded.defaultBranch
            let nextRef = loaded.branches.contains(preferred) ? preferred : loaded.defaultBranch
            if selectedRef != nextRef {
                ignoreNextRefChange = true
                selectedRef = nextRef
            }
            values = WorkflowDispatchValues.merging(values, with: loaded.spec)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let fields = context.map { WorkflowDispatchValues.fields(spec: $0.spec, values: values) } ?? []
            try await store.dispatchWorkflow(ref: selectedRef, inputs: fields)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func needsWorkflowScope(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("workflow scope")
            || lowered.contains("resource not accessible")
            || (lowered.contains("403") && lowered.contains("workflow"))
    }
}
