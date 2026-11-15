# CNHS Portal v2 (Flutter + Node + Supabase)

```
app/       Flutter: Android (students, teachers, parents) + Windows (teachers, USB sync)
backend/   Node.js API (Render) - writes, ID generation, USB/biometric parsing, push notifications
backend/sql/001_schema.sql, 002_ids.sql   Supabase database (RLS, realtime, storage buckets)
```

## Setup (in this order)
1. **Supabase**: new project -> SQL editor -> run `001_schema.sql` then `002_ids.sql`.
   Auth -> Providers -> enable **Google** (Google Cloud OAuth client). Auth -> URL config -> add redirect `io.cnhs.portal://login-callback`.
2. **Render**: New Web Service from the GitHub repo (it reads `render.yaml`). Set `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, optionally `FCM_SERVICE_ACCOUNT_JSON`.
3. **Firebase** (phone push): create project, add Android app `io.cnhs.portal`, download `google-services.json` -> GitHub secret `GOOGLE_SERVICES_JSON`; service-account JSON -> Render `FCM_SERVICE_ACCOUNT_JSON`.
4. **GitHub secrets**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_URL` (your Render URL), `GOOGLE_SERVICES_JSON`.
5. Locally once: `cd app && flutter create . --platforms=android,windows --org io.cnhs --project-name cnhs_portal`, then
   - `android/app/src/main/AndroidManifest.xml`: add an intent-filter for scheme `io.cnhs.portal`, host `login-callback`; apply the google-services Gradle plugin.
   - Windows: register the `io.cnhs.portal` URL scheme (supabase_flutter uses app_links; MSIX `protocol_activation` or an installer registry key).
   Commit and push -> GitHub Actions builds the APK and the Windows folder (Actions > Artifacts).

## How the USB sync works
| Event | What happens |
|---|---|
| Teacher plugs USB into the Windows PC | App finds the drive holding `Attendance_Logs*.txt` / `Employee_Form*.xls`, uploads both |
| Server reads punches | Stores every punch, first punch of day = IN, last = OUT, late if >15 min after the section's first class, then notifies the student + approved parents (in-app realtime + phone push) |
| End of day (17:30 PH, or `POST /api/attendance/close-day`) | No punch on a class day -> Absent, parents notified |
| Anything changes in the app (student added/edited/removed, section, schedule) | DB trigger marks the USB dirty -> Realtime -> app rewrites `Employee_Form.xls` on the stick (or on next plug-in) |

`Employee_Form.xls` layout matches your file (sheets *Employee Form* and *Attendance Rules Form*). Each section = one device department (max 16); the section's day span (first class start to last class end) becomes the shift (max 10 distinct spans).
`001_UserInfo.dat` holds fingerprint templates enrolled on the terminal; it is binary and proprietary, so the app never edits it.

## Notes
- Student ID `202627-48213` and Teacher ID `T-70519` keep your old scheme (race-safe, non-sequential).
- Admin is gone; the adviser (the teacher who creates the advisory) manages that section. Any teacher can approve parent links.
- Individual_Report_Employee-2_.xls in your upload is corrupt (all 0xFF bytes); nothing depends on it.
