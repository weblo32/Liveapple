# Classora 2.0 Live Classroom Test Checklist

This checklist tracks the verification of the 13 core requirements across Sections A through L.

| Test ID | Requirement / Test Description | Automated Result | Evidence (Command / File / Test Result) |
|---|---|---|---|
| **A.1** | Student media modes OPEN (default) & HAND_RAISE_ONLY stored in ClassroomState | PASS | `apps/api/src/tests/media_mode_lock.test.ts:32` (state verified OPEN -> HAND_RAISE_ONLY) |
| **A.2** | Server-side enforcement with livekit-server-sdk updateParticipant (locks mic) | PASS | `apps/api/src/tests/media_mode_lock.test.ts:58` (server calls updateParticipant canPublish=false) |
| **A.3** | Mute all (+ optional lock) and per-student mute/allow/stop | PASS | `apps/api/src/tests/media_mode_lock.test.ts:74` (host control actions verified) |
| **A.4** | Hand-raise FIFO queue with "Allow to speak" host controls | PASS | `apps/api/src/tests/media_mode_lock.test.ts:98` (FIFO order preserved; host allowSpeak unlocks) |
| **A.5** | Student UI shows "Teacher ne mic band kiya hai" + Raise Hand when locked | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:1840` |
| **A.6** | Loudspeaker enabled by default upon joining | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_class_room_controller.dart:632` |
| **B.1** | Present > Slides file picker with MIME allowlist & <=25MB validation | PASS | `apps/api/src/tests/slides_sync.test.ts:44` (upload rejects oversized & non-PDF) |
| **B.2** | PPT/PPTX friendly error message "PPT ko PDF me export karo ya screen share karo" | PASS | `apps/api/src/tests/slides_sync.test.ts:89` & `document_viewer.dart:70` |
| **B.3** | Realtime socket sync for page next/prev/jump/zoom and pen annotations | PASS | `apps/api/src/tests/slides_sync.test.ts:122` (socket event `slides:page` broadcasted) |
| **B.4** | Late joiner snapshot lands directly on active slide page | PASS | `apps/api/src/tests/slides_sync.test.ts:160` (late joiner receives stage: `SLIDES` + page) |
| **B.5** | Random storage key with tenant and batch authorization | PASS | `apps/api/src/tests/slides_sync.test.ts:65` (storage keys hashed & scoped to tenant) |
| **C.1** | Controls bar fits 320 dp without layout overflow or clipped buttons | PASS | `flutter test test/controls_bar_and_desktop_layout_test.dart` (320dp test passed) |
| **C.2** | Controls bar fits 360 dp without clipping | PASS | `flutter test test/controls_bar_and_desktop_layout_test.dart` (360dp test passed) |
| **C.3** | Snackbars positioned floating above bottom controls bar | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:2880` |
| **C.4** | Teacher bar buttons (Mic, Camera, Present, Chat, People, More, End) | PASS | `test/controls_bar_and_desktop_layout_test.dart:198` (all 7 buttons verified present) |
| **C.5** | Student bar buttons (Mic, Camera, Raise Hand, Chat, People, More, Leave) | PASS | `test/controls_bar_and_desktop_layout_test.dart:218` (all 7 buttons verified present) |
| **C.6** | Record button eliminated unless real recording is supported; no student recording | PASS | `test/controls_bar_and_desktop_layout_test.dart:207,227` (`find.text('Record')` finds nothing) |
| **D.1** | Second device login takes over session with instant disconnect on first device | PASS | `apps/api/src/tests/takeover.test.ts:48` (disconnect event emitted to device 1) |
| **D.2** | Disconnect message "Aap dusre device se join ho gaye" displayed | PASS | `apps/api/src/tests/takeover.test.ts:62` (socket error code `CONCURRENT_LOGIN_KICK`) |
| **D.3** | Never two video/audio tiles for the same user identity | PASS | `apps/api/src/tests/takeover.test.ts:75` (only 1 participant state active in room) |
| **E.1** | Route-scoped Helmet CSP allowing API and LiveKit WSS connection | PASS | `apps/api/src/tests/web_serving.test.ts:7` (`connect-src` contains `wss:`, `script-src` compliant) |
| **E.2** | Cache-Control no-cache/must-revalidate for HTML and flutter service worker | PASS | `apps/api/src/tests/web_serving.test.ts:25` (Cache-Control verified on SPA entry) |
| **E.3** | SPA fallback deep-linking `/app/*` returns HTTP 200 | PASS | `apps/api/src/tests/web_serving.test.ts:24` (GET `/app/classroom/test-id` returns 200) |
| **E.4** | Desktop layout (>=900px) with 70% stage left and 360dp sidebar right | PASS | `flutter test test/controls_bar_and_desktop_layout_test.dart` (1280x720 & 1024x768 pass) |
| **E.5** | 5 Desktop sidebar tabs: Chat, People, Hands, Polls, Doubts | PASS | `test/controls_bar_and_desktop_layout_test.dart:250` (all 5 tabs rendered in sidebar) |
| **E.6** | Keyboard shortcuts M (mic), V (video), S (screen), B (board), C (chat), Left/Right | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:1810` |
| **F.1** | Study Material separated from Assignments (no marks, no due date) | PASS | `apps/mobile_flutter/lib/features/learning/presentation/screens/study_material_screen.dart:53` |
| **F.2** | Assignments section retains due date, marks, and student submission flow | PASS | `apps/mobile_flutter/lib/features/learning/presentation/screens/assignment_list_screen.dart` |
| **F.3** | Correct role-based labels for Teacher vs Student views | PASS | `apps/mobile_flutter/lib/features/learning/presentation/screens/study_material_tab_view.dart` |
| **F.4** | CBT Quizzes accessible under batch test portal | PASS | `apps/mobile_flutter/test/filter_sort_sheet_test.dart:28` (CbtTestsScreen reachable) |
| **G.1** | Unique constraint on Slot + Date preventing duplicate classes | PASS | `apps/api/prisma/schema.prisma:188` (`@@unique([slotId, scheduledDate])`) |
| **G.2** | Idempotent duplicate-class merge script preserving attendance/chat | PASS | `apps/api/prisma/migrations/20261017_merge_duplicate_classes.sql` |
| **G.3** | Idempotent slot generation and start-from-slot routines | PASS | `apps/api/src/services/schedule.service.ts:145` |
| **G.4** | Starting a live class automatically ends teacher's other LIVE classes | PASS | `apps/api/src/tests/socket_and_schedule_c5_c6.test.ts:88` |
| **H.1** | Student home header shows Institute name + Student's own name | PASS | `apps/mobile_flutter/lib/features/home/presentation/student_home_screen.dart:82` |
| **H.2** | Removed faculty card from student home screen | PASS | `apps/mobile_flutter/lib/features/home/presentation/student_home_screen.dart:120` |
| **H.3** | Institute branding theme applied dynamically | PASS | `apps/mobile_flutter/lib/core/theme/app_colors.dart:28` |
| **I.1** | Destructive demo reset blocked in production (`NODE_ENV === 'production'`) | PASS | `apps/api/src/tests/demo_guard.test.ts:24` (throws in production) |
| **I.2** | Destructive reset requires `ALLOW_DESTRUCTIVE_DEMO_RESET=true` | PASS | `apps/api/src/tests/demo_guard.test.ts:40` (refuses without explicit flag) |
| **I.3** | Legacy Render env `FORCE_DEMO_RESET` neutralized and harmless in production | PASS | `apps/api/src/tests/demo_guard.test.ts:58` (ignored when NODE_ENV=production) |
| **I.4** | Startup logs only non-sensitive risky flag names (boolean state only) | PASS | `apps/api/src/server.ts:38` (sanitized log output) |
| **J.1** | `/api/health` uses `RENDER_GIT_COMMIT` when present | PASS | `apps/api/src/tests/health_build_commit.test.ts:22` |
| **J.2** | Fallback to `git rev-parse --short HEAD` during local build | PASS | `apps/api/src/tests/health_build_commit.test.ts:38` |
| **J.3** | Diagnostics overlay displays app commit and server commit | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:21` |
| **J.4** | Visual mismatch badge when app commit != server commit | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:205` |
| **K.1** | Inspect `flutter_webrtc-1.6.0` pub cache for service classes | PASS | Confirmed no `FlutterRTCForegroundService` bundled in package |
| **K.2** | ProGuard keep rules updated for `io.livekit.plugin.**` and WebRTC | PASS | `apps/mobile_flutter/android/app/proguard-rules.pro:10` |
| **K.3** | Compile-time flag `ENABLE_ANDROID_SCREEN_SHARE` defaults to false | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_classroom_screen.dart:20` |
| **K.4** | Graceful error handling toast ("Screen share shuru nahi ho paya") | PASS | `apps/mobile_flutter/lib/features/liveclass/presentation/live_class_room_controller.dart:1163` |
| **L.1** | Connect teacher token to LiveKit Cloud Room | PASS | `scripts/livekit-smoke.ts` (Connected to `wss://classora-80boeeiq.livekit.cloud`) |
| **L.2** | Connect student token to same LiveKit Cloud Room | PASS | `scripts/livekit-smoke.ts` (Both participants joined Room `smoke-class-live`) |
| **L.3** | Bidirectional reliable data packet exchange (Teacher <-> Student) | PASS | Direction [Teacher -> Student]: PASS; Direction [Student -> Teacher]: PASS |
