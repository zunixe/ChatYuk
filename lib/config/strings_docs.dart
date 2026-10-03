// String DOKUMENTASI admin — JANGAN di-import dari kode build rilis.
// Extension on S: hanya modul admin yang meng-import file ini, sehingga
// tree shaker membuang seluruh string bersama layar admin.
import 'strings.dart';

extension SDocsX on S {
  // ── Tab & cari ──
  String get adminDocsTab => isId ? 'Dokumentasi' : 'Docs';
  String get adminDocsUser => isId ? 'Pengguna' : 'User';
  String get adminDocsDeveloper => isId ? 'Developer' : 'Developer';
  String get adminDocsSearch =>
      isId ? 'Cari dokumentasi...' : 'Search docs...';
  String get adminDocsEmpty =>
      isId ? 'Tidak ada yang cocok' : 'No match found';
  String get adminDocsUserIntro => isId
      ? 'Panduan semua fitur ChatYuk dengan bahasa sederhana. Tulis ulang dengan kata-katamu saat menjelaskan ke user.'
      : 'A plain-language guide to every ChatYuk feature. Rephrase in your own words when explaining to users.';
  String get adminDocsDevIntro => isId
      ? 'Ringkasan arsitektur & service untuk developer. Detail penuh ada di docs/ARCHITECTURE.md dan docs/FEATURE_MAP.md.'
      : 'Architecture & service summary for developers. Full details live in docs/ARCHITECTURE.md and docs/FEATURE_MAP.md.';

  // ── PENGGUNA: Masuk & Akun ──
  String get docsUserAuthTitle => isId ? '🚪 Masuk & Akun' : '🚪 Sign-in & Account';
  String get docsUserAuthBody => isId
      ? 'ChatYuk bisa dipakai tanpa daftar: isi nickname, gender, umur, negara, dan kota, lalu langsung chat sebagai tamu (guest).\n\n• Daftar email: naikkan akun tamu jadi permanen (bisa login di HP lain).\n• Login Google: satu ketuk, otomatis pilih akun tiap kali.\n• Lupa password: kirim link reset ke email terdaftar.\n• Tautkan email: tamu lama bisa dikaitkan ke email tanpa kehilangan chat.'
      : 'ChatYuk works without registering: enter a nickname, gender, age, country, and city, then chat instantly as a guest.\n\n• Email register: upgrade a guest into a permanent account (sign in on another phone).\n• Google sign-in: one tap, always asks which account.\n• Forgot password: reset link sent to the registered email.\n• Link email: attach an email to an old guest without losing chats.';

  // ── PENGGUNA: Pengguna Online ──
  String get docsUserOnlineTitle =>
      isId ? '🔴 Pengguna Online' : '🔴 Online Users';
  String get docsUserOnlineBody => isId
      ? 'Melihat siapa yang sedang online saat ini, lengkap dengan status online / idle / offline.\n\n• Filter negara & gender, plus kolom cari.\n• Ketuk user untuk lihat profil atau langsung chat.\n• User mode invisible memang disembunyikan dari daftar ini.'
      : 'See who is online right now, with online / idle / offline status.\n\n• Filter by country & gender, plus search.\n• Tap a user to view their profile or start chatting.\n• Users in invisible mode are intentionally hidden from this list.';

  // ── PENGGUNA: Chat Pribadi ──
  String get docsUserPrivateTitle =>
      isId ? '💬 Chat Pribadi 1:1' : '💬 Private 1:1 Chat';
  String get docsUserPrivateBody => isId
      ? 'Ngobrol berdua yang cepat seperti WhatsApp: pesan muncul instan, centang-2 langsung terlihat.\n\n• Kirim teks, foto, voice note, lokasi, dan YukCoin.\n• Geser bubble ke kanan untuk balas (reply), tekan lama untuk reaksi emoji, teruskan, edit, atau hapus pesan.\n• Foto Sekali Lihat: hanya bisa dibuka sekali, lalu hilang.\n• Tanda centang-2 = sudah dibaca; indikator mengetik terlihat live.\n• Pesan tetap terkirim walau sinyal putus (antre otomatis, kirim saat online).\n• Blokir & laporkan user nakal dari dalam chat.'
      : 'Fast two-person chat like WhatsApp: messages appear instantly with immediate double-checks.\n\n• Send text, photos, voice notes, locations, and YukCoin.\n• Swipe a bubble right to reply; long-press for emoji reactions, forward, edit, or delete.\n• View-once photo: opens a single time, then disappears.\n• Double-check = read; live typing indicator.\n• Messages queue offline and send automatically when back online.\n• Block & report abusive users from inside the chat.';

  // ── PENGGUNA: Room ──
  String get docsUserRoomsTitle =>
      isId ? '🏠 Room Global & Private' : '🏠 Global & Private Rooms';
  String get docsUserRoomsBody => isId
      ? 'Room Global: ruang ngobrol terbuka per negara dengan 10 kategori (General, Curhat, Pertemanan, Teknologi, Gaming, Musik, Film & TV, Joke & Meme, Belajar, Flirt). Gratis, tanpa password.\n\n• Room Private: ruang berbayar (YukCoin) milik sendiri — buat, kasih password/QR undangan, setujui member (maks 20), perpanjang tiap 7 hari.\n• Di room ada mention (@nama/@all), reaksi, voice stage (maks 6 mic), siaran (broadcast), dan angkat tangan Minta bicara.\n• Pemilik/admin bisa promote, mute, dan keluarkan member.'
      : 'Global rooms: open country-based chat with 10 categories (General, Curhat, Friends, Tech, Gaming, Music, Movies & TV, Jokes & Memes, Study, Flirt). Free, no password.\n\n• Private rooms: paid (YukCoin) rooms you own — create, set password/QR invite, approve members (max 20), extend every 7 days.\n• Rooms support mentions (@name/@all), reactions, voice stage (max 6 mics), broadcast, and raise-hand to speak.\n• Owners/admins can promote, mute, and remove members.';

  // ── PENGGUNA: Grup ──
  String get docsUserGroupTitle => isId ? '👥 Grup' : '👥 Groups';
  String get docsUserGroupBody => isId
      ? 'Grup pribadi terpisah dari room: cocok untuk lingkaran sendiri.\n\n• Buat grup (gratis), undang lewat token, atur password atau tanpa password.\n• Info grup: ganti nama/ikon, lihat media & anggota, bisukan notifikasi.\n• Pemilik bisa hapus grup; member bisa keluar kapan saja.'
      : 'Personal groups, separate from rooms: ideal for your own circle.\n\n• Create a group (free), invite via token, with or without password.\n• Group info: rename/re-icon, browse media & members, mute notifications.\n• Owners can delete the group; members can leave anytime.';

  // ── PENGGUNA: Call ──
  String get docsUserCallTitle =>
      isId ? '📞 Voice & Video Call' : '📞 Voice & Video Call';
  String get docsUserCallBody => isId
      ? 'Nelpon suara/video 1:1 langsung dari chat (teknologi WebRTC).\n\n• Layar panggilan masuk + notifikasi panggilan tak terjawab.\n• Riwayat panggilan: siapa menelepon, diangkat atau tidak.\n• Call berbayar YukCoin per menit (audio 6, video 20) — sebagian masuk ke yang ditelepon.\n• Anti-spam: akun tamu hanya bisa nelpon bila admin mengizinkan.'
      : '1:1 voice/video calls straight from chat (WebRTC).\n\n• Incoming-call screen + missed-call notifications.\n• Call history: who called, answered or not.\n• Calls cost YukCoin per minute (audio 6, video 20) — part goes to the callee.\n• Anti-spam: guests can only call when the admin allows it.';

  // ── PENGGUNA: Stories ──
  String get docsUserStoryTitle => isId ? '📸 Stories' : '📸 Stories';
  String get docsUserStoryBody => isId
      ? 'Bagikan momen harian yang hilang sendiri setelah 24 jam.\n\n• Ambil dari kamera atau pilih dari galeri, tambah teks/emoji.\n• Lihat story teman lewat tray di beranda; siapa yang melihat tercatat.\n• Story hanya tampil sesuai pengaturan privasimu.'
      : 'Share daily moments that disappear after 24 hours.\n\n• Capture with the camera or pick from gallery, add text/emoji.\n• Watch friends\u2019 stories from the home tray; views are recorded.\n• Stories only show according to your privacy settings.';

  // ── PENGGUNA: Timeline ──
  String get docsUserTimelineTitle => isId ? '📝 Timeline' : '📝 Timeline';
  String get docsUserTimelineBody => isId
      ? 'Postingan status ala media sosial dengan penonton yang bisa diatur.\n\n• Tulis postingan, atur siapa yang bisa lihat: publik / pengikut / pelanggan.\n• Komentar, reaksi, dan bagikan postingan ke chat.\n• Follow kreator favorit; berlangganan (subscribe) untuk konten khusus.\n• Blokir bersifat dua arah di timeline (saling menyembunyikan).'
      : 'Social-style status posts with an audience you control.\n\n• Write posts, choose viewers: public / followers / subscribers.\n• Comment, react, and share posts into chats.\n• Follow favorite creators; subscribe for exclusive content.\n• Blocking is two-way on the timeline (mutually hidden).';

  // ── PENGGUNA: Nearby ──
  String get docsUserNearbyTitle =>
      isId ? '🗺️ Orang Sekitar' : '🗺️ People Nearby';
  String get docsUserNearbyBody => isId
      ? 'Temukan user lain di sekitarmu berbasis lokasi di peta.\n\n• Nyalakan Bagikan Lokasi + atur radius pencarian.\n• Ketuk pin/nama untuk profil & chat.\n• Lokasi GPS tidak pernah ditimpa perkiraan IP — tetap akurat.\n• Fitur harian berbayar YukCoin (diaktifkan admin bila dipublish).'
      : 'Discover other users around you on a location map.\n\n• Turn on Share Location + set search radius.\n• Tap a pin/name for profile & chat.\n• GPS location is never overwritten by IP estimates — stays accurate.\n• Daily paid feature in YukCoin (enabled by admin when published).';

  // ── PENGGUNA: Misi & Leaderboard ──
  String get docsUserMissionsTitle =>
      isId ? '🏆 Misi & Top Aktif' : '🏆 Missions & Top Active';
  String get docsUserMissionsBody => isId
      ? 'Kumpulkan YukCoin gratis lewat misi, dan adu aktif di papan peringkat.\n\n• Misi harian, mingguan, dan sekali-selesai — klaim hadiahnya, jaga streak login.\n• Top Aktif: peringkat chat terseru minggu ini / sepanjang masa.\n• Ada juga Top Saldo di Profil (berbasis koin).'
      : 'Earn free YukCoin through missions, and compete on activity boards.\n\n• Daily, weekly, and one-time quests — claim rewards, keep your streak.\n• Top Active: chattiest ranking this week / all time.\n• There is also a Top Balance board in Profile (coin-based).';

  // ── PENGGUNA: Top up & riwayat ──
  String get docsUserTopupTitle =>
      isId ? '💳 Top Up & Riwayat Koin' : '💳 Top-up & Coin History';
  String get docsUserTopupBody => isId
      ? 'YukCoin = satu saldo untuk semua fitur berbayar.\n\n• Dapat dari: top up Google Play Billing (khusus build Play Store), bonus selamat datang user baru, dan pemasukan saat ditelepon.\n• Dipakai untuk: nelpon, filter gender, orang sekitar, undo/edit pesan, mode invisible, slot foto, buka foto, room, dan gift.\n• Katalog gift: Mawar 10, Kopi 25, Boneka 50, Kue 75, Berlian 150, Mahkota 300, Roket 500, Mobil Sport 1000.\n• Riwayat Koin mencatat semua masuk-keluar.'
      : 'YukCoin = one balance for every paid feature.\n\n• Earned from: Google Play Billing top-up (Play Store build only), new-user welcome bonus, and income when called.\n• Spent on: calls, gender filter, nearby, undo/edit messages, invisible mode, photo slots, photo unlocks, rooms, and gifts.\n• Gift catalog: Rose 10, Coffee 25, Teddy 50, Cake 75, Diamond 150, Crown 300, Rocket 500, Sports Car 1000.\n• Coin History records every in and out.';

  // ── PENGGUNA: Profil ──
  String get docsUserProfileTitle =>
      isId ? '👤 Profil & Galeri' : '👤 Profile & Gallery';
  String get docsUserProfileBody => isId
      ? 'Kartu identitasmu di ChatYuk.\n\n• Foto profil + galeri foto (bisa dikunci: orang lain bayar koin untuk buka).\n• Ganti username, status/about, umur, kota.\n• Lihat daftar langganan, permintaan teman, dan kontak.\n• Ganti bahasa Indonesia/English dan tema dari sini.'
      : 'Your identity card in ChatYuk.\n\n• Profile photo + photo gallery (can be locked: others pay coins to unlock).\n• Change username, status/about, age, city.\n• See subscriptions, friend requests, and contacts.\n• Switch language (Indonesian/English) and theme from here.';

  // ── PENGGUNA: Privasi ──
  String get docsUserPrivacyTitle =>
      isId ? '🛡️ Privasi & Blokir' : '🛡️ Privacy & Blocking';
  String get docsUserPrivacyBody => isId
      ? 'Kamu yang pegang kendali siapa bisa lihat apa.\n\n• Atur per bagian: status online, terakhir dilihat, foto profil, tentang, story, Top Aktif — pilih Semua / Teman / Sembunyikan / pengecualian.\n• Centang baca bisa dimatikan (lawan tidak lihat centang-2).\n• Blokir user di chat (satu arah); laporkan chat nakal ke admin.\n• Foto Sekali Lihat bisa bertanda watermark forensik (ketahuan bila disebar).'
      : 'You control who sees what.\n\n• Set per section: online status, last seen, profile photo, about, story, Top Active — Everyone / Friends / Hidden / exceptions.\n• Read receipts can be turned off (no double-check for them).\n• Block users in chat (one-way); report abusive chats to admin.\n• View-once photos can carry a forensic watermark (traceable if leaked).';

  // ── PENGGUNA: Pengaturan ──
  String get docsUserSettingsTitle =>
      isId ? '⚙️ Pengaturan & Notifikasi' : '⚙️ Settings & Notifications';
  String get docsUserSettingsBody => isId
      ? 'Semua saklar aplikasi ada di menu Pengaturan.\n\n• Akun: data diri, tautkan email, keluar, hapus akun.\n• Notifikasi: atur per kategori (chat, call, mention, timeline) + suara.\n• Bahasa, tema terang/gelap, kualitas foto (Standar/HD), font chat.\n• Mode invisible (tak terlihat online, berbayar harian).\n• Info versi + popup bila ada update wajib.'
      : 'Every app switch lives in Settings.\n\n• Account: personal data, link email, sign out, delete account.\n• Notifications: per-category toggles (chat, call, mention, timeline) + sound.\n• Language, light/dark theme, photo quality (Standard/HD), chat font.\n• Invisible mode (hidden online, daily paid).\n• Version info + popup when a mandatory update exists.';

  // ── PENGGUNA: Bantuan ──
  String get docsUserHelpTitle =>
      isId ? '🆘 Bantuan & Keamanan' : '🆘 Help & Safety';
  String get docsUserHelpBody => isId
      ? 'Butuh bantuan manusia? Ada jalurnya.\n\n• Menu Kontak/Hubungi: kirim pesan langsung ke admin, dibalas via panel.\n• Syarat & Kebijakan Privasi bisa dibaca di aplikasi.\n• Tips aman: jangan bagikan kode login, blokir + laporkan bila diganggu, screenshot bisa dibatasi admin untuk sekali-lihat.'
      : 'Need a human? There is a channel.\n\n• Contact menu: message the admin directly, answered via the panel.\n• Terms & Privacy Policy are readable inside the app.\n• Safety tips: never share login codes, block + report harassment, screenshots can be restricted by admin for view-once.';

  // ── PENGGUNA: Kelola & rapikan chat ──
  String get docsUserOrganizeTitle =>
      isId ? '🗂️ Kelola & Rapikan Chat' : '🗂️ Manage & Tidy Chats';
  String get docsUserOrganizeBody => isId
      ? 'Bikin daftar chat rapi seperti WhatsApp.\n\n• Sematkan (pin) chat penting di atas, arsipkan yang jarang dipakai (tab Arsip).\n• Bintang (star) pesan penting supaya mudah dicari lagi.\n• Teruskan (forward) pesan ke chat/grup lain, salin teks.\n• Tandai belum dibaca (Read all / unread), cari pesan di dalam chat.\n• Mode seleksi: pilih banyak pesan lalu hapus sekaligus.'
      : 'Keep your chat list tidy like WhatsApp.\n\n• Pin important chats to the top, archive rarely-used ones (Archived tab).\n• Star important messages for easy finding later.\n• Forward messages to other chats/groups, copy text.\n• Mark read/unread, search inside a chat.\n• Selection mode: pick many messages and delete at once.';

  // ── PENGGUNA: Fitur berbayar koin (undo/edit/ghost/slot) ──
  String get docsUserCoinFxTitle =>
      isId ? '✨ Fitur Koin (Undo, Edit, Ghost, Slot)' : '✨ Coin Features (Undo, Edit, Ghost, Slots)';
  String get docsUserCoinFxBody => isId
      ? 'Beberapa aksi pintar memakai YukCoin (nominal diatur admin).\n\n• Undo: tarik kembali pesan yang baru dikirim.\n• Edit: perbaiki tulisan pesan yang sudah terkirim.\n• Mode Hantu (invisible): status online disembunyikan, tetap bisa chat — bayar per hari.\n• Slot Foto: tambah jatah slot di galeri profil (+5 slot).\n• Semua ini hanya muncul setelah admin mem-publish (YukCoin v2).'
      : 'Some smart actions cost YukCoin (rates set by the admin).\n\n• Undo: pull back a message just sent.\n• Edit: fix an already-sent message.\n• Ghost (invisible) mode: hide your online status while still chatting — paid daily.\n• Photo Slots: add gallery slots to your profile (+5 slots).\n• All of these appear only after the admin publishes them (YukCoin v2).';

  // ── PENGGUNA: Foto berbayar & sekali lihat ──
  String get docsUserPhotoPayTitle =>
      isId ? '🔓 Foto Berbayar & Sekali Lihat' : '🔓 Paid Photos & View-Once';
  String get docsUserPhotoPayBody => isId
      ? 'Foto di galeri bisa dikunci sebagai konten premium.\n\n• Orang lain bayar YukCoin untuk membuka: lihat sekali ATAU permanen (nominal diatur admin).\n• Sebagian hasil masuk ke pemilik foto.\n• Foto Sekali Lihat: penerima hanya bisa membuka 1x, setelah itu hangus; bisa dipasangi watermark forensik berisi identitas penerima.\n• Ada juga timer pesan (mis. 1x lihat / hitung mundur) untuk teks/foto tertentu.'
      : 'Gallery photos can be locked as premium content.\n\n• Others pay YukCoin to unlock: view-once OR permanent (rates set by the admin).\n• Part of the revenue goes to the photo owner.\n• View-once photos: the receiver can open only once, then it expires; a forensic watermark with the receiver\u2019s identity can be embedded.\n• There is also a message timer (e.g. view-once / countdown) for certain texts/photos.';

  // ── PENGGUNA: Voice stage & broadcast room ──
  String get docsUserRoomLiveTitle =>
      isId ? '🎙️ Voice Stage & Broadcast Room' : '🎙️ Room Voice Stage & Broadcast';
  String get docsUserRoomLiveBody => isId
      ? 'Di room global ada panggung suara & siaran langsung.\n\n• Voice Stage: sampai 6 orang nyalakan mic bersamaan (audio saja) — naik ke "panggung" untuk bicara, sisanya mendengarkan.\n• Angkat tangan (hand raise) minta izin bicara; admin room bisa izinkan/mute paksa.\n• Broadcast/Live: admin room menyiarkan ke semua anggota; penonton dapat notifikasi LIVE.\n• Maks 6 mic dijaga server; keluar room otomatis mematikan mic (tak nyangkut).'
      : 'Global rooms have a voice stage & live broadcast.\n\n• Voice Stage: up to 6 people turn on mics at once (audio-only) — go on \u201cstage\u201d to speak, the rest listen.\n• Raise hand to ask to speak; the room admin can allow or force-mute.\n• Broadcast/Live: the room admin streams to all members; viewers get a LIVE notification.\n• The 6-mic cap is enforced server-side; leaving the room turns the mic off automatically.';

  // ── PENGGUNA: Undang & teman ──
  String get docsUserSocialTitle =>
      isId ? '🤝 Teman, Pengikut & Undangan' : '🤝 Friends, Followers & Invites';
  String get docsUserSocialBody => isId
      ? 'Bangun lingkaran sosialmu.\n\n• Permintaan teman: kirim/terima/tolak; ada kotak masuk & terkirim.\n• Pengikut (follow) & pelanggan (subscriber) — lihat daftarnya dari profil.\n• Undang ke grup/room dari daftar orang yang pernah chat denganmu.\n• Bagikan aplikasi (share app) ke teman lewat tautan referral.'
      : 'Build your social circle.\n\n• Friend requests: send/accept/reject; with an inbox and sent list.\n• Followers & subscribers — view the lists from your profile.\n• Invite people to groups/rooms from those you have chatted with.\n• Share the app with friends via a referral link.';

  // ── PENGGUNA: Lengkapi profil & onboarding ──
  String get docsUserOnboardTitle =>
      isId ? '🎯 Lengkapi Profil & Mulai' : '🎯 Profile Completion & Getting Started';
  String get docsUserOnboardBody => isId
      ? 'ChatYuk memandu user baru langkah demi langkah.\n\n• Lobby: isi negara/kota, pilih minat, dan mulai chat.\n• Kartu "Lengkapi Profil" mengingatkan isi yang kurang (foto, tentang, dll).\n• Panduan YukCoin menjelaskan cara dapat & pakai koin.\n• Popup minta daftar email saat mencoba fitur khusus (call, nearby, timeline) — biar akun aman & bisa pulih.'
      : 'ChatYuk guides new users step by step.\n\n• Lobby: set country/city, pick interests, and start chatting.\n• The \u201cComplete Profile\u201d card reminds you of missing bits (photo, about, etc.).\n• The YukCoin guide explains how to earn & spend coins.\n• A popup asks to register an email when trying special features (calls, nearby, timeline) — so the account is safe & recoverable.';

  // ── PENGGUNA: Donasi ──
  String get docsUserDonateTitle =>
      isId ? '💝 Donasi (Dukungan Sukarela)' : '💝 Donations (Optional Support)';
  String get docsUserDonateBody => isId
      ? 'Dukung ChatYuk supaya tetap gratis & bebas iklan.\n\n• Donasi sukarela via QRIS (semua dompet digital & m-banking Indonesia) atau USDT Crypto.\n• Wajib kirim ke network yang benar — salah network, dana bisa hilang.\n• Donasi berbeda dari YukCoin: koin dibuat untuk belanja dalam aplikasi, donasi murni dukungan.'
      : 'Support ChatYuk to keep it free & ad-free.\n\n• Optional donations via QRIS (all Indonesian e-wallets & m-banking) or USDT Crypto.\n• Always send to the correct network — a wrong network may lose funds.\n• Donations differ from YukCoin: coins are for spending in-app, donations are pure support.';

  // ── DEV: Lapisan ──
  String get docsDevLayersTitle =>
      isId ? '🧱 Lapisan Aplikasi' : '🧱 App Layers';
  String get docsDevLayersBody => isId
      ? 'Alur data: screens → providers → services → Supabase (RPC/tabel) → models → notifyListeners → UI rebuild. Realtime: service buka channel, dorong update ke provider.\n\n• screens/: UI saja, DILARANG import services/ (gate: scripts/check_screen_boundary.sh).\n• providers/: ChangeNotifier + orkestrasi (pecah part-mixin bila besar).\n• services/: satu-satunya yang boleh panggil Supabase.\n• core/: helper murni (cache, media, perf) — juga dilarang import services/.\n• Entry: lib/main.dart (user: apkpure/play) & lib/main_admin.dart (admin). Berbagi lib/app.dart; kode admin dipisah via AdminGate agar ter-tree-shake dari APK rilis.'
      : 'Data flow: screens → providers → services → Supabase (RPC/tables) → models → notifyListeners → UI rebuild. Realtime: services open channels, push updates to providers.\n\n• screens/: UI only, MUST NOT import services/ (gate: scripts/check_screen_boundary.sh).\n• providers/: ChangeNotifier + orchestration (split into part-mixins when large).\n• services/: the only layer allowed to call Supabase.\n• core/: pure helpers (cache, media, perf) — also must not import services/.\n• Entries: lib/main.dart (user: apkpure/play) & lib/main_admin.dart (admin). Both share lib/app.dart; admin code is isolated via AdminGate so it tree-shakes out of release APKs.';

  // ── DEV: Backend ──
  String get docsDevBackendTitle =>
      isId ? '🗄️ Backend Supabase' : '🗄️ Supabase Backend';
  String get docsDevBackendBody => isId
      ? 'Tanpa server API sendiri — logika hidup di Postgres + Edge Functions.\n\n• supabase/migrations/: skema, RPC SECURITY DEFINER, trigger, cron, RLS (timestamp UNIK; fungsi FROZEN dilarang di-redefine via copy-paste — lihat scripts/frozen_functions.txt).\n• Sumber kebenaran SQL: supabase/snapshots/functions.sql.\n• Tabel kunci: profiles, user_photos, private_chats, private_messages, messages, rooms, room_members, calls, call_signals, coin_ledger, blocks, follows, posts, stories, user_devices, dummy_accounts, outbox, app_settings.\n• Cron (pg_cron): housekeeping tiap menit (presence idle + voice + room), ai-presence 5 mnt, claim-recovery 5 mnt, missed-recovery 3 mnt, outbox-worker 1 mnt, call-sweep 5 mnt.\n• Terapkan SQL di Mac ini HANYA via Management API (CLI db push/query HANG).'
      : 'No self-owned API server — logic lives in Postgres + Edge Functions.\n\n• supabase/migrations/: schema, SECURITY DEFINER RPCs, triggers, cron, RLS (UNIQUE timestamps; FROZEN functions must not be redefined via copy-paste — see scripts/frozen_functions.txt).\n• SQL source of truth: supabase/snapshots/functions.sql.\n• Key tables: profiles, user_photos, private_chats, private_messages, messages, rooms, room_members, calls, call_signals, coin_ledger, blocks, follows, posts, stories, user_devices, dummy_accounts, outbox, app_settings.\n• Cron (pg_cron): per-minute housekeeping (idle presence + voice + rooms), ai-presence 5m, claim-recovery 5m, missed-recovery 3m, outbox-worker 1m, call-sweep 5m.\n• On this Mac apply SQL ONLY via the Management API (CLI db push/query HANGS).';

  // ── DEV: Edge ──
  String get docsDevEdgeTitle =>
      isId ? '⚡ Edge Functions' : '⚡ Edge Functions';
  String get docsDevEdgeBody => isId
      ? 'Fungsi Deno di supabase/functions/ (autentikasi antar-layanan via header x-app-secret dari app_settings.app_shared_secret).\n\n• send-push & outbox-worker: kirim push FCM (worker menguras tabel outbox tiap menit).\n• ai-reply & ai-daily-life: balasan + cerita harian dummy AI.\n• welcome-bonus: klaim bonus anti-farming (cek IP server-side).\n• play-topup-verify: verifikasi pembelian Play Billing → kredit koin.\n• turn-credentials: kredensial TURN untuk call.\n• fanout & dummy-manage: kipas notifikasi topik & kelola dummy.\n• migrate-photos, admin-cf-usage, terms, r: utilitas (migrasi foto, kuota TURN, syarat, redirect share).'
      : 'Deno functions in supabase/functions/ (service-to-service auth via x-app-secret header from app_settings.app_shared_secret).\n\n• send-push & outbox-worker: send FCM push (worker drains the outbox table every minute).\n• ai-reply & ai-daily-life: dummy-AI replies + daily stories.\n• welcome-bonus: anti-farming bonus claims (server-side IP check).\n• play-topup-verify: verify Play Billing purchases → credit coins.\n• turn-credentials: TURN credentials for calls.\n• fanout & dummy-manage: topic fan-out & dummy management.\n• migrate-photos, admin-cf-usage, terms, r: utilities (photo migration, TURN quota, terms, share redirect).';

  // ── DEV: Realtime ──
  String get docsDevRealtimeTitle =>
      isId ? '📡 Realtime & Presence' : '📡 Realtime & Presence';
  String get docsDevRealtimeBody => isId
      ? 'Pesan & status live via Supabase Realtime.\n\n• Pesan: channel per chat (msg-<chatId>), INSERT di-append langsung (0 round-trip); UPDATE/DELETE reload ter-debounce.\n• Presence: channel global via RealtimeHub; status dihitung server (effectiveStatusOf: last_seen >30 mnt = offline; invisible = offline).\n• Aturan dummy: ai_always_online selalu online; wake memaksa online; offline memaksa offline; di luar jam aktif = offline.\n• Notif massal tidak menunggu HTTP di transaksi — tulis ke tabel outbox, worker yang kirim (transaksi cepat & tahan gagal).\n• Token FCM dibaca dari user_devices.fcm_token (helper user_fcm_tokens), BUKAN profiles.fcm_token.'
      : 'Live messages & status via Supabase Realtime.\n\n• Messages: per-chat channel (msg-<chatId>), INSERTs appended directly (0 round-trips); UPDATE/DELETE trigger debounced reloads.\n• Presence: global channel via RealtimeHub; status computed server-side (effectiveStatusOf: last_seen >30m = offline; invisible = offline).\n• Dummy rules: ai_always_online stays online; wake forces online; offline forces offline; outside active hours = offline.\n• Mass notifications never wait on HTTP inside transactions — they write to the outbox table, a worker sends them (fast & failure-proof).\n• FCM tokens come from user_devices.fcm_token (helper user_fcm_tokens), NOT profiles.fcm_token.';

  // ── DEV: Cache ──
  String get docsDevCacheTitle =>
      isId ? '💾 Cache & Offline' : '💾 Cache & Offline';
  String get docsDevCacheBody => isId
      ? 'Buka chat terasa WhatsApp karena cache berlapis.\n\n• Pesan & blob di SQLite terenkripsi (SQLCipher, kunci dari Android Keystore); foto/voice = file terenkripsi terpisah.\n• ChatStreamSession: replay onListen (memori → SQLite → server, merge).\n• Antrean offline (ChatOutboxMixin): kirim otomatis saat online kembali.\n• Warm-up 6 chat teratas + snapshot list agar centang-2 siap di frame pertama (read receipt monoton maju — tak boleh mundur).\n• Semua RPC lewat measuredRpc (metrik saat PERF_PROBE, nol overhead saat mati); koneksi HTTP dibatasi timeout 5 dtk + idle 15 dtk anti \u201cngelag setelah idle\u201d.'
      : 'Opening a chat feels like WhatsApp thanks to layered caching.\n\n• Messages & blobs in encrypted SQLite (SQLCipher, key from Android Keystore); photos/voice = separate encrypted files.\n• ChatStreamSession: replay onListen (memory → SQLite → server, merged).\n• Offline queue (ChatOutboxMixin): auto-sends when back online.\n• Warm-up of top 6 chats + list snapshot so double-checks are ready on the first frame (read receipts only move forward).\n• Every RPC goes through measuredRpc (metrics when PERF_PROBE is on, zero overhead when off); HTTP capped at 5s timeout + 15s idle against \u201c lag after idle\u201d.';

  // ── DEV: Services ──
  String get docsDevServicesTitle =>
      isId ? '🧰 Katalog Service' : '🧰 Service Catalog';
  String get docsDevServicesBody => isId
      ? 'lib/services/ — satu-satunya lapisan yang bicara ke Supabase.\n\n• ChatService (dipecah part-mixin per domain: private, chatlist, room, typing, presence, gift) + chat_stream_session, realtime_hub, rt_resilient.\n• call_service + call/ (UI sistem & ConnectionService native) + turn-credentials.\n• room_service, private_room_service, room_voice_service, room_broadcast_service, room_media_service.\n• auth_service (+auth/profile/settings), social_service, timeline_service, story_service.\n• points_service, topup_service (Play Billing), subscription_rpc.\n• privacy_service, message_reaction_service, notification_prefs_service, push_topic_service.\n• contact_service, device_info_service, location_service, geo_service, avatar_service, storage_photo_service, attribution_service, meta_analytics_service, tiktok_service, app_update_service.\n• admin_service + admin_call_watch_service (khusus build admin).'
      : 'lib/services/ — the only layer that talks to Supabase.\n\n• ChatService (split into part-mixins per domain: private, chatlist, room, typing, presence, gift) + chat_stream_session, realtime_hub, rt_resilient.\n• call_service + call/ (system UI & native ConnectionService) + turn-credentials.\n• room_service, private_room_service, room_voice_service, room_broadcast_service, room_media_service.\n• auth_service (+auth/profile/settings), social_service, timeline_service, story_service.\n• points_service, topup_service (Play Billing), subscription_rpc.\n• privacy_service, message_reaction_service, notification_prefs_service, push_topic_service.\n• contact_service, device_info_service, location_service, geo_service, avatar_service, storage_photo_service, attribution_service, meta_analytics_service, tiktok_service, app_update_service.\n• admin_service + admin_call_watch_service (admin build only).';

  // ── DEV: Providers ──
  String get docsDevProvidersTitle =>
      isId ? '🗂️ Katalog Provider' : '🗂️ Provider Catalog';
  String get docsDevProvidersBody => isId
      ? 'lib/providers/ — state ChangeNotifier; screen membaca via context.watch/select.\n\n• chat_provider, room_provider, call_provider, online_users_provider.\n• auth_provider, social_provider, timeline_provider, story_provider.\n• points_provider, privacy_provider, message_reaction_provider, notification_prefs_provider.\n• avatar_provider, storage_provider, contact_provider, device_info_provider, location_provider.\n• locale_provider (bahasa), theme_provider, nav_provider, connectivity_provider, update_provider.\n• admin_provider (dipecah providers/admin/*: stats, chats, chat_org, devices, deleted, attribution, notif, passthrough) — hanya di build admin.'
      : 'lib/providers/ — ChangeNotifier state; screens read via context.watch/select.\n\n• chat_provider, room_provider, call_provider, online_users_provider.\n• auth_provider, social_provider, timeline_provider, story_provider.\n• points_provider, privacy_provider, message_reaction_provider, notification_prefs_provider.\n• avatar_provider, storage_provider, contact_provider, device_info_provider, location_provider.\n• locale_provider (language), theme_provider, nav_provider, connectivity_provider, update_provider.\n• admin_provider (split into providers/admin/*: stats, chats, chat_org, devices, deleted, attribution, notif, passthrough) — admin build only.';

  // ── DEV: Ekonomi ──
  String get docsDevEconomyTitle =>
      isId ? '🪙 Mesin Ekonomi Koin' : '🪙 Coin Economy Engine';
  String get docsDevEconomyBody => isId
      ? 'Satu saldo coin_ledger (cache profiles.points); masuk hanya dari topup + welcome bonus + income call.\n\n• charge_metered(): potong + split generik (hanya service_role).\n• call_billing_tick(): tagih call per menit dari calls.answered_at (saldo tak bisa minus).\n• gate_feature(): akses harian (filter gender, nearby).\n• credit_welcome_bonus(): idempoten per install_id + limit IP/hari.\n• credit_play_topup(): hasil verifikasi Play Billing.\n• feature_enabled_for() / admin_set_feature_flag(): publish fitur ke user (sebelum publish hanya admin yang bisa pakai).'
      : 'One balance in coin_ledger (cached as profiles.points); inflow only from top-up + welcome bonus + call income.\n\n• charge_metered(): generic charge + split (service_role only).\n• call_billing_tick(): per-minute call billing from calls.answered_at (never negative).\n• gate_feature(): daily access (gender filter, nearby).\n• credit_welcome_bonus(): idempotent per install_id + IP/day limit.\n• credit_play_topup(): Play Billing verification result.\n• feature_enabled_for() / admin_set_feature_flag(): publish features to users (before publishing, only admins can use them).';

  // ── DEV: Model ──
  String get docsDevModelsTitle =>
      isId ? '🧩 Data Model' : '🧩 Data Models';
  String get docsDevModelsBody => isId
      ? 'lib/models/ — kelas data + (de)serialisasi, tanpa I/O.\n\n• user_model, message_model, room_model, story_model, user_photo, privacy_settings, active_call_model, legal_section.\n• Pola umum: fromMap (Map → objek) / toMap, plus copyWith untuk update parsial (dipakai provider).\n• Kolom sensitif (status, avatar, last_seen, email, ip, user_photos.photo) TIDAK di-select langsung — dibaca lewat RPC ber-privacy (presence_for, avatar_for, get_user_photos_access). Lihat FEATURE_MAP §9.'
      : 'lib/models/ — data classes + (de)serialization, no I/O.\n\n• user_model, message_model, room_model, story_model, user_photo, privacy_settings, active_call_model, legal_section.\n• Common pattern: fromMap (Map → object) / toMap, plus copyWith for partial updates (used by providers).\n• Sensitive columns (status, avatar, last_seen, email, ip, user_photos.photo) are NOT selected directly — read via privacy-aware RPCs (presence_for, avatar_for, get_user_photos_access). See FEATURE_MAP §9.';

  // ── DEV: Error & offline ──
  String get docsDevErrorsTitle =>
      isId ? '🚧 Error Handling & Offline' : '🚧 Error Handling & Offline';
  String get docsDevErrorsBody => isId
      ? 'Panel admin tahan banting saat koneksi buruk.\n\n• lib/core/admin_err.dart: kategori kegagalan (offline/unauthorized/server/unknown) → judul + hint bilingual; detail exception mentah TIDAK ditampilkan ke UI.\n• Data lama tetap tampil saat offline (banner merah tipis), bukan layar error — error penuh hanya saat benar-benar belum ada data.\n• AdminProvider: TTL cache (stats 5 mnt server, detail 60 dtk, storage 10 mnt, excluded 5 mnt); invalidate saat pull-to-refresh force.\n• Notifikasi device baru/call aktif di-arm dulu (seed) sebelum polling → cegah notif palsu saat buka panel.'
      : 'The admin panel is resilient on bad connections.\n\n• lib/core/admin_err.dart: failure categories (offline/unauthorized/server/unknown) → bilingual title + hint; raw exception details are NEVER shown in the UI.\n• Stale data still shows when offline (thin red banner) instead of an error screen — a full error only when there is truly no data yet.\n• AdminProvider: cache TTLs (stats 5 min server-side, detail 60s, storage 10 min, excluded 5 min); invalidated on forced pull-to-refresh.\n• New-device / active-call notifications are armed (seeded) before polling → avoids false alerts when opening the panel.';

  // ── DEV: Testing ──
  String get docsDevTestsTitle =>
      isId ? '✅ Strategi Test' : '✅ Testing Strategy';
  String get docsDevTestsBody => isId
      ? 'Jaring pengaman anti-regresi.\n\n• Flutter: ~155 file test (unit provider/service, widget hermetic, IO via HTTP palsu, regression & functional).\n• SQL: pgTAP di supabase/tests/ (presence, chat notif, privacy, call, outbox, schema_sync anti-regresi tabel/RPC).\n• Deno: supabase/functions/_shared/*.test.ts (helper AI, dll).\n• Gate sebelum commit: flutter analyze 0/0, flutter test 100% hijau, scripts/check_screen_boundary.sh, scripts/check_migrations.sh --all, dan snapshot functions.sql di-review.'
      : 'A regression safety net.\n\n• Flutter: ~155 test files (provider/service units, hermetic widgets, IO via fake HTTP, regression & functional).\n• SQL: pgTAP in supabase/tests/ (presence, chat notif, privacy, call, outbox, schema_sync anti-regression for tables/RPCs).\n• Deno: supabase/functions/_shared/*.test.ts (AI helpers, etc.).\n• Pre-commit gates: flutter analyze 0/0, 100% green flutter test, scripts/check_screen_boundary.sh, scripts/check_migrations.sh --all, and a reviewed functions.sql snapshot.';

  // ── DEV: Admin Panel ──
  String get docsDevAdminPanelTitle =>
      isId ? '🛠️ Admin Panel (modul ini)' : '🛠️ Admin Panel (this module)';
  String get docsDevAdminPanelBody => isId
      ? 'Panel admin hidup DI BUILD TERPISAH (flavor adminProd, appId .admin) dan ter-tree-shake dari APK rilis.\n\n• Entry: lib/main_admin.dart + AdminGate (lib/core/admin_gate.dart) — jembatan netral yang mengisi builder/provider admin; build user tidak pernah menyentuh kode admin.\n• UI: lib/screens/admin_panel_screen.dart (10 tab) + admin_*_tab.dart; provider lib/providers/admin_provider.dart (part-mixin providers/admin/*).\n• RPC admin (SECURITY DEFINER) hanya jalan untuk email admin tunggal (admin_gate.dart adminEmail) — anon/user biasa diblokir server.\n• Tab: Pengaturan Global, Ringkasan, Poin, Monitor Chat, Dummy (AI), Kontak, Perangkat, Terhapus, Atribusi, Dokumentasi.\n• Keamanan: clearAdminCache() menghapus cache PII (email/IP/device) bila HP dipakai bergantian.'
      : 'The admin panel lives in a SEPARATE build (adminProd flavor, .admin appId) and is tree-shaken out of release APKs.\n\n• Entry: lib/main_admin.dart + AdminGate (lib/core/admin_gate.dart) — a neutral bridge wiring admin builders/providers; the user build never touches admin code.\n• UI: lib/screens/admin_panel_screen.dart (10 tabs) + admin_*_tab.dart; provider lib/providers/admin_provider.dart (part-mixin providers/admin/*).\n• Admin RPCs (SECURITY DEFINER) only run for the single admin email (admin_gate.dart adminEmail) — anon/regular users are blocked server-side.\n• Tabs: Global Setting, Overview, Points, Chat Monitor, Dummy (AI), Contact, Devices, Deleted, Attribution, Docs.\n• Security: clearAdminCache() wipes PII cache (email/IP/device) when the phone is shared.';

  // ── DEV: Diagram / flow ──
  String get docsDevDiagramsTitle =>
      isId ? '🗺️ Diagram Alur' : '🗺️ Flow Diagrams';
  String get docsDevDiagramsIntro => isId
      ? 'Sketsa cepat alur data utama. Diagram ini menyederhanakan — detail penuh di docs/ARCHITECTURE.md & docs/FEATURE_MAP.md.'
      : 'Quick sketches of the main data flows. These simplify — full details in docs/ARCHITECTURE.md & docs/FEATURE_MAP.md.';

  // Diagram 1 — layer stack
  String get docsDevLayerDiagramTitle =>
      isId ? 'Lapisan (top → bottom)' : 'Layers (top → bottom)';
  String get docsDevLayerDiagram => isId
      ? '  ┌─────────────── FLUTTER APP (lib/) ───────────────┐\n'
          '  │  screens/     UI (termasuk admin)               │\n'
          '  │      ▼  (context.watch / select)                │\n'
          '  │  providers/   ChangeNotifier + orkestrasi       │\n'
          '  │      ▼  (panggil service)                        │\n'
          '  │  services/    SATU-SATUNYA ke Supabase          │\n'
          '  │      ▼  (RPC / table / realtime)                 │\n'
          '  │  models/      Map ⇄ objek                        │\n'
          '  │  core/        cache · media · perf (tanpa I/O)  │\n'
          '  └───────────────────────┬─────────────────────────┘\n'
          '              PostgREST / Realtime │ WebSocket\n'
          '  ┌───────────────────────▼─────────────────────────┐\n'
          '  │  SUPABASE  Postgres + RLS + RPC + trigger+cron  │\n'
          '  │            Auth · Storage · Realtime            │\n'
          '  │  Edge Fn   outbox-worker · ai-reply · send-push │\n'
          '  └───────────────────────┬─────────────────────────┘\n'
          '              pg_net / FCM Admin SDK\n'
          '                      ▼\n'
          '            Firebase FCM (push)'
      : '  ┌─────────────── FLUTTER APP (lib/) ───────────────┐\n'
          '  │  screens/     UI (incl. admin)                  │\n'
          '  │      ▼  (context.watch / select)                │\n'
          '  │  providers/   ChangeNotifier + orchestration    │\n'
          '  │      ▼  (call service)                          │\n'
          '  │  services/    the ONLY layer to Supabase        │\n'
          '  │      ▼  (RPC / table / realtime)                │\n'
          '  │  models/      Map ⇄ object                      │\n'
          '  │  core/        cache · media · perf (no I/O)     │\n'
          '  └───────────────────────┬─────────────────────────┘\n'
          '              PostgREST / Realtime │ WebSocket\n'
          '  ┌───────────────────────▼─────────────────────────┐\n'
          '  │  SUPABASE  Postgres + RLS + RPC + trigger+cron  │\n'
          '  │            Auth · Storage · Realtime            │\n'
          '  │  Edge Fn   outbox-worker · ai-reply · send-push │\n'
          '  └───────────────────────┬─────────────────────────┘\n'
          '              pg_net / FCM Admin SDK\n'
          '                      ▼\n'
          '            Firebase FCM (push)';

  // Diagram 2 — kirim pesan
  String get docsDevMessageFlowTitle =>
      isId ? 'Alur kirim pesan (chat)' : 'Message send flow (chat)';
  String get docsDevMessageFlow => isId
      ? 'USER ketik di composer\n'
          '   │\n'
          '   ▼\n'
          'ChatProvider.send()  ──► ChatOutboxMixin (antrean offline)\n'
          '   │  online? kirim langsung   │ offline? simpan, kirim saat online\n'
          '   ▼\n'
          'ChatService.insertMessage → INSERT private_messages\n'
          '   │\n'
          '   ├─► TRIGGER notify_private_message → INSERT outbox\n'
          '   ├─► TRIGGER ai_reply_enqueue (kalau lawan = dummy) → Edge ai-reply\n'
          '   └─► TRIGGER handle_new_private_message → potong poin (charge)\n'
          '   │\n'
          '   ▼\n'
          'Realtime channel msg-<chatId> → INSERT di-append ke UI (0 round-trip)\n'
          '   │\n'
          '   ▼\n'
          'MessageCache (SQLite terenkripsi) ← tersimpan lokal untuk offline\n\n'
          'Lawan online → push lewat cron chatyuk-outbox-worker (*/1m) → Edge send-push'
      : 'USER types in composer\n'
          '   │\n'
          '   ▼\n'
          'ChatProvider.send()  ──► ChatOutboxMixin (offline queue)\n'
          '   │  online? send now         │ offline? store, send when online\n'
          '   ▼\n'
          'ChatService.insertMessage → INSERT private_messages\n'
          '   │\n'
          '   ├─► TRIGGER notify_private_message → INSERT outbox\n'
          '   ├─► TRIGGER ai_reply_enqueue (if peer = dummy) → Edge ai-reply\n'
          '   └─► TRIGGER handle_new_private_message → charge coins\n'
          '   │\n'
          '   ▼\n'
          'Realtime channel msg-<chatId> → INSERT appended to UI (0 round-trip)\n'
          '   │\n'
          '   ▼\n'
          'MessageCache (encrypted SQLite) ← stored locally for offline\n\n'
          'Peer online → push via cron chatyuk-outbox-worker (*/1m) → Edge send-push';

  // Diagram 3 — notifikasi outbox
  String get docsDevNotifFlowTitle =>
      isId ? 'Alur notifikasi (outbox, anti-blok)' : 'Notification flow (outbox, non-blocking)';
  String get docsDevNotifFlow => isId
      ? 'EVENT (pesan baru / mention / call / follow…)\n'
          '   │\n'
          '   ▼\n'
          'TRIGGER tulis ke tabel `outbox`   ◄── transaksi TIDAK menunggu HTTP\n'
          '   │\n'
          '   ▼\n'
          'cron chatyuk-outbox-worker (*/1m)\n'
          '   │\n'
          '   ▼\n'
          'Edge outbox-worker → ambil token dari user_devices.fcm_token\n'
          '   │               (helper user_fcm_tokens: devices aktif + fallback)\n'
          '   ▼\n'
          'Edge send-push → Firebase FCM → HP user\n\n'
          'KALAU worker/cron MATI → notif tidak terkirim (pesan tetap aman, bukan data loss).'
      : 'EVENT (new message / mention / call / follow…)\n'
          '   │\n'
          '   ▼\n'
          'TRIGGER writes to `outbox` table   ◄── tx does NOT wait on HTTP\n'
          '   │\n'
          '   ▼\n'
          'cron chatyuk-outbox-worker (*/1m)\n'
          '   │\n'
          '   ▼\n'
          'Edge outbox-worker → token from user_devices.fcm_token\n'
          '   │               (helper user_fcm_tokens: active devices + fallback)\n'
          '   ▼\n'
          'Edge send-push → Firebase FCM → user device\n\n'
          'IF worker/cron is DOWN → notifications are not sent (messages stay safe, no data loss).';

  // Diagram 4 — call / WebRTC
  String get docsDevCallFlowTitle =>
      isId ? 'Alur call (WebRTC)' : 'Call flow (WebRTC)';
  String get docsDevCallFlow => isId
      ? 'PENELEPON                        PENERIMA\n'
          '   │                                │\n'
          '   │  calls INSERT (status=ringing) │\n'
          '   ├───────────────────────────────►│\n'
          '   │        TRIGGER call_push       │  notif panggilan masuk\n'
          '   │                                │\n'
          '   │        Edge turn-credentials   │  kredensial TURN (NAT traversal)\n'
          '   │◄──────────────────────────────►│\n'
          '   │      signaling (call_signals)  │  SDP offer/answer + ICE\n'
          '   │◄──────────────────────────────►│\n'
          '   │          WebRTC media (P2P)    │  audio / video langsung\n'
          '   │◄──────────────────────────────►│\n'
          '   │                                │\n'
          '   ▼  call_billing_tick()           │  tagih YukCoin per menit (dari answered_at)\n'
          '   │  cron chatyuk-call-sweep (*/5m)│  akhiri call zombie + retensi signals\n'
          '   ▼                                ▼\n'
          '  notify_call_ended → missed call 1× (lewat outbox)'
      : 'CALLER                           CALLEE\n'
          '   │                                │\n'
          '   │  calls INSERT (status=ringing) │\n'
          '   ├───────────────────────────────►│\n'
          '   │        TRIGGER call_push       │  incoming call notif\n'
          '   │                                │\n'
          '   │        Edge turn-credentials   │  TURN creds (NAT traversal)\n'
          '   │◄──────────────────────────────►│\n'
          '   │      signaling (call_signals)  │  SDP offer/answer + ICE\n'
          '   │◄──────────────────────────────►│\n'
          '   │          WebRTC media (P2P)    │  direct audio / video\n'
          '   │◄──────────────────────────────►│\n'
          '   │                                │\n'
          '   ▼  call_billing_tick()           │  bill YukCoin per minute (from answered_at)\n'
          '   │  cron chatyuk-call-sweep (*/5m)│  end zombie calls + signals retention\n'
          '   ▼                                ▼\n'
          '  notify_call_ended → missed call 1× (via outbox)';

  // Diagram 5 — ekonomi koin
  String get docsDevCoinFlowTitle =>
      isId ? 'Alur ekonomi koin (masuk → keluar)' : 'Coin economy flow (inflow → outflow)';
  String get docsDevCoinFlow => isId
      ? '        MASUK (inflow)                       KELUAR (outflow)\n'
          '   ┌──────────────────────┐        ┌──────────────────────────┐\n'
          '   │ Play Billing topup   │        │ call (audio 6/video 20)  │\n'
          '   │  → play-topup-verify │        │  → call_billing_tick     │\n'
          '   │  → credit_play_topup │        │ filter gender / nearby   │\n'
          '   │ welcome bonus (baru) │        │  → gate_feature          │\n'
          '   │  → credit_welcome_*  │        │ undo / edit / ghost /slot│\n'
          '   │ income call (ditelepon)│      │ buka foto / room / gift  │\n'
          '   └──────────┬───────────┘        │  → charge_metered (split)│\n'
          '              │                     └────────────┬─────────────┘\n'
          '              ▼                                  ▼\n'
          '        ┌────────────────────────────────────────────┐\n'
          '        │   coin_ledger  (sumber kebenaran / audit)   │\n'
          '        │   cache: profiles.points (akses cepat)      │\n'
          '        └────────────────────────────────────────────┘\n\n'
          'charge_metered hanya `service_role` — user tak bisa mendebit orang lain.\n'
          'Saldo tak bisa minus (afford-guard di server).'
      : '        INFLOW                               OUTFLOW\n'
          '   ┌──────────────────────┐        ┌──────────────────────────┐\n'
          '   │ Play Billing top-up  │        │ call (audio 6/video 20)  │\n'
          '   │  → play-topup-verify │        │  → call_billing_tick     │\n'
          '   │  → credit_play_topup │        │ gender filter / nearby   │\n'
          '   │ welcome bonus (new)  │        │  → gate_feature          │\n'
          '   │  → credit_welcome_*  │        │ undo / edit / ghost/slot │\n'
          '   │ call income (callee) │        │ photo unlock / room / gift│\n'
          '   └──────────┬───────────┘        │  → charge_metered (split)│\n'
          '              │                     └────────────┬─────────────┘\n'
          '              ▼                                  ▼\n'
          '        ┌────────────────────────────────────────────┐\n'
          '        │   coin_ledger  (source of truth / audit)    │\n'
          '        │   cache: profiles.points (fast access)      │\n'
          '        └────────────────────────────────────────────┘\n\n'
          'charge_metered is `service_role` only — users cannot debit others.\n'
          'Balance can never go negative (server-side afford-guard).';

  String get docsDevDiagramNoWrap =>
      isId ? 'Geser ke samping untuk diagram →' : 'Scroll sideways for diagrams →';

  // ── DEV: Build ──
  String get docsDevBuildTitle =>
      isId ? '🏗️ Build & Konvensi' : '🏗️ Build & Conventions';
  String get docsDevBuildBody => isId
      ? 'Flavor (store × env): apkpure (HP/APKPure), play (Play Store + topup Billing), admin (internal, appId .admin — DILARANG upload store). Build wajib --flavor + obfuscate + keystore v2 (kalau tidak, Google Sign-In 12500).\n\n• Wajib bilingual: semua string UI via s.* (config/strings*.dart).\n• Tipografi: hanya token AppText/AppGlyph — dilarang fontSize: angka mentah.\n• ChatService & AdminProvider: tambah method di mixin domain, jangan di file monolit.\n• Cek wajib: flutter analyze (0/0), flutter test hijau, scripts/check_screen_boundary.sh OK, scripts/check_migrations.sh --all OK.'
      : 'Flavors (store × env): apkpure (phone/APKPure), play (Play Store + Billing top-up), admin (internal, .admin appId — NEVER upload to stores). Builds require --flavor + obfuscate + v2 keystore (otherwise Google Sign-In 12500).\n\n• Bilingual mandatory: every UI string via s.* (config/strings*.dart).\n• Typography: AppText/AppGlyph tokens only — no raw fontSize: numbers.\n• ChatService & AdminProvider: add methods in the domain mixin, never the monolith.\n• Required gates: flutter analyze (0/0), green flutter test, scripts/check_screen_boundary.sh OK, scripts/check_migrations.sh --all OK.';
}
