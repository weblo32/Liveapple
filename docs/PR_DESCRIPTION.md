# Pull Request: Classora 2.0 Live Classroom & Production Hardening

## 1. Summary of Changes (Plain Language)
This pull request delivers complete live classroom reliability, production safety guards, and student/teacher experience enhancements:
- **Two-Way Audio/Video & Tile Sync:** Participant mic/camera icons now derive strictly from LiveKit track publication state, preventing false "muted" badges while students are speaking.
- **Stage Sync & Document Presentation:** Board, video grid, and PDF slide stages sync across all participants in real time. Late joiners automatically land on the active stage and page number. PPT/PPTX uploads provide a clear Hindi/English guidance message ("PPT ko PDF me export karo ya screen share karo").
- **Host Controls & Student Media Modes:** Classroom media modes (`OPEN` vs `HAND_RAISE_ONLY`) are enforced server-side via `livekit-server-sdk` participant permission updates. Includes host mute-all, per-student controls, FIFO hand-raise queue, and clear locked indicators for students.
- **Single-Device Session Enforcement:** Concurrent logins on a second device seamlessly take over the session; previous sessions receive a clean disconnect toast ("Aap dusre device se join ho gaye") with zero duplicate tiles.
- **Web App Serving & CSP Security:** The Flutter Web client is packaged at `/app/` with route-scoped Helmet CSP allowing API and LiveKit WebSocket connections (`wss:`), no-cache headers for instant updates, and desktop layout (>=900px) with dedicated stage and sidebar tabs.
- **Coursework Separation:** Distinct separation between Study Material (folders/files, no marks or due dates) and Assignments (due dates, marks, grading).
- **Duplicate Class & Demo Guard:** Safe idempotent scheduling migrations prevent duplicate class slots, and production demo safeguards prevent accidental data wiping.

---

## 2. Deployment Impact on Render
When this PR is merged into `main` on the upstream repository (`weblo32/Liveapple`):
1. **Build Step Execution:**
   - Render runs `npm install`, `prisma generate`, and `prisma migrate deploy` (or `prisma db push`).
   - The compiled Flutter Web client is packaged directly inside `apps/api/web-dist` and served statically at `/app/`.
2. **Database Migrations:**
   - The schema includes a unique compound index on `[slotId, scheduledDate]` for scheduled classes.
   - **Recommended Action:** Taking a quick PostgreSQL database backup/snapshot in Render dashboard prior to merging is recommended as standard operational best practice.
3. **Process Restart:**
   - Node process restarts with zero breaking schema changes.
   - Startup logs output a sanitized security flag check (boolean values only, no secrets exposed).

---

## 3. Required Environment Variables
Ensure the following environment variables are set in the Render Service Environment settings:

| Variable | Value / Format | Purpose |
|---|---|---|
| `NODE_ENV` | `production` | Enables production security & enforces demo data guards |
| `LIVEKIT_URL` | `wss://classora-80boeeiq.livekit.cloud` | LiveKit Cloud SFU WebSocket endpoint |
| `LIVEKIT_API_KEY` | *(Set in Render secret manager)* | LiveKit API Key (never commit to git) |
| `LIVEKIT_API_SECRET` | *(Set in Render secret manager)* | LiveKit API Secret (never commit to git) |
| `JWT_ACCESS_SECRET` | *(Random 32+ character string)* | Session token signing secret |
| `JWT_REFRESH_SECRET` | *(Random 32+ character string)* | Refresh token signing secret |
| `FORCE_DEMO_RESET` | `false` (or deleted) | Must NOT be true; neutralized in production |
| `ALLOW_DESTRUCTIVE_DEMO_RESET` | `false` (or omitted) | Prevents database wipe |

> [!IMPORTANT]
> The server automatically reads `RENDER_GIT_COMMIT` supplied by Render to display the exact deployed merge commit sha in `/api/health`.

---

## 4. Post-Merge Verification Checklist
After Render finishes deploying the merge commit, verify the following endpoints:

1. **`GET /api/health`**
   ```json
   {
     "status": "ok",
     "service": "Classora 2.0 API & Realtime Gateway",
     "version": "2.0.0",
     "build": {
       "commit": "<merge-commit-short-sha>",
       "environment": "production"
     },
     "livekit": {
       "configured": true,
       "urlHost": "classora-80boeeiq.livekit.cloud",
       "urlIsWss": true,
       "usingDefaultKeys": false
     }
   }
   ```
2. **`GET /app/`**
   - Returns HTTP `200 OK`.
   - Headers include `Content-Security-Policy` with `connect-src 'self' ... wss://classora-80boeeiq.livekit.cloud`.
   - Loads Classora Web classroom interface without console CSP violations.

---

## 5. Rollback Steps
If unexpected regressions occur:
1. In the Render Dashboard, navigate to the Service > **Deploys** tab.
2. Select the previous successful deployment and click **Rollback to this deploy**.
3. Because all database changes are non-destructive and backward-compatible, rolling back application code will not corrupt existing records.

---

## 6. Known Limitations
- **Android Native Screen Share:** Android 14+ requires an interactive system foreground service permission prompt before capturing screen. Default release APK hides the button on Android to prevent crashes; a test build with compile-time flag `ENABLE_ANDROID_SCREEN_SHARE=true` is provided for physical device verification. Web screen share is fully operational.
- **Physical Device Tests:** Automated CI test suites verify socket protocols, SFU token issuance, and bidirectional data exchange. Real phone testing on physical carriers depends on device-specific battery savers and permission grants.

---

## 7. Real PDF Slides Presentation & Bottom Controls Bar Polish
- **Shared PDF Slides Contract & Persistence:** Real PDF slides now upload to `/api/v1/classes/:id/slides`, compute SHA-256 and page count, and persist in database table `ClassSlideDeck` to survive Render container restarts.
- **Student Synchronization & Error Handling:** Students authenticate file download using existing bearer tokens; if download fails, a clear error ("Slides load nahi ho payi") with Retry is shown instead of a perpetual placeholder.
- **Controls Bar Responsiveness (Zero Clipping):** Re-engineered bottom controls bar to dynamically collapse on compact widths (320-393dp) and 1.3 text scale without text clipping ("Mic", "Video", "Hand", "More", "Leave").
- **Present Button Icon Restoration:** Fixed active state icon styling so the Present button displays a high-contrast white icon on a vibrant blue circle, eliminating the empty blue circle defect.
- **Diagnostics Overlay:** Added real-time Slides diagnostics section displaying deckId, totalPages, currentPage, receive source, fetch status, and loaded byte size.
