# ChatYuk threat model

Status: draft built from the code of `zunixe/ChatYuk`. The user has not yet answered the threat-model questions (asset priority, attackers, payment functions, accepted risks), so nothing below is a user-confirmed fact unless marked **[user]**. Unmarked statements are inferences from the code.

## System overview
ChatYuk is an Android-first Flutter chat app (Indonesian/English) on a single Supabase project:
- **Client:** Flutter app (`lib/`). Release flavors `apkpure` / `play` (entry `lib/main.dart`); admin flavor `admin` (entry `lib/main_admin.dart`, appId `com.chatyuk.chatyuk.admin`, personal device only). Admin code is tree-shaken from release builds via `lib/core/admin_gate.dart` and checked by `scripts/check_release_apk.sh`.
- **Backend:** Supabase Postgres with RLS and ~130 `SECURITY DEFINER` RPCs (`supabase/migrations/`, plus legacy loose SQL in `supabase/*.sql`), Supabase Auth (anonymous, email, Google), Realtime, Storage, and 13 Deno edge functions (`supabase/functions/`).
- **Third parties:** Firebase Cloud Messaging (push, via `send-push` / `fanout`), Cloudflare (TURN credentials, analytics), formerly Midtrans / iPaymu (payments).
- **Infrastructure:** no separate infrastructure repository. `supabase/config.toml` (function `verify_jwt` settings) and the migrations are the infrastructure definition. Firebase rules: `firestore.rules`, `database.rules*.json`.

## Trust boundaries
1. Device ↔ Supabase: the app ships only the publishable (anon) key (`lib/config/supabase_config.dart`). Anything the app can do, a user can do directly against PostgREST / RPC / Realtime / Storage with their own JWT. RLS and RPC checks are the real boundary; client-side checks (anti-screenshot, view-once, watermark, paywall UI) are not.
2. Internet ↔ edge functions with `verify_jwt = false`: `r` (referral redirect), `send-push`, `topup-webhook`, `ipaymu-callback`, `ipaymu-return`, `terms`.
3. DB triggers ↔ edge functions: `net.http_post` calls `send-push` / `fanout` with the shared secret `x-app-secret` (`supabase/functions/_shared/auth.ts`).
4. Regular user ↔ admin: admin authority is a hardcoded email check (`auth.email() = 'zunixe@gmail.com'`, also `auth.jwt()->>'email'`) in ~100 RPCs and in `admin-cf-usage`; `dummy-manage` compares against `ADMIN_EMAIL`. Some RPCs also accept `service_role`.
5. Admin ↔ dummy accounts: `dummy_accounts` stores refresh tokens of server-created anonymous accounts so the admin can act as them ("Dummy Session").

## Entry points and who can reach them
| Entry point | Reachable by |
|---|---|
| PostgREST tables + RPCs (`supabase/migrations`) | any JWT holder, including anonymous sign-ins (`AuthService.signInAnonymously`) |
| Realtime channels (chats, presence, calls, social) | any JWT holder, subject to RLS / channel auth |
| Storage buckets (e.g. `chat-photos`, public read, authenticated insert/delete) | any authenticated user; public URLs for reads |
| `send-push`, `migrate-photos` | holders of `APP_SHARED_SECRET` |
| `r`, `terms`, `ipaymu-return` | public internet |
| `topup-webhook`, `ipaymu-callback` | public internet, signature-checked (Midtrans / iPaymu) |
| `topup-create`, `ipaymu-create`, `turn-credentials`, `admin-cf-usage`, `dummy-manage`, `fanout` | JWT holders; admin-only ones check email |
| Deep links (`chatyuk://`) and FCM data-only pushes | other apps on the device / anyone who can trigger a push |

## Assets (draft; priority not yet confirmed by the user)
- Private 1:1 messages, room messages, view-once media, chat photos in Storage.
- Call signalling and call history; TURN credentials.
- Personal data: email, location / nearby users / location history, device info and FCM tokens, profile photos.
- Admin powers: chat monitoring, invisible mode, deleting chats, global settings, broadcast notifications, dummy-account sessions (stored refresh tokens).
- Coin / points balances, gifts, quests, leaderboard (digital goods only).
- Financial features (top-up, KYC, withdraw): removed from the app; their RPCs are revoked from `anon`/`authenticated` by `20260819140000_disable_financial_functions.sql`, but the tables and the payment edge functions remain in the repo.
- Secrets: Supabase service role key, `APP_SHARED_SECRET`, FCM service account, Cloudflare tokens, signing keystore and Play upload key.

## Attacker profiles (draft)
- **A1 Any app user, including an anonymous guest**, calling the API directly with their own JWT: reading or modifying other users' chats, media, location or profiles; escalating to admin; minting coins or points; abusing view-once or the paywall.
- **A2 Unauthenticated internet**: public edge functions, public Storage URLs, forged payment webhooks, open redirects in `r`.
- **A3 Malicious app on the same device**: deep links, exported Android components, local caches (message cache, media disk cache).
- **A4 Someone with repository access**: secrets committed to the repo or docs.
- Not assumed: a malicious admin (the admin is the owner).

## Existing controls
- RLS on core tables; `private_messages` SELECT is denied directly and goes through RPCs (`20260901010000_rpc_chat.sql`); hardening migrations (`20260812200000_hardening_rls.sql`, `fix_security*.sql`).
- Anonymous gating: `anon_gate`, `require_registration`, `*_registered_only` migrations; stale anonymous accounts are purged.
- Edge functions: shared secret for trigger-invoked ones, Midtrans / iPaymu signature checks, gateway JWT verification where `verify_jwt` is on.
- Admin code is excluded from release APKs (flavor gate + `check_release_apk.sh`).
- Client hardening: obfuscation, FLAG_SECURE / anti-screenshot, forensic watermark (`lib/services/forensic_watermark.dart`), screen secure service.

## Out of scope / accepted risk
- Nothing confirmed by the user yet.

## Open questions
1. Should `zunixe/ChatYuk-Admin` and `zunixe/ChatYuk_Web` (likely the same Supabase backend) be covered?
2. Which assets matter most (messages and view-once media, personal and location data, admin powers, coins)?
3. Which attackers matter (anonymous or signed-in users, unauthenticated internet, a malicious admin)?
4. Are the payment edge functions (`ipaymu-*`, `topup-*`) still deployed?
5. Accepted risks: bypassing anti-screenshot or the watermark on rooted devices; admins reading chats; spam and rate limiting by anonymous accounts?

## Components (finding tag `Component`)
| Component | Covers |
|---|---|
| Mobile App | `lib/` except admin code: `lib/screens` (non-admin), `lib/services`, `lib/providers`, `lib/widgets`, `lib/core`, `lib/main.dart`, plus `android/`, `ios/`, `web/` app config |
| Admin App | `lib/admin/`, `lib/screens/admin_*`, `lib/providers/admin_provider.dart`, `lib/main_admin.dart`, `lib/services/admin_*` |
| Database & RLS | `supabase/migrations/`, `supabase/*.sql` (tables, RLS, RPCs, triggers, Storage policies, Realtime) |
| Edge Functions | `supabase/functions/`, `supabase/config.toml` |
| Firebase | `firestore.rules`, `database.rules*`, `firebase.json`, `lib/firebase_options*.dart` |
| Build & Release | `fastlane/`, `scripts/`, `tool/`, keystore and signing config, `AGENTS.md` and other docs at the repo root |
