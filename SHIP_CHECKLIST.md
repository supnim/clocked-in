# Clocked-In v1 — Mac App Store Ship Checklist

Compiled 2026-10-08 from five parallel audits (client core, auth/API, backend, App Store readiness, UI/features).
Backend findings marked **(confirmed)** were reproduced against a live local server; everything else is from source review (no Xcode available in the audit environment).

**Bottom line:** the core loop (detect activity → upload → friends see it) does not work end to end today, the backend has several confirmed security holes, and there is no production deployment. All of it is fixable, but "submit today" is aggressive; App Review itself then takes ~1–2 days.

Legend: `[code]` fixable in repo · `[mac]` needs Xcode / your Mac · `[asc]` App Store Connect / non-code · `[you]` decision or account access

---

## Decisions made for v1 (App Store build)

| Decision | Reason |
|---|---|
| Ship via Mac App Store (README said DMG — update README) | User request |
| **Cut** browser-URL sharing (AppleScript) | Needs temporary-exception apple-events entitlements; near-certain rejection; already non-functional in sandbox |
| **Cut** window-title sharing (CGWindowList) | Requires Screen Recording permission; review friction |
| **Hide** Google sign-in and account "linking" UI | Callback is CSRF-able, "link" creates a separate account; device-UUID login stays primary. Hiding all third-party login also removes the Sign in with Apple token-revocation requirement |
| Replace global keyDown idle monitor with `CGEventSource.secondsSinceLastEventType` | Works in sandbox, no permission prompt |
| Delete synthetic click repost (`CGEvent.post`) | Blocked in sandbox and double-clicks elsewhere |

---

## P0 — Blocks shipping

### Client: core loop broken
- [ ] `[code]` `ActivityMonitor` is never instantiated → nothing is ever uploaded (`Core/Activity/ActivityMonitor.swift`, `App/AppDelegate.swift`)
- [ ] `[code]` Launch race: `AppDelegate.swift:48` checks `isAuthenticated` before async `restoreSession` finishes → onboarding every launch, services never start
- [ ] `[code]` Friend list always empty: `CompactNotchView.swift:91` `onDisappear → stopListening()` clears cache when notch opens
- [ ] `[code]` Server publishes `online`/`updated_at` as strings; client decodes Bool/Int64 → every `presence_update` silently dropped (`backend/app/ws/presence.py:53-94`, `WebSocketClient.swift:311,318`)
- [ ] `[code]` WS liveness: client treats 60s silence as disconnect, server never acks heartbeats; zero-friend users never "connect"; reconnect discards `initial_presence`
- [ ] `[code]` User search 404s: `APIClient.swift:25` `appendingPathComponent` encodes `?` → Add Friend can't find anyone
- [ ] `[code]` Date decoding: `.iso8601` rejects fractional seconds the backend emits → `/api/users/me` and pending requests fail to decode (verify with a unit test)
- [ ] `[code]` Onboarding never completes: `OnboardingView.completeSetup` doesn't close window/start services/refresh `currentUser`; returning users re-shown username picker
- [ ] `[code]` Sign-out stops `EventMonitors` and never restarts / never shows onboarding
- [ ] `[code]` App icons sent as full multi-res TIFF base64 (MBs) → exceed 1 MB WS frame on receivers → reconnect loops

### Privacy leaks
- [ ] `[code]` Hidden app sent with status "away" on idle (`PresenceManager.swift:181-188`)
- [ ] `[code]` Invisible mode: toggling does nothing until next app switch; heartbeat keeps old presence alive; `setOffline` stored as online; queued updates flushed on reconnect
- [ ] `[code]` Server `HSET` merges → stale window title/domain/icon survive (`presence.py:61`)
- [ ] `[code]` Own app (Clocked-In) reported as activity when notch opens

### Backend security (confirmed)
- [ ] `[code]` Presence spoofing: client `data` spread after server fields → can impersonate `user_id`, crash friends' `GET /api/friends` (500); unbounded payload
- [ ] `[code]` Nudge any user without friendship check
- [ ] `[code]` Unfriended users keep receiving live presence; new friends never stream until reconnect
- [ ] `[code]` Reconnect race: old socket's `finally` tears down the new connection and marks user offline (every sleep/wake)
- [ ] `[code]` Apple sign-in account takeover via client-supplied `email` (`auth/router.py:218-238`); Google links by unverified email
- [ ] `[code]` Deleted users' JWTs still valid / refreshable (`api/deps.py`)

### App Store hard requirements
- [ ] `[code]` In-app **account deletion** (5.1.1(v)): `DELETE /api/users/me` + Settings button + Keychain wipe
- [ ] `[code]` **Block + report** users (1.2): backend endpoints + UI in FriendDetail / PendingRequests; blocked users hidden from search/requests/nudges
- [ ] `[code]` Info.plist: version hardcoded `1.0`/`1` (overrides `MARKETING_VERSION`), missing `LSApplicationCategoryType`, `NSAllowsArbitraryLoads=true`, dead `NSMainStoryboardFile`, unused Google URL scheme; add `ITSAppUsesNonExemptEncryption=NO`
- [ ] `[code]` Add `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`, tracking false, collected data types)
- [ ] `[code]` Privacy policy + support links in Settings
- [ ] `[code]` App Store export path: `ExportOptions.plist` (`app-store-connect`) + store mode in `scripts/release.sh`
- [ ] `[you]` Host privacy policy + support page (URLs needed in app and ASC)

### Backend: production
- [ ] `[you]` Choose host (e.g. Fly.io / Render / Railway) with managed Postgres + Redis, TLS at edge for `api.clockedin.studio.gold`
- [ ] `[code]` Production compose/config: no published DB/Redis ports, Redis password, `--proxy-headers`, non-root Dockerfile, healthcheck
- [ ] `[code]` Migration strategy (numbered SQL + `schema_migrations`, baseline from `init.sql`) run on deploy
- [ ] `[you]` Set `JWT_SECRET` (≥32 bytes), `JWT_EXPIRATION_HOURS`, `DATABASE_URL`, `REDIS_URL` in host secret store; deploy and smoke-test **before** submitting

---

## P1 — Fix before ship

### Client
- [ ] `[code]` `ErrorHandler`: read FastAPI `detail`; map 403 → `.api` (only 401 forces re-auth)
- [ ] `[code]` 401 → silent re-auth via device ID + retry once (tokens expire in 24h, no refresh)
- [ ] `[code]` Reject `clockedin://auth?...` deep links when no sign-in is pending
- [ ] `[code]` WS: detect auth failure via HTTP 403 on handshake; unbounded reconnect with cap+jitter; reconnect on `didWakeNotification`; flush on connect; tear down old socket before reconnect; re-send presence on connect
- [ ] `[code]` Use server `status` (online/away/ghost/offline) instead of client 15-min heuristic
- [ ] `[code]` `PresenceListener` ref-count bug when starting invisible; invisible should not hide friends from you
- [ ] `[code]` Notch pop-dismiss tasks close a panel the user just opened; Esc/Cmd+W bypass forced username picker
- [ ] `[code]` Sharing defaults off for anything beyond app name (opt-in)
- [ ] `[code]` Launch at Login toggle actually calls `SMAppService`
- [ ] `[code]` Hidden-apps sheet has no Done button and Esc is swallowed → user trapped
- [ ] `[code]` Deep link `clockedin://add/{u}` drops the username
- [ ] `[code]` "Clear status" sends nothing (nil omitted)
- [ ] `[code]` FriendRow context-menu Nudge/Remove are no-ops
- [ ] `[code]` Loading/offline/error states (currently all show "No friends yet")
- [ ] `[code]` Multi-monitor / no-notch: pick notched screen, rebuild on `didChangeScreenParametersNotification`
- [ ] `[mac]` Build with Xcode 26 (needs Swift 6.2 for `isolated deinit` + default MainActor isolation); check `NSRunningApplication` Sendable at `ActivityMonitor.swift:32`

### Backend
- [ ] `[code]` Rate limiting (`/auth/device` created 200 accounts in 1.6s — confirmed); search, friend requests, nudges, WS messages
- [ ] `[code]` Require auth on `/api/users/search`, `/check-username`, `/{username}` (confirmed public)
- [ ] `[code]` Input validation: `display_name`/`status_message` max_length (confirmed 500), `DELETE /api/friends/{id}` typed `UUID` (confirmed 500), bound `hidden_apps`
- [ ] `[code]` Publish offline when presence TTL expires; heartbeat re-asserts online
- [ ] `[code]` JWT: enforce secret length always; WS token out of query string / access logs (confirmed in logs)
- [ ] `[code]` Readiness `/health` pings PG + Redis
- [ ] `[code]` Unique partial index for pending friend requests (race)
- [ ] `[code]` `initial_presence` values JSON round-trip types (`"123"` window title → int breaks decode)
- [ ] `[code]` Tests: WS/presence/nudge/delete/block coverage; fail instead of silently skipping when stack is down

---

## App Store Connect / non-code `[asc]`
- [ ] App ID `gold.studio.clocked-in`, app record (Primary: Productivity, Secondary: Social Networking), SKU
- [ ] Mac App Distribution provisioning profile + Mac Installer Distribution certificate
- [ ] Privacy Policy URL, Support URL, contact email
- [ ] Screenshots (16:10: 1280×800 / 1440×900 / 2560×1600 / 2880×1800): notch lobby, friend list, privacy/invisible settings
- [ ] Name, subtitle, description, keywords, promo text, copyright, version
- [ ] Age rating: user-generated content + user interaction → expect 13+
- [ ] App Privacy: Tracking **No**; Linked to user, App Functionality: User ID, Name (display name), User Content (username/status), Usage Data (frontmost app name/bundle ID, idle/away)
- [ ] Review notes: no-login (device ID), UI lives at the top-center/notch (no Dock icon), works on non-notch Macs; provide a **demo friend account** that is always online so reviewers see the lobby populated
- [ ] Export compliance: HTTPS only → exempt

---

## P2 — After launch
- Nudges through Redis pub/sub (multi-worker), N+1 Redis in `get_friends`, `ILIKE '%q%'` seq scan → prefix/trigram
- Migrate `python-jose` → PyJWT; pin deps with a lockfile
- Hash stored device IDs; JWT revocation (`token_version`)
- Real-time `friend_request` WS events, `last_seen`, display names in presence
- Pending-requests badge, "change username", tab/window change detection
- Accessibility (FriendRow keyboard activation, reduce motion), username rules unified client/server, profanity filter
- Developer ID DMG flavour with browser domains + window titles
