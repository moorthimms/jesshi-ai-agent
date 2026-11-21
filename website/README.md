# Jessy website

Build: `npm ci && npm run build`. Serve `dist/` through HTTPS or localhost.
Install through the browser menu; iPhone Safari uses Share → Add to Home Screen.
The versioned service worker caches the app shell. Chat uses WebLLM and WebGPU,
with one-time model/runtime downloads from the model provider. No chat/file uploads.
Confirm model readiness, then test in airplane mode. Browsers can evict model and
data caches. Unsupported devices retain access to documents, notes, and tasks.

Includes PDF/text extraction, keyword-ranked excerpts, memory, notes, task lists,
open-app reminders, prompt routines, activity, one-step data undo, model management,
local system speech output, language/text preferences, and encrypted portable backups.
Run `npm test` for schema, retrieval, and backup checks.

Backups use PBKDF2 SHA-256 (250,000 iterations), AES-256-GCM, a random 16-byte salt,
and a 12-byte nonce. They transfer manually among website, Mac, and iPhone.
Live IndexedDB data is not encrypted by the app. Permissions, smart-home tokens,
app lock, model weights, and OS notification registrations are not transferred.

The website cannot control other apps, offer biometric app lock, transcribe a
microphone offline, OCR screenshots, schedule reminders while closed, or operate
calendar/smart-home integrations. Use native apps for supported device features.

## Sign-in, approval, and Gmail

The deployed Worker now gates `/app/` and every app asset with a server-side D1
membership check. The root page is a sign-in/request-access page. Configure the
Sites audience as public only after this Worker is deployed: that exposes the
request page, not unrestricted app access. Trusted identity comes only from the
Sites dispatcher, never a submitted email or browser storage. The configured
owner retains app access; `ADMIN_EMAIL` alone can approve, deny, and manage Gmail.

Runtime variables: `ADMIN_EMAIL`, `OWNER_EMAIL`, `SITE_ORIGIN`, and secret
`GMAIL_TOKEN_KEY` (base64-encoded 32 random bytes). Never rotate the encryption key
without migrating stored encrypted Gmail settings. D1 logical binding is `DB`;
Drizzle schema migrations are committed under `drizzle/`.

At `/admin`, connect Gmail using your own Google web OAuth client. Enable Gmail
API, configure consent/test users as appropriate, and register the callback shown
in the admin page. Enter client ID/secret in the admin form, then authorize the
`gmail.send` scope. The app stores the client secret and refresh token encrypted
with AES-GCM under the runtime secret. No Gmail inbox/read scope is requested.
Until that authorization is complete, requests persist and can be approved in
the dashboard, but no notification email is sent. Status explicitly reports this.

Each new signed-in account creates one pending request. The notification goes
only to ADMIN_EMAIL, with a link to authenticated admin review. GET/email links
do not approve automatically. Approval requires an admin-only same-origin POST.
The admin can reject/revoke online access and retry failed notification delivery.
Existing offline app caches remain usable until the device reconnects; revocation
cannot erase code/data already downloaded to an offline device.

`npm test` includes server authorization, identity/CSRF checks, request deduplication,
protected asset gating, encrypted credentials, OAuth state replay, fixed recipient,
and mocked Gmail notification tests. No live Gmail send is claimed until authorized.
`node dev.mjs` is a local in-memory UI fixture and is not included in production.

## Admin dashboard

Signing in as ADMIN_EMAIL redirects from `/` to `/admin`. The same dashboard is
linked from the app only for the admin; authorization is enforced server-side.
The dashboard displays request/status counts, active accounts in the past 24 hours,
searchable/filterable access requests, recent usage events, and approval history.

Usage tracking sends only a server-validated event name, a random deduplication ID,
and the platform-authenticated account identity. It never uploads chat text,
notes, document names/contents, routine prompts, or backup data. The app discloses
this collection in its privacy sidebar. Offline events are not queued or uploaded;
client-reported usage is incomplete and is not a security-grade audit trail.
Access approvals/denials are server-recorded independently. The dashboard shows
up to 200 recent activity items and 200 access decisions; it auto-refreshes only
when the admin clicks Refresh or changes a request/filter. Usage writes are
limited to 120 per authenticated account per hour and are idempotent by event ID.
