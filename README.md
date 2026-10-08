# Clocked In

See what your friends are working on, right from your Mac's notch.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## What it is

Clocked In is a macOS presence app that lives in the notch. Add friends, and it
shows you what app they're currently using, in real time — with idle/away
states, nudges, and a fully honest privacy model (see below).

## Features

- **Live friend presence** — see what app each friend is using, updated in real time over WebSocket
- **Friend requests** — search by username, or share a `clockedin://add/{username}` deep link
- **Nudges** — poke a friend (shake + sound + notification, each toggleable)
- **Idle / away detection** — friends show as away after a period of inactivity
- **Invisible mode** — one toggle stops all presence sharing entirely
- **Per-app hiding** — pick apps that never get reported, even to friends
- **Offline-friendly** — cached friends list and an offline banner when disconnected

## Tech Stack

- **Client**: Swift 6, SwiftUI + AppKit (for notch/system integration), macOS 15+
- **Backend**: FastAPI, PostgreSQL, Redis, WebSockets for real-time presence
- **Auth**: device-based on first run (no sign-up form, no passwords)

## Local Development

### Backend

```bash
cd backend
cp .env.example .env   # fill in JWT secret / Google OAuth creds as needed
docker compose up
```

This starts Postgres, Redis, and the API on `localhost:8000`.

### Client

Open `clocked-in.xcodeproj` in Xcode 26+ and run. Debug builds automatically
target `localhost:8000`; Release builds target the hosted backend.

## Distribution

Clocked In ships on the **Mac App Store**.

To produce a store build:

```bash
scripts/release.sh appstore                     # archive + export a .pkg to ./dist/appstore
APPSTORE_UPLOAD=1 scripts/release.sh appstore   # archive + upload straight to App Store Connect
```

This archives the Release configuration with automatic signing (team
`67QQB49ZUJ`) and exports with `ExportOptions-AppStore.plist`
(`app-store-connect`). Without `APPSTORE_UPLOAD=1`, upload the exported
package via Xcode's Organizer, Transporter, or `xcrun altool --upload-app`.

A Developer ID–signed, notarized DMG can still be built for direct
distribution with `scripts/release.sh dmg`.

## Privacy

Clocked In shares real activity data with real people, so here's exactly what
that means:

- **What's shared**: the app you're currently using (name + icon) and your
  online / away status. Window titles and browser URLs are never collected
  or shared.
- **Who it's shared with**: only friends who have mutually accepted your
  friend request, via your own backend instance — never a third party.
- **Hidden apps**: any app you add to your hidden list is filtered out
  client-side, before anything is ever uploaded. Friends just see nothing for
  that period.
- **Invisible mode**: a single toggle that stops all presence sharing —
  friends see you as offline.
- **Data lifetime**: presence data lives in Redis with a 45-second TTL. There
  is no long-term activity history stored server-side.
- **No analytics or tracking.**
- **Your controls**: block or report any user, and delete your account (and
  all its server-side data) at any time from Settings.

## License

Released under the MIT License.

## Author

Made by [@sup_nim](https://x.com/sup_nim)

[studio.gold](https://studio.gold)
