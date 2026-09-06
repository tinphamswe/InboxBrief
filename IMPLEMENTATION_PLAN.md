# InboxBrief V1 Implementation Plan

## Product Goal

InboxBrief is a small email-triage utility. It connects multiple Gmail accounts, scans messages received in the previous 24 hours, asks an AI classifier for structured importance and actionability assessments, and presents one unified briefing. It deliberately does not behave like a full email client.

## Technical Baseline

- SwiftUI application with an iOS 17 minimum deployment target.
- Swift 6 language mode with complete concurrency checking.
- Observation (`@Observable`) for presentation state.
- One application target, one unit-test target, and one UI-test target.
- Constructor injection from a single `AppContainer` composition root.
- Swift Testing for behavioral unit tests; XCTest for UI tests.

## Architecture

Dependencies point inward:

```text
SwiftUI Views -> @MainActor ViewModels -> Domain Use Cases -> Domain Boundaries
                                                                  ^
                                                                  |
                                        Gmail / OAuth / AI / storage adapters
```

The Domain layer contains provider-independent models and orchestration. Presentation does not know about URLSession, Gmail DTOs, OAuth tokens, Keychain, or OpenAI transport. Infrastructure maps external representations into Domain values.

## Source Layout

```text
InboxBrief/
  App/
  Domain/
    Models/
    Errors/
    Boundaries/
    UseCases/
  Features/
    Briefing/
    Accounts/
  Infrastructure/
    Authentication/
    Gmail/
      DTOs/
      Mapping/
    AI/
    Networking/
    Persistence/
    ExternalURLs/
  Support/

InboxBriefTests/
  Domain/
  Presentation/
  Infrastructure/
  TestDoubles/
  Fixtures/
```

## Core Domain

Models:

- `MailAccount`: stable account ID, provider, address, display name, and connection state.
- `EmailMessage`: provider-independent identity, account, sender, subject, receipt date, a minimized plaintext excerpt, and an optional original-message target.
- `EmailAssessment`: importance, priority, concise summary, action requirement, action description, and a typed reason.
- `AnalyzedEmail`: an email plus its validated assessment.
- `AccountScanFailure`: failed account and a safe typed reason.
- `InboxBrief`: scan window, statistics, important messages, and generation date.

External boundaries:

- `AccountGateway`: list, connect, reconnect, and disconnect accounts.
- `RecentEmailFetching`: fetch recent normalized messages for an account.
- `EmailAnalyzing`: analyze minimized messages and return typed assessments.

The boundaries are `Sendable` and async so deterministic fakes can replace them without changing production APIs.

## Generate Inbox Brief Workflow

`GenerateInboxBriefUseCase` will:

1. Obtain connected accounts.
2. Return a typed no-accounts outcome if none exist.
3. Calculate an exact 24-hour scan window using an injected date source.
4. Fetch accounts concurrently with a throwing task group.
5. Convert independent provider failures into account outcomes while propagating cancellation.
6. Preserve all successful account results.
7. Fail if every attempted account failed.
8. Aggregate normalized messages and create minimized AI inputs.
9. Skip AI work if no messages were found.
10. Analyze candidates behind `EmailAnalyzing`.
11. Validate one assessment per candidate and keep important results.
12. Sort by priority and then newest receipt date.
13. Return statistics, partial failures, important messages, and generation time.

An AI failure is not treated as “nothing is important”; it becomes an explicit `analysisUnavailable` failure.

## Gmail and OAuth

- OAuth authorization-code flow with PKCE; Gmail passwords are never requested.
- Scopes: `openid`, `email`, and `gmail.readonly` only.
- Explicit account selection supports multiple independent Gmail identities.
- Each account has its own refreshable authorization state stored in Keychain.
- Only non-secret account display metadata is stored outside Keychain.
- Gmail requests use native `URLSession` and async/await.
- `users.messages.list` uses the Inbox label and an epoch `after:` query, follows pagination, and is followed by bounded concurrent detail requests.
- `internalDate` is checked locally to enforce the exact cutoff.
- MIME parsing prefers `text/plain`, uses sanitized HTML-derived text as a fallback, and never downloads attachments for AI.
- DTOs and Gmail IDs remain inside Infrastructure until mapped into Domain values.

For strict documented-link behavior, V1 opens the standard Gmail HTTPS site for the selected account and copies a documented `rfc822msgid:` query. It will not use an undocumented custom URL scheme or pretend Gmail REST supplies a direct permalink.

## AI Connection

The rest of the application depends only on:

```swift
protocol EmailAnalyzing: Sendable {
    func analyze(_ messages: [EmailAnalysisInput]) async throws -> [EmailAssessment]
}
```

V1 has two composition modes:

1. **Local Debug**: replaceable FIT-AI, Gemini, and OpenAI adapters fulfill the same typed analysis boundary. FIT-AI is preferred when multiple local keys exist and uses the documented OpenAI-compatible Chat Completions endpoint with forced function calling. A developer key is injected through an uncommitted, user-only Xcode launch environment variable. It is never placed in source, Info.plist, an xcconfig copied into the bundle, logs, or version control.
2. **Distribution**: the same domain boundary is fulfilled by a small app-owned HTTPS analysis proxy. The proxy holds the provider secret and returns the same provider-neutral JSON contract. Building or operating that production proxy is outside this iOS V1.

Release builds fail closed with a clear configuration state if no proxy endpoint is configured; they never fall back to a bundled provider key.

The request contains only an opaque message ID, sender, subject, received time, and a normalized/truncated plaintext excerpt. It excludes access tokens, raw MIME, attachments, full HTML, and unrelated headers.

FIT-AI latency is bounded with batches of eight, up to eight concurrent batch requests for the V1 instructor key, and 2,000-character excerpts. Unimportant assessments return empty summaries to minimize generation time. The concurrency limit is configurable for lower-tier keys, clamped to the documented maximum, and preserves bounded 429 backoff.

The response schema contains:

- message ID
- important flag
- priority (`low`, `medium`, `high`, `critical`)
- concise summary
- action-required flag
- optional action description
- typed importance reason

The adapter rejects malformed JSON, unknown or missing message IDs, duplicate results, incomplete responses, provider refusals, and invalid action invariants.

## Presentation

`BriefingViewModel` exposes idle, loading, loaded, empty, and failed states. Loading carries typed workflow progress. The UI first reports completed Gmail inbox fetches, then marks fetching complete and reports completed AI-analyzed emails with native linear progress bars. Partial inbox failure is a successful result with visible failure context. Refresh calls the same use case and keeps the previous briefing visible beneath the progress overlay.

The main screen emphasizes:

- accounts checked
- emails scanned
- messages worth attention
- a primary **Check inboxes** action
- important-email rows containing sender, subject, account, time, summary, and action
- a visible partial-failure notice

The accounts screen supports listing, adding, reconnecting, and removing Gmail accounts. Native SwiftUI controls, Dynamic Type, VoiceOver labels, and non-color-only status are used.

## Persistence and Privacy

- OAuth state and refresh tokens: Keychain, one item per account.
- Account metadata: a small Codable value in UserDefaults.
- Email bodies and briefings: memory only in V1.
- Diagnostics: sparse OSLog events with private/redacted fields.
- Never log tokens, email bodies, AI payloads, or raw transport errors containing sensitive data.

## Error Model

Infrastructure errors are translated into a small set of application outcomes:

- authentication expired
- offline
- Gmail unavailable
- invalid provider response
- AI unavailable or malformed
- account storage unavailable
- partial account failure

Raw OAuth, HTTP, decoding, and Keychain errors do not reach SwiftUI.

## Testing

- Main use case: aggregation, sorting, important filtering, no accounts, no mail, partial account failure, complete account failure, AI failure, and cancellation.
- ViewModel: initial, loading, success, empty, partial, error, and refresh.
- Gmail: request construction, mapping, MIME extraction, exact cutoff, pagination, malformed data, auth failure, and network errors.
- AI: request minimization, structured decoding, malformed/incomplete/duplicate output, refusal, provider errors, and mapping.
- Authentication: multiple accounts, addition/removal, missing or expired credentials, refresh success, and refresh failure.
- UI: deterministic launch configuration with no live services.

Tests use immediate fakes or explicitly controlled continuations. They never use arbitrary sleeps, real accounts, real network calls, real AI, or real Keychain.

## Incremental Delivery

1. Project settings, domain models, central use case, and behavioral tests.
2. Briefing ViewModel and native briefing UI using deterministic preview data.
3. Account management, OAuth, secure storage, and tests.
4. Gmail transport, pagination, mapping, MIME parsing, and tests.
5. Structured AI adapter, local-only configuration, and tests.
6. Composition, UI test mode, documentation, full build/test pass, and final architecture/security audit.

Every slice must compile and pass its relevant tests before the next slice begins.
