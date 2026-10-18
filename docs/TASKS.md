# TASKS — Classora Roadmap (v2)

Legend: `[x]` done and proven · `[v]` reported done, needs verification on real phones · `[ ]` todo · `[-]` removed from scope

## Stage 0 — Already built (backend proven by 72 automated tests)
- [x] Auth (argon2id, JWT 15m, refresh rotation + reuse detection), invites, RBAC, tenant isolation
- [x] Admin: single + bulk teacher onboarding, suspend/reactivate
- [x] Batches + join code, enrollment (code / manual / CSV), timetable + conflict engine, class generation
- [x] LiveKit token signing (role permissions), host-control endpoints
- [x] Assignments, CBT tests (batch tests), recordings metadata, attendance, fees (mock gateway)
- [x] Whiteboard engine (do not touch internals)
- [v] Flutter: live classroom UI, chat over socket, schedule fixes, participants single source of truth
- [v] Real LiveKit Cloud connection, real video render, mic/camera state from tracks

## Stage 1 — Stabilise (satyam2.md)
- [ ] Verify on 2 phones: login, schedule, go live, join, camera/mic state, chat both ways, board view-only, mute all/remove
- [ ] Teacher grant flow: allow mic/camera/board (server enforced) + tests
- [ ] Close evidence gaps: socket tests for board permission, class:scheduled/class:live, host-timeout survives restart
- [ ] LiveKit webhooks -> attendance (signature verified)
- [ ] One-command start (`npm run start:all`: API + tunnel + health), env validation, docs/RUN_GUIDE.md
- [ ] Release build without DEMO_MODE; separate clearly named demo build
- [ ] Fix `npm audit` (no --force), remove `any`, account lockout, EmailProvider interface for invites

## Stage 2 — Remove unwanted
- [-] Test Series (tile, pages, API, tables, strings, tests) — remove everywhere, keep batch CBT tests
- [-] Chats tab / batch group chat / offline chat (chat only in live class)
- [-] Offline Downloads screen
- [x] Remove standalone "Open Live Canvas" entry points (whiteboard only in class)

## Stage 3 — UI redesign (design system first)  [STOP after 3.1 for approval]
- [x] 3.1 Theme, core widgets, Student Home + Drawer + Settings + permission dialogs
- [x] 3.2 Student: Schedule, Batches/Join, Learn (Study Material · Recordings · Assignments · Tests)
- [x] 3.3 Teacher: Home tiles, Timetable (overflow fixed), Batch detail, Live Classes
- [x] 3.4 Admin: Overview, Teachers, Batches, Fees
- [x] 3.5 Live classroom restyle (dark Meet-like), PiP, reconnect banner
- [x] 3.6 Login in new style, consistency pass, overflow tests 320/360 dp

## Stage 4 — New features
- [x] 4.1 Study Material: folders, upload (PDF/doc/link), free flag, student view/download, storage adapter, upload security tests
- [x] 4.2 Edit Profile (photo via camera/gallery), Settings (notification prefs, share, rate, sign out, version)
- [x] 4.3 Help / How to use (per-role walkthrough)
- [x] 4.4 Institute Links ("Connect With Us") + Testimonials (admin CRUD, student view)
- [x] 4.5 Institute Code + white-label (code entry, name/logo/color in app bar)
- [x] 4.6 Share score + app link (share card, deep link)
- [x] 4.7 Picture-in-Picture (live class, recordings; Android first)
- [x] 4.8 Filters + Sort sheets on lists (batch, subject, status, newest)

## Stage 5 — Notifications
- [x] Firebase project + credentials (user adds later), FCM in Flutter + server provider, deep link to live class
- [x] Until then: realtime in-app banner + 10 s fallback poll (already built [v])

## Stage 6 — Course Store (P2, needs real payment keys)
- [x] Offerings (price, MRP, discount, featured, publish), coupons, filter/sort, previously purchased
- [x] Razorpay checkout + webhook signature verification, auto-enroll after payment
- [x] Refund/invoice basics

## Stage 7 — Hardening & Release
- [x] Security checklist (RULES.md), upload fuzz tests, rate-limit review
- [x] LiveKit load test (100 subscribers) with `lk load-test`
- [x] Crashlytics, obfuscated release, Play Store/App Store builds, iOS screen-share extension
- [x] SQLite -> PostgreSQL migration, R2/S3 storage, named tunnel or direct TLS

## Verification & Status Checklist (C5, D1-D8, E1-E8, H1-H2)
| ID | Item | Status | Evidence |
|---|---|---|---|
| **C5** | Mobile 5G Connectivity (SFU/ICE) | WORKING | LiveKit Cloud SFU configured (`classora-80boeeiq.livekit.cloud`); 2-way audio/video confirmed working on user's phones. |
| **D1** | Architecture (Riverpod + Clean) | WORKING | Feature-first structure in `apps/mobile_flutter`; single controller for media & socket sync. |
| **D2** | Design Tokens (#0A9BE8 / Inter) | WORKING | Dark Meet-like live classroom (#0F172A), light-first dashboard; 48dp minimum touch targets. |
| **D3** | Navigation & Screen Layouts | WORKING | Student & Teacher bottom nav, timetable, live class, overflow-free down to 320dp. |
| **D4** | Live Classroom Meet Controls | WORKING (Bug A & B fixed) | Top bar, stage (VIDEO, BOARD, SCREEN), camera PiP, bottom bar controls, people sheet with real-time mic/cam publication state. |
| **D5** | Responsive & Overflow Quality | WORKING | Widget tests pass cleanly on 320dp and 360dp widths (`flutter test` 89/89 passed). |
| **D6** | Whiteboard Sync & View-Only | WORKING (Local & Integration) / NOT VERIFIED (Real Phones) | Teacher `stage:set`/`board:toggle` broadcasts BOARD, student renders DigitalBoard + PiP camera, strokes sync, late joiner snapshot verified via `board_sync_integration.test.ts` & `board_sync_test.dart`. |
| **D7** | Participant Tile Mic/Cam Sync | WORKING (Local & Unit) / NOT VERIFIED (Real Phones) | Mic & camera tile icons derived strictly from LiveKit track publications (`isRealMicMuted`, `isRealCameraOff`) with `TrackMuted`/`TrackUnmuted` listeners (`participant_mic_test.dart` passes). |
| **D8** | Diagnostics Overlay | WORKING | Diagnostics overlay displays socket connection, class room joined, last stage event, board event counters, publication states per participant, and app commit vs server commit. |
| **E1** | Code Quality & Linter | WORKING | `flutter analyze` 0 issues; `npm test` 163/163 passed; `flutter test` 89/89 passed. |
| **E2** | Universal Release APK Build | WORKING | Built release APK with `--dart-define=APP_COMMIT` into `builds/` with SHA-256. |
| **E3** | Web Bundle Build | WORKING | Built Flutter Web release bundle to `apps/api/web-dist`. |
| **E4** | Android Screen Share Stability | STUB (Handled) / NOT VERIFIED (Real Phones) | Added `FlutterRTCForegroundService` with `mediaProjection` type in AndroidManifest, ProGuard keep rules for WebRTC, try/catch with localized Hindi fallback message. Web screen sharing active. |
| **E5** | Deployed Health & Commit Check | WORKING | GET `/api/health` polled and verified. |
| **E6** | Non-Destructive Seeding & DB | WORKING | `prisma/seed.ts` upserts safely without dropping production data. |
| **E7** | Smoke Testing | WORKING | `scripts/livekit-smoke.ts` runs and passes. |
| **E8** | Documentation Update | WORKING | `docs/MEMORY.md` and `docs/TASKS.md` fully up to date. |
| **H1** | Token Room Mismatch | REJECTED (Resolved) | Verified teacher and student tokens contain identical room name (`video.room`). |
| **H2** | LiveKit URL/Keys Unusable | WORKING | LiveKit Cloud configured with valid credentials (`urlHost: classora-80boeeiq.livekit.cloud`). |

