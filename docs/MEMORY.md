# MEMORY — Project Context (agents: read this first, update it last)

## Project
**Classora 2.0** — multi-tenant EdTech SaaS. Owner: Satyam (WebApple, Mumbai). Writes in Hinglish. Prefers iterative work: review and approve before the next phase.

## Goal
Admin onboards many teachers -> each teacher builds a timetable, enrolls students, shares study material, goes live (Zoom/Meet quality, screen share, host controls) -> students get notified and join together. White-label per institute (Institute Code). Main client Flutter. Strong security.

## Current Status (honest)
- Backend: 72 automated tests pass (auth, onboarding, batches, timetable, live-class tokens, learning modules, notifications logic, socket chat, tenant isolation).
- Flutter: installs and runs on real phones; login works through the Cloudflare tunnel. Several fixes reported (participants, chat, schedule) but NOT yet confirmed on 2 phones.
- NOT verified: real camera/mic/screen share, FCM push (no credentials, currently a logged no-op), LiveKit Cloud connection from the app, load with real video.
- Fees/payments are mocked. Recordings (egress) and iOS screen share are stubs.

## Decisions Log
| Date | Decision |
|---|---|
| 2026-10 | DB = local SQLite (Prisma). Cloudflare D1 was created but is NOT used; do not wire it |
| 2026-10 | Cloudflare used only as Tunnel for API + WebSocket |
| 2026-10 | Video = LiveKit Cloud (SFU), keys in apps/api/.env, never in chat or git |
| 2026-10 | Push = FCM later; Firebase credentials to be added by the owner. App must run without them |
| 2026-10 | UI = light-first, blue app bar, coloured tiles, drawer, 4-tab bottom nav (see DESIGN.md) |
| 2026-10 | **Test Series removed everywhere**; batch CBT tests stay |
| 2026-10 | **No Chats tab / offline chat; chat only in the live class.** No Offline Downloads |
| 2026-10 | New features approved: Study Material, Edit Profile, Settings, Help, Connect With Us, Testimonials, Share score + link, Institute Code, PiP, Filters/Sort, Course Store (P2) |
| 2026-10 | Whiteboard: teacher draws, students view-only unless granted |
| 2026-10 | Tests use a separate test.db; demo data via `npm run db:reset-demo` |

## Known Issues / Debt
- Old build had DEMO_MODE chips and demo password in the APK; ship release without it
- 14 `any` usages and `npm audit` findings to fix
- Host-disconnect timeout lives in memory (lost on restart)
- Invite codes are returned by API only; no email/SMS delivery yet
- Old React portals moved to `_archive/`

## Working Agreements
Follow RULES.md. Label results WORKING/PARTIAL/STUB/BROKEN/MISSING/NOT VERIFIED with evidence. Stop after each phase. Camera/mic/screen share/push are verified by the owner on real phones.

## Session Log
- 2026-10-09: docs v1, Phases 0-6 built by agent; audit found overclaims
- 2026-10-10: satyam2.md fixes (C1-C7), cleanup, APK on phones; Cloudflare tunnel + LiveKit Cloud plan
- 2026-10-11: docs v2 (this set): new feature list, Test Series removed, in-class chat only. Next: phone test, then Stage 1 -> 3.1
- 2026-10-12: Stage 2 & 3.1 completed: standalone whiteboard removed, tokens aligned to DESIGN.md (#0A9BE8, Inter), core widgets built (ColorTile, StatusPill, PermissionRationaleDialog, ConfirmDialog, EmptyState), fake counts removed, flutter analyze 0 issues, npm test 72/72 pass.
- 2026-10-12: Stage 3.2 completed: Dynamic schedule day/date computation, real slot status logic (LIVE/ENDED/UPCOMING), StatusPill badges, real batch filtering in Study Material, interactive resource sheet (no dead UI), light theme redesign for Recordings, Assignments & CBT Tests. flutter analyze 0 issues, npm test 72/72 pass.
- 2026-10-13: Stage 3.3 completed: Teacher HomeScreen redesigned with 2x3 ColorTiles (Batches, Timetable, Live Classes, Study Material, Assignments & Tests, Recordings), real stats metrics, 'Sync from slots' trigger with live feedback, multi-tab BatchDetailScreen (join code + QR pattern + share, enrolled students, batch timetable, study material), AddTimetableSlotDialog with 320 dp overflow prevention + inline conflict alerts, delete slot with ConfirmDialog. flutter analyze 0 issues, npm test 72/72 pass.
- 2026-10-13: Stage 3.4 completed: AdminHomeScreen completely replaced from web stub to 4-tab mobile powerhouse (Overview with 2x2 stat cards, 2x2 ColorTiles & live session monitoring; Teachers tab with search, status filters, + Single/Bulk CSV modals & suspend/reactivate toggles; Batches tab with cohort cards & BatchDetail integration; More tab with administrative modules, web admin link & sign out), FeesScreen reskinned to Light-first design system (#0A9BE8 / #FFFFFF / EmptyState). flutter analyze 0 issues, npm test 72/72 pass.
- 2026-10-13: Stage 3.5 completed: LiveClassroomScreen completely restyled to Meet-like dark theme (#0F172A / #1E293B) per DESIGN.md Section 6. Real session timer, connection status indicator, reconnect banner on unstable network, 8 Meet controls in bottom bar, people sheet sorted by hand-raised first with teacher moderation (mute, allow board draw, remove), ConfirmDialog for leaving/ending class. Removed fake local .mp4 text writes and hardcoded slide decks. flutter analyze 0 issues, npm test 72/72 pass.
- 2026-10-13: Stage 3.6 completed: LoginScreen & AcceptInviteScreen restyled to Light-first Classora design system (#0A9BE8 / #FFFFFF card / #F4F6F8 bg / 48 dp min touch targets). Replaced deprecated .withOpacity calls with .withValues(alpha:). Removed pre-filled production passwords (isolated demo accounts for debug only). Added auth_screens_overflow_test.dart covering 320dp and 360dp with textScaler 1.3. flutter analyze 0 issues, flutter test 8/8 pass, npm test 72/72 pass. Stage 3 UI Redesign complete!
- 2026-10-13: Stage 4.1 completed: Study Material & Storage Adapter. Backend Prisma schema (MaterialFolder, StudyMaterial) + LocalStorageService (25MB limit, strict MIME allowlist, path traversal security) + material service & controller with batch/folder scoping, student enrollment authorization & isFree preview logic. 12 automated backend tests passing in study_material_phase4_1.test.ts (85/85 API tests total). Flutter: StudyMaterialModel, StudyMaterialRepository, StudyMaterialController (Riverpod), and StudyMaterialTabView integrated into both BatchDetailScreen (Teacher/Admin with folder creation, file picker upload, external link modal, delete confirmation) and StudentHomeScreen (Learn tab with batch selector chips, folder exploration, free preview badges, search & sort, file download). flutter analyze: 0 issues, flutter test: 12/12 pass (including study_material_test.dart).
- 2026-10-13: Stage 4.2 completed: Edit Profile & Settings. Backend User model updated with avatarUrl & notificationPrefs. PATCH /api/v1/auth/profile (name, phone, notificationPrefs), POST /api/v1/auth/avatar (5MB limit, JPEG/PNG/WEBP validation, safe UUID naming, old avatar cleanup), GET /api/v1/auth/avatar/:key with MIME & Cache-Control streaming, and /me /login /refresh integration. 8 new automated backend tests passing in profile_settings_phase4_2.test.ts (94/94 API tests total). Flutter: EditProfileScreen with camera / gallery photo selection (ImagePicker + FilePicker fallback), full name & phone editing, locked email display, role & institute summary card, save button with Riverpod authState sync; Student & Teacher profile/drawer tabs updated with live auth state, avatar preview, /edit-profile navigation, persistent notification preference switches, Share Classora invite link (Clipboard + feedback), interactive 5-star rating dialog with feedback comments. flutter analyze: 0 issues, flutter test: 17/17 pass (including edit_profile_settings_test.dart).
- 2026-10-17: Fixed Bug A (remote participant microphone & camera state desync), Bug B (whiteboard stage, stroke sync & late-joiner snapshot), and Bug C (Android 14 MediaProjection foreground service crash). LiveKit TrackMuted/TrackUnmuted event listeners wired to publication state; DigitalBoard stage transition and socket broadcasting unified; AndroidManifest foreground service declared with mediaProjection and ProGuard keep rules added; diagnostics overlay augmented with publication breakdowns and app-server commit diff.

## Reported by agent on 2026-10-11 (UNVERIFIED, needs audit)
- Backend deployed on Render (liveapple.onrender.com); README says SQLite local / PostgreSQL on Render. Admin web console served from apps/api/admin-dist at /admin/.
- Added WebRTC signaling relay over Socket.IO (signal:offer/answer/candidate) as a fallback because LiveKit could not be reached from Render. Temporary hack; real fix = LiveKit Cloud.
- Student AND teacher "Record" button in live class saving to app storage (likely not a real recording; privacy concern).
- Video upload from device + unlisted YouTube/direct links + custom player (no download/share buttons). Uploaded files need object storage, not API disk.
- "Assignments" screen was renamed "Study Material & Notes" but still shows Max Marks / Due Date: conflicts with DESIGN.md (separate Assignments and Study Material).
- CBT Quizzes chip removed from teacher Faculty Modules (decision was: remove Test Series only, keep batch CBT tests).
- Demo credentials (Password@123) exist on a public deployment: rotate/disable in production.
- Backend tests still 72 (no new tests for the new work).
- README claims bcryptjs, but earlier audit showed argon2id: verify which is true.
