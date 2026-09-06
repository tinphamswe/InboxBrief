import SwiftUI

struct BriefGenerationProgressView: View {
    let progress: InboxBriefGenerationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Creating your briefing")
                .font(.headline)

            stage(
                title: "Fetching emails",
                systemImage: "tray.and.arrow.down",
                value: fetchingValue,
                status: fetchingStatus
            )
            stage(
                title: "AI analysis",
                systemImage: "sparkles",
                value: analysisValue,
                status: analysisStatus
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func stage(
        title: String,
        systemImage: String,
        value: Double,
        status: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .accessibilityLabel(title)
                .accessibilityValue(status)
        }
    }

    private var fetchingValue: Double {
        switch progress {
        case let .fetching(value): value.fractionCompleted
        case .analyzing: 1
        }
    }

    private var fetchingStatus: String {
        switch progress {
        case let .fetching(value):
            value.total == 0 ? "Starting…" : "\(value.completed) of \(value.total) inboxes"
        case .analyzing:
            "Done"
        }
    }

    private var analysisValue: Double {
        switch progress {
        case .fetching: 0
        case let .analyzing(value): value.fractionCompleted
        }
    }

    private var analysisStatus: String {
        switch progress {
        case .fetching:
            "Waiting"
        case let .analyzing(value):
            value.total == 0 ? "No emails" : "\(value.completed) of \(value.total) emails"
        }
    }
}

struct BriefStatisticsView: View {
    let statistics: InboxBriefStatistics

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statistic(value: statistics.accountsSucceeded, label: accountLabel)
            Divider()
            statistic(value: statistics.emailsScanned, label: "scanned")
            Divider()
            statistic(value: statistics.importantEmails, label: "important")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accountLabel: String {
        statistics.accountsSucceeded == statistics.accountsAttempted
            ? "inboxes"
            : "of \(statistics.accountsAttempted) inboxes"
    }

    private var accessibilitySummary: String {
        "\(statistics.accountsSucceeded) of \(statistics.accountsAttempted) inboxes checked, "
            + "\(statistics.emailsScanned) emails scanned, "
            + "\(statistics.importantEmails) worth your attention"
    }

    private func statistic(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PartialFailureView: View {
    let failures: [AccountScanFailure]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Some inboxes weren’t checked", systemImage: "exclamationmark.triangle")
                .font(.headline)
            ForEach(failures) { failure in
                Text("\(failure.account.emailAddress): \(description(for: failure.reason))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func description(for reason: AccountScanFailure.Reason) -> String {
        switch reason {
        case .authenticationExpired: "sign in again"
        case .offline: "no internet connection"
        case .providerUnavailable: "Gmail unavailable"
        case .invalidResponse: "unexpected Gmail response"
        case .unknown: "unknown error"
        }
    }
}

struct ImportantEmailRow: View {
    let email: AnalyzedEmail
    let open: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(email.message.sender.displayName)
                    .font(.headline)
                Spacer()
                Text(email.message.receivedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(email.message.subject)
                .font(.subheadline.weight(.semibold))

            Text(email.assessment.summary)

            if email.assessment.actionRequired, let action = email.assessment.actionDescription {
                Label(action, systemImage: "checklist")
                    .font(.subheadline)
            }

            HStack {
                Label(email.message.accountAddress, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                AsyncButton(action: open) {
                    Label("Open Email", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .disabled(email.message.originalTarget == nil)
                .accessibilityHint("Opens Gmail and copies the exact message search when needed")
            }
        }
        .padding(.vertical, 6)
    }
}
