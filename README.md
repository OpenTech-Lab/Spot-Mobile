# Spot — Citizen Swarm

**Decentralized SNS & Civic Event Timeline Platform**

Spot is a mobile app that enables citizens to document, share, and verify real-world events collaboratively. It combines decentralized social networking with an on-device evidence verification system — giving communities a trusted, censorship-resistant lens on what's happening around them.

---

## Features

### Media & Posts
- **Camera-first interface** — tap for photo, hold for video
- **Multi-media posts** — attach up to 4 files per post with hashtags and descriptions
- **Danger Mode** — automatically blur faces and strip GPS metadata for safety in sensitive situations

### Event Timeline
- Posts are grouped into civic events by hashtag and geographic location
- Real-time event timelines showing participant count, trust score, and activity
- Thread views with reply chains for community discussion

### Feed & Discovery
- **Latest** and **Following** tabs for home feed
- **Trending**, **For You**, and **Nearby** sections in Discover
- Geo-filtered and algorithmic feed scoring

### Trust & Verification (EBES)
Spot includes an on-device Evidence-Based Event Scoring system that assesses the trustworthiness of reported events:
- Scores based on source credibility, media integrity, geographic proximity, and cross-evidence consensus
- Witness signals: `SEEN`, `CONFIRM`, `DENY`
- Event confidence levels: unverified → low confidence → high confidence → conflicted

### Identity & Wallet
- Device-bound **secp256k1** cryptographic identity
- **BIP39** 12-word mnemonic for key recovery
- Biometric app lock (Face ID / fingerprint)

### Social
- Follow/unfollow users and hashtags
- Follower/following lists and profile stats
- Interest tags for topic-based discovery

### Geolocation & Maps
- GPS locking at capture time
- Location-aware discovery with Natural Earth city database
- Geographic event clustering on map views

### Storage & Sync
- Offline-first with local SQLite database
- **IPFS** pinning for permanent, decentralized media storage
- SHA-256 content hashing for integrity verification
- WebSocket-based P2P networking

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Cryptography | secp256k1, BIP39, SHA-256 |
| Storage | SQLite (sqflite), flutter_secure_storage |
| Media | Camera, ML Kit (face detection), image/video processing |
| Maps | flutter_map, latlong2 |
| Network | WebSocket (web_socket_channel), IPFS, Supabase |
| Auth | local_auth (biometrics) |

---

## Getting Started

### Prerequisites
- Flutter SDK `^3.11.0`
- Dart SDK (included with Flutter)
- Android SDK or Xcode (for iOS)

### Setup

```bash
# Clone the repo
git clone <repo-url>
cd mobile

# Install dependencies
flutter pub get

# Copy environment config
cp .env.example .env
# Edit .env with your API keys

# Run the app
flutter run
```

### Environment Variables

The app requires a `.env` file in the project root. See `.env.example` for required keys (Supabase URL, anon key, media presign endpoint, etc.).

---

## Project Structure

```
lib/
├── main.dart               # App entry point
├── models/                 # Data models (CivicEvent, Post, User, ...)
├── screens/                # UI screens (feed, camera, profile, ...)
├── services/               # Business logic (auth, sync, trust scoring, ...)
└── widgets/                # Reusable UI components
```

---

## License

Private — all rights reserved.
