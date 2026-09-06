import SwiftUI

struct AccountsView: View {
    @Bindable var viewModel: AccountsViewModel

    var body: some View {
        List {
            if viewModel.accounts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Gmail accounts",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Connect an account to include it in your briefing.")
                )
            } else {
                Section("Connected accounts") {
                    ForEach(viewModel.accounts) { account in
                        accountRow(account)
                    }
                }
            }

            Section {
                AsyncButton(action: viewModel.connectGmail) {
                    Label("Add Gmail account", systemImage: "plus")
                }
                .disabled(viewModel.isLoading)
            } footer: {
                Text("InboxBrief requests read-only Gmail access. It cannot send, delete, or modify email.")
            }
        }
        .navigationTitle("Accounts")
        .overlay {
            if viewModel.isLoading && viewModel.accounts.isEmpty {
                ProgressView("Loading accounts…")
            }
        }
        .task { await viewModel.load() }
        .alert(
            "Account problem",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func accountRow(_ account: MailAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account.connectionState == .connected
                  ? "checkmark.circle.fill"
                  : "exclamationmark.circle.fill")
                .foregroundStyle(account.connectionState == .connected ? .green : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayLabel)
                if account.displayName != nil {
                    Text(account.emailAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(account.connectionState == .connected ? "Connected" : "Sign in again")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.connectionState == .authenticationRequired {
                AsyncButton(action: { await viewModel.reconnect(account) }) {
                    Text("Reconnect")
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            AsyncButton(role: .destructive, action: { await viewModel.disconnect(account) }) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
