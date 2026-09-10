# InboxBrief

InboxBrief is a small iOS email-triage utility for people who manage several Gmail accounts. It scans recent mail, asks an AI service which messages deserve attention, and presents one unified briefing.

> Instead of checking three or four inboxes, see the few emails that actually need your attention.

InboxBrief is deliberately not an email client. It does not compose, reply, archive, delete, manage labels, or change read state.

## What V1 does

- Connects multiple Gmail accounts using OAuth—never Gmail passwords.
- Fetches messages received during the previous 24 hours.
- Keeps results from healthy accounts when another account fails.
- Sends minimized plaintext excerpts to a provider-neutral AI boundary.
- Returns strongly typed importance, priority, summary, and action information.
- Filters low-value promotions, newsletters, social notifications, and routine security confirmations.
- Shows determinate progress for Gmail fetching and AI analysis.
- Opens Gmail through its supported HTTPS interface and copies an exact `rfc822msgid:` search when needed.

## Requirements

- macOS with Xcode 26 or newer
- iOS 17 or newer
- A Google Cloud project with the Gmail API enabled
- A FIT-AI key for the default development configuration, or a Gemini/OpenAI key

No third-party package manager or dependency installation step is required.

## Project setup

### 1. Clone and open the project

```sh
git clone https://github.com/tinphamswe/InboxBrief.git
cd InboxBrief
open InboxBrief.xcodeproj
```

In Xcode, select the `InboxBrief` target under **Signing & Capabilities**, choose your development team, and use a bundle identifier you control.

### 2. Configure Google OAuth

In Google Cloud Console:

1. Create or select a project.
2. Enable the Gmail API.
3. Configure the OAuth consent screen.
4. While the app is in testing mode, add every Gmail address you intend to connect as a test user.
5. Create an OAuth client with application type **iOS**.
6. Enter the exact bundle identifier used by the Xcode target.
7. Copy the generated client ID. Its reversed form is the callback scheme. For example, client ID `123.apps.googleusercontent.com` uses callback scheme `com.googleusercontent.apps.123`.

In Xcode, open the target’s **Build Settings** and update both user-defined settings for Debug and Release:

- `GOOGLE_CLIENT_ID`
- `GOOGLE_REDIRECT_SCHEME`

They are injected into [Info.plist](InboxBrief/Info.plist); do not add a second URL type manually. The checked-in client ID is not a password or API secret, but it belongs to the original Google Cloud project. A fork normally needs its own OAuth client because the bundle ID and authorized test users must match.

InboxBrief requests only `openid`, `email`, and `https://www.googleapis.com/auth/gmail.readonly`. Refresh tokens and OAuth state are stored per account in Keychain. Account display metadata is stored separately without message content.

Google classifies `gmail.readonly` as a restricted scope. Test-mode grants may expire, and public distribution requires Google’s applicable OAuth verification, data-use, and security-assessment process.

### 3. Create a private local scheme

The shared `InboxBrief` scheme intentionally contains no API credentials.

1. Open **Product → Scheme → Manage Schemes**.
2. Duplicate `InboxBrief` and name the copy `InboxBrief Local`.
3. Make sure **Shared** is unchecked for the copy.
4. Open **Product → Scheme → Edit Scheme** for `InboxBrief Local`.
5. Select **Run → Arguments → Environment Variables**.

Per-user Xcode scheme data is ignored by Git, so local values remain outside commits. Still review staged changes before every push.

### 4. Configure AI

FIT-AI is the preferred Debug provider for this project. Add these environment variables to the private scheme:

| Variable | Value |
| --- | --- |
| `INBOXBRIEF_AI_PROVIDER` | `fitai` |
| `INBOXBRIEF_FITAI_API_KEY` | Your FIT-AI key |
| `INBOXBRIEF_FITAI_MODEL` | `Qwen3.6-27B` |

The default gateway is `https://api-fit.hcmus.edu.vn/v1`. Only add `INBOXBRIEF_FITAI_BASE_URL` when your key was issued for a different documented gateway.

The default analysis concurrency is eight batches for the instructor-key limits. Set `INBOXBRIEF_FITAI_MAX_CONCURRENT_BATCHES=3` for a student key or another lower-concurrency allocation.

Alternative development providers are also supported:

| Provider | Required variables |
| --- | --- |
| Gemini | `INBOXBRIEF_AI_PROVIDER=gemini`, `INBOXBRIEF_GEMINI_API_KEY`, optionally `INBOXBRIEF_GEMINI_MODEL` |
| OpenAI | `INBOXBRIEF_AI_PROVIDER=openai`, `INBOXBRIEF_OPENAI_API_KEY`, optionally `INBOXBRIEF_OPENAI_MODEL` |

Provider keys are read only by Debug builds. Never place them in source code, `Info.plist`, target build settings, a shared scheme, or an xcconfig file that will be committed.

### 5. Run the app

1. Select the `InboxBrief Local` scheme and an iOS 17+ simulator or device.
2. Build and run.
3. Open account management and choose **Add Gmail account**.
4. Complete Google OAuth in the system authentication session.
5. Add any other accounts, then choose **Check inboxes**.

The progress panel first reports completed Gmail inboxes and then completed AI-analyzed emails. Fetching is measured by account because Gmail does not provide a stable cross-account message total before each listing completes.

## Build and test from the command line

List available simulators if the example device is unavailable:

```sh
xcrun simctl list devices available
```

Run the deterministic test suite:

```sh
xcodebuild \
  -project InboxBrief.xcodeproj \
  -scheme InboxBrief \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO \
  test
```

Tests use immediate fakes for Gmail, OAuth, AI, networking, time, and credential storage. They require no real accounts, keys, network access, or arbitrary delays.

## Continuous integration

GitHub Actions runs the shared `InboxBrief` scheme on every pull request to `main`, every push to `main`, and on demand. It resolves Swift packages, runs the simulator test suite, and uploads the `.xcresult` bundle for inspection. CI requires no API keys, OAuth credentials, signing certificate, or App Store Connect access.

## Architecture

InboxBrief uses SwiftUI, Observation, MVVM, and Swift Concurrency in a single app target:

```text
SwiftUI Views
    ↓
@MainActor ViewModels
    ↓
Domain use cases and provider-neutral models
    ↓
Infrastructure implementations (Gmail, OAuth, AI, Keychain, URLSession)
```

Dependencies are assembled in `AppContainer`. The central `GenerateInboxBriefUseCase` concurrently fetches independent accounts, retains partial successes, analyzes normalized messages, validates complete AI coverage, filters and sorts important mail, and returns scan statistics with the briefing.

Source layout:

- `InboxBrief/App` — application configuration and composition root
- `InboxBrief/Features` — SwiftUI views and ViewModels
- `InboxBrief/Domain` — provider-neutral models, boundaries, errors, and use cases
- `InboxBrief/Infrastructure` — Gmail, OAuth, AI, persistence, networking, and external URLs
- `InboxBrief/Support` — small deterministic support types
- `InboxBriefTests` — domain, infrastructure, and presentation behavior

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the architectural decisions and delivery plan.

## AI behavior and privacy

The app sends only an opaque message ID, sender, subject, received time, and a normalized plaintext excerpt capped at 2,000 characters. It does not send OAuth tokens, attachments, raw MIME, or full HTML payloads. Email content is not persisted or logged by the app.

FIT-AI analyzes batches of up to eight messages with bounded parallel requests and bounded retry for HTTP 429. Results must satisfy the shared JSON schema and include exactly one valid assessment per input message; malformed or incomplete output fails visibly instead of silently hiding mail.

The FIT-AI documentation does not currently state an email-content retention or training policy. Use synthetic messages until the operator confirms how prompts and responses are logged, retained, and used.

### Production AI boundary

Shipping an AI provider key in an iOS binary is not safe. Release builds therefore require an HTTPS proxy configured through the `AI_PROXY_URL` build setting. `ProxyEmailAnalyzer` already provides the app-side boundary, allowing a production backend to be introduced without rewriting the domain or UI.

The request contract is a `messages` array of minimized analysis inputs. The response contract is a `results` array containing `message_id`, `is_important`, `priority`, `summary`, `action_required`, `action_description`, and `reason`.

## Troubleshooting

- **Google reports a redirect or client error:** confirm the app bundle ID matches the iOS OAuth client and that both Google build settings were updated together.
- **The account is not allowed:** add that Gmail address as an OAuth consent-screen test user.
- **“AI isn’t configured”:** confirm the private local scheme is selected and its environment variables are enabled.
- **AI authentication fails:** replace the local key; never commit it while troubleshooting.
- **Rate limit reached:** wait for the provider limit to reset or lower `INBOXBRIEF_FITAI_MAX_CONCURRENT_BATCHES`.
- **A connected account requires authentication:** reconnect it from account management; other healthy accounts can still produce a partial briefing.

## Secret-safety check before committing

Review both tracked and untracked files:

```sh
git status --short
git diff --cached
git grep -n -E 'sk-(proj-)?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,}' -- .
```

`.gitignore` excludes per-user Xcode data, `.env` files, and `Secrets.xcconfig`. If a secret is ever pasted into a public location or committed, revoke it immediately—removing it from the latest commit is not sufficient.

## V1 limitations

- Gmail only
- Manual foreground refresh only
- Last 24 hours only
- No full mailbox browsing or message mutation
- No personalization, feedback training, notifications, widgets, or generated replies
- Production distribution requires an AI proxy and completion of Google’s restricted-scope requirements
