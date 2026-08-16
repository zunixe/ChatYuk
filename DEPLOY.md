# Deploy Checklist — Ekonomi Koin + Sosial ChatYuk

Perubahan: dual pricing (bonus vs paid), fix keamanan koin, ramping faucet,
follow/friend/subscribe, dan referral install.

## 1. Deploy migration Supabase

```bash
supabase db push
```

File yang diterapkan (berurutan):

| File | Isi |
|---|---|
| `supabase/migrations/20260816030000_coin_economy_v2.sql` | dual pricing, fix S0/S1/S2, ramping bonus, referral install, `bind_referrer` |
| `supabase/migrations/20260816040000_social_graph.sql` | `follows`, `friend_requests`, `subscriptions`, counter trigger, push notif |

## 2. Deploy edge function

```bash
supabase functions deploy r --no-verify-jwt
supabase functions deploy send-push --no-verify-jwt
```

## 3. Verifikasi RPC di dashboard (SQL Editor)

Pastikan fungsi-fungsi berikut ada (jalankan satu per satu, tidak boleh error):

```sql
select public.ledger_spend_paid(auth.uid(), 'test', 0);
select public.ledger_spend_dual(auth.uid(), 'test', 0, 0);
select public.room_pricing();
select public.follow_user(null);
select public.bind_referrer(null);
```

Cek tabel & kolom:

```sql
select column_name from information_schema.columns
where table_name = 'profiles'
  and column_name in ('followers_count','following_count','subscriber_count','subscription_price','referred_by');

select tablename from pg_tables
where schemaname = 'public'
  and tablename in ('follows','friend_requests','subscriptions','referral_rewards');
```

## 4. Test manual di HP

- [ ] Chat teks tetap bisa pakai koin bonus (1 koin).
- [ ] Buat room private: tampil "Koin belian X · atau bonus 3X", potong otomatis.
- [ ] Kirim koin: hanya pakai saldo belian (bonus tidak terpotong).
- [ ] Gift: akun anon ditolak; registered bisa, tier paid → cut 30%, bonus → tanpa cut.
- [ ] Follow/unfollow muncul di profil orang & angka berubah.
- [ ] Friend request → accept → otomatis saling follow (jadi teman).
- [ ] Subscribe creator: hanya koin belian, creator dapat earned, platform cut 30%.
- [ ] Referral install: klik link share → deep link → register → referrer dapat bonus.
- [ ] Notifikasi follow/friend request muncul bilingual.

## 5. Catatan keamanan

- **Jangan pernah** simpan `SERVICE_ROLE_KEY` di app. Hanya `publishableKey`
  (`lib/config/supabase_config.dart`).
- Bonus hanya bisa jadi `bonus` (tidak bisa dicairkan). Hanya `earned` yang
  bisa withdraw (KYC). Spread beli Rp11 vs cair Rp7 + cut 30% = margin ~55%.
