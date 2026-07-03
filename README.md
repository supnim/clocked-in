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
- **Auth**: device-based on first run, with optional Apple or Google account linking

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

Clocked In is distributed as a direct-download notarized DMG — it is **not**
on the Mac App Store. Until a signed release is published, build from source
as described above.

## Privacy

Clocked In shares real activity data with real people, so here's exactly what
that means:

- **What's shared**: the app you're currently using (name + icon). Window
  title and browser domain sharing are on by default and each separately
  toggleable in Settings.
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

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Made by [@sup_nim](https://x.com/sup_nim)

[studio.gold](https://studio.gold)
