import Foundation
import Observation

@MainActor
@Observable
final class BriefingViewModel {
    enum State: Equatable {
        case idle
        case loading(previous: InboxBrief?, progress: InboxBriefGenerationProgress)
        case loaded(InboxBrief)
        case empty(InboxBrief)
        case needsAccounts
        case failed(PresentationError, previous: InboxBrief?)

        var brief: InboxBrief? {
            switch self {
            case let .loading(previous, _), let .failed(_, previous): previous
            case let .loaded(brief), let .empty(brief): brief
            case .idle, .needsAccounts: nil
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    enum PresentationError: Equatable {
        case accountsUnavailable
        case inboxesUnavailable
        case analysisUnavailable(EmailAnalysisFailure)
        case unknown

        var title: String {
            switch self {
            case .accountsUnavailable: "Accounts unavailable"
            case .inboxesUnavailable: "Couldn’t check inboxes"
            case let .analysisUnavailable(failure): failure.title
            case .unknown: "Something went wrong"
            }
        }

        var message: String {
            switch self {
            case .accountsUnavailable: "InboxBrief couldn’t load your connected accounts."
            case .inboxesUnavailable: "None of your inboxes could be checked. Try again shortly."
            case let .analysisUnavailable(failure): failure.message
            case .unknown: "Please try checking your inboxes again."
            }
        }
    }

    enum ReminderPresentationError: Equatable {
        case accessDenied
        case unavailable
        case defaultListUnavailable
        case saveFailed

        var message: String {
            switch self {
            case .accessDenied:
                "Allow Reminders access for InboxBrief in Settings, then try again."
            case .unavailable:
                "Reminders is currently unavailable. Try again shortly."
            case .defaultListUnavailable:
                "Set up a default Reminders list, then try again."
            case .saveFailed:
                "InboxBrief couldn’t save the reminder. Try again."
            }
        }
    }

    private let generateBrief: GenerateInboxBriefUseCase
    private let messageOpener: any OriginalMessageOpening
    private let createReminderDraft: CreateReminderDraftUseCase
    private let reminderCreator: any ReminderCreating

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    private(set) var state: State = .idle
    private(set) var openMessageNotice: String?
    private(set) var reminderDraft: ReminderDraft?
    private(set) var reminderError: ReminderPresentationError?
    private(set) var isCreatingReminder = false
    private(set) var reminderNotice: String?

    init(
        generateBrief: GenerateInboxBriefUseCase,
        messageOpener: any OriginalMessageOpening,
        createReminderDraft: CreateReminderDraftUseCase,
        reminderCreator: any ReminderCreating
    ) {
        self.generateBrief = generateBrief
        self.messageOpener = messageOpener
        self.createReminderDraft = createReminderDraft
        self.reminderCreator = reminderCreator
    }

    @discardableResult
    func startRefresh() -> Task<Void, Never> {
        if let refreshTask {
            return refreshTask
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await refresh()
            refreshTask = nil
        }
        refreshTask = task
        return task
    }

    func refresh() async {
        let previous = state.brief
        state = .loading(
            previous: previous,
            progress: .fetching(OperationProgress(completed: 0, total: 0))
        )

        do {
            let brief = try await generateBrief.execute { [weak self] progress in
                await self?.updateLoadingProgress(progress, previous: previous)
            }
            state = brief.emails.isEmpty ? .empty(brief) : .loaded(brief)
        } catch is CancellationError {
            state = previous.map(State.loaded) ?? .idle
        } catch let error as BriefGenerationError {
            state = map(error, previous: previous)
        } catch {
            state = .failed(.unknown, previous: previous)
        }
    }

    func openOriginal(_ email: AnalyzedEmail) async {
        guard let target = email.message.originalTarget else {
            openMessageNotice = "The original message can’t be opened."
            return
        }
        let didOpen = await messageOpener.open(target)
        openMessageNotice = didOpen
            ? (target.searchQuery == nil ? nil : "Gmail search copied to the clipboard.")
            : "Gmail couldn’t be opened."
    }

    func dismissOpenMessageNotice() {
        openMessageNotice = nil
    }

    func beginReminder(for email: AnalyzedEmail) {
        reminderDraft = createReminderDraft.execute(for: email)
        reminderError = nil
    }

    func dismissReminderEditor() {
        guard !isCreatingReminder else { return }
        reminderDraft = nil
        reminderError = nil
    }

    func saveReminder(_ draft: ReminderDraft) async {
        guard reminderDraft?.id == draft.id, !isCreatingReminder else { return }

        isCreatingReminder = true
        reminderError = nil
        defer { isCreatingReminder = false }

        do {
            try await reminderCreator.create(draft)
            reminderDraft = nil
            reminderNotice = "Reminder created."
        } catch let error as ReminderCreationError {
            reminderError = map(error)
        } catch {
            reminderError = .unavailable
        }
    }

    func dismissReminderNotice() {
        reminderNotice = nil
    }

    /// Chooses the first-run onboarding state from successfully loaded local account metadata.
    func setInitialAccountAvailability(_ accounts: [MailAccount]) {
        guard case .idle = state,
              !accounts.contains(where: { $0.connectionState == .connected }) else {
            return
        }
        state = .needsAccounts
    }

    /// Returns the onboarding screen to its initial state after an account is
    /// connected from account management. The user can then explicitly choose
    /// when to generate their first briefing.
    func updateAccountAvailability(_ accounts: [MailAccount]) {
        guard case .needsAccounts = state,
              accounts.contains(where: { $0.connectionState == .connected }) else {
            return
        }
        state = .idle
    }

    private func map(_ error: BriefGenerationError, previous: InboxBrief?) -> State {
        switch error {
        case .noConnectedAccounts:
            return .needsAccounts
        case .accountsUnavailable:
            return .failed(.accountsUnavailable, previous: previous)
        case .allAccountsFailed:
            return .failed(.inboxesUnavailable, previous: previous)
        case let .analysisUnavailable(failure):
            return .failed(.analysisUnavailable(failure), previous: previous)
        }
    }

    private func updateLoadingProgress(
        _ progress: InboxBriefGenerationProgress,
        previous: InboxBrief?
    ) {
        guard state.isLoading else { return }
        state = .loading(previous: previous, progress: progress)
    }

    private func map(_ error: ReminderCreationError) -> ReminderPresentationError {
        switch error {
        case .accessDenied: return .accessDenied
        case .unavailable: return .unavailable
        case .defaultListUnavailable: return .defaultListUnavailable
        case .saveFailed: return .saveFailed
        }
    }
}

private extension EmailAnalysisFailure {
    var title: String {
        switch self {
        case .configurationMissing: "AI isn’t configured"
        case .authenticationFailed: "AI credentials rejected"
        case .permissionDenied: "AI access denied"
        case .rateLimited: "AI usage limit reached"
        case .offline: "No internet connection"
        case .serviceUnavailable: "AI service unavailable"
        case .invalidRequest: "AI request rejected"
        case .invalidResponse, .refused: "AI response couldn’t be used"
        }
    }

    var message: String {
        switch self {
        case .configurationMissing:
            "Add an AI connection to this build, then try again."
        case .authenticationFailed:
            "The configured API key was rejected. Create a valid project key and update the private Run environment variable."
        case .permissionDenied:
            "The configured API project does not have permission to use this AI request or model."
        case .rateLimited:
            "The AI project is rate-limited or has no available usage credit. Check its limits and billing, then try again."
        case .offline:
            "Reconnect to the internet and try checking your inboxes again."
        case .serviceUnavailable:
            "The AI service is temporarily unavailable. Try again shortly."
        case .invalidRequest:
            "The AI service rejected the request. Check that the configured model is available to the API project."
        case .invalidResponse:
            "The AI returned an incomplete or malformed briefing, so InboxBrief did not show potentially misleading results."
        case .refused:
            "The AI declined to analyze this batch. No email was silently classified as unimportant."
        }
    }
}
