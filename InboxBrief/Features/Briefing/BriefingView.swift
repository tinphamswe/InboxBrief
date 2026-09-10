import SwiftUI

struct BriefingView: View {
    @Bindable var viewModel: BriefingViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    welcome
                case let .loading(previous, progress):
                    loading(previous: previous, progress: progress)
                case let .loaded(brief):
                    briefList(brief)
                case let .empty(brief):
                    emptyBrief(brief)
                case .needsAccounts:
                    needsAccounts
                case let .failed(error, previous):
                    failure(error, previous: previous)
                }
            }
            .navigationTitle("Inbox Brief")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AccountsView(viewModel: accountsViewModel)
                    } label: {
                        Label(
                            "Accounts",
                            systemImage: accountsViewModel.accounts.contains {
                                $0.connectionState == .connected
                            }
                                ? "person.crop.circle.badge.checkmark"
                                : "person.crop.circle"
                        )
                    }
                }
            }
        }
        .alert(
            "Open Gmail",
            isPresented: Binding(
                get: { viewModel.openMessageNotice != nil },
                set: { if !$0 { viewModel.dismissOpenMessageNotice() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissOpenMessageNotice() }
        } message: {
            Text(viewModel.openMessageNotice ?? "")
        }
        .alert(
            "Reminder",
            isPresented: Binding(
                get: { viewModel.reminderNotice != nil },
                set: { if !$0 { viewModel.dismissReminderNotice() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissReminderNotice() }
        } message: {
            Text(viewModel.reminderNotice ?? "")
        }
        .sheet(
            item: Binding(
                get: { viewModel.reminderDraft },
                set: { draft in
                    if draft == nil {
                        viewModel.dismissReminderEditor()
                    }
                }
            )
        ) { draft in
            ReminderEditorSheet(
                draft: draft,
                isSaving: viewModel.isCreatingReminder,
                error: viewModel.reminderError,
                save: { draft in await viewModel.saveReminder(draft) },
                cancel: viewModel.dismissReminderEditor
            )
        }
        .onChange(of: accountsViewModel.accounts) { _, accounts in
            viewModel.updateAccountAvailability(accounts)
        }
        .task {
            await accountsViewModel.load()
            guard accountsViewModel.hasLoadedAccounts else { return }
            viewModel.setInitialAccountAvailability(accountsViewModel.accounts)
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("One brief for every inbox", systemImage: "tray.full")
        } description: {
            Text("Connect Gmail accounts, then check the messages from the last 24 hours that deserve your attention.")
        } actions: {
            checkButton
        }
    }

    private var needsAccounts: some View {
        ContentUnavailableView {
            Label("Connect a Gmail account", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("InboxBrief needs at least one account before it can create a briefing.")
        } actions: {
            NavigationLink("Manage accounts") {
                AccountsView(viewModel: accountsViewModel)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loading(
        previous: InboxBrief?,
        progress: InboxBriefGenerationProgress
    ) -> some View {
        Group {
            if let previous {
                briefList(previous)
                    .overlay { loadingOverlay(progress) }
            } else {
                BriefGenerationProgressView(progress: progress)
                    .frame(maxWidth: 420)
                    .padding()
            }
        }
    }

    private func loadingOverlay(_ progress: InboxBriefGenerationProgress) -> some View {
        ZStack {
            Color(.systemBackground).opacity(0.75)
            BriefGenerationProgressView(progress: progress)
                .padding()
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
        }
    }

    private func briefList(_ brief: InboxBrief) -> some View {
        List {
            Section {
                BriefStatisticsView(statistics: brief.statistics)
            }

            if brief.statistics.isPartial {
                Section { PartialFailureView(failures: brief.statistics.failures) }
            }

            Section("Worth your attention") {
                ForEach(brief.emails) { email in
                    ImportantEmailRow(email: email) {
                        await viewModel.openOriginal(email)
                    } createReminder: {
                        viewModel.beginReminder(for: email)
                    }
                }
            }

            Section {
                checkButton.frame(maxWidth: .infinity)
            } footer: {
                Text("Generated \(brief.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.startRefresh().value }
    }

    private func emptyBrief(_ brief: InboxBrief) -> some View {
        List {
            Section { BriefStatisticsView(statistics: brief.statistics) }

            if brief.statistics.isPartial {
                Section { PartialFailureView(failures: brief.statistics.failures) }
            }

            Section {
                ContentUnavailableView(
                    "You’re all caught up",
                    systemImage: "checkmark.circle",
                    description: Text("No recent emails were judged worthy of your attention.")
                )
            }

            Section { checkButton.frame(maxWidth: .infinity) }
        }
        .refreshable { await viewModel.startRefresh().value }
    }

    private func failure(_ error: BriefingViewModel.PresentationError, previous: InboxBrief?) -> some View {
        Group {
            if let previous {
                List {
                    Section {
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    Section { BriefStatisticsView(statistics: previous.statistics) }
                    Section("Previous briefing") {
                        ForEach(previous.emails) { email in
                            ImportantEmailRow(email: email) {
                                await viewModel.openOriginal(email)
                            } createReminder: {
                                viewModel.beginReminder(for: email)
                            }
                        }
                    }
                    Section { checkButton.frame(maxWidth: .infinity) }
                }
            } else {
                ContentUnavailableView {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    checkButton
                }
            }
        }
    }

    private var checkButton: some View {
        Button(action: { viewModel.startRefresh() }) {
            if viewModel.state.isLoading {
                Label("Checking inboxes", systemImage: "hourglass")
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Check inboxes", systemImage: "sparkles")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.state.isLoading)
        .accessibilityHint("Scans connected inboxes for important email from the last 24 hours")
    }
}
