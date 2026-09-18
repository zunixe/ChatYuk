// Kontrak Edge ↔ DB ↔ App — sumber kebenaran tunggal untuk test.
// Kalau mengubah send-push / fanout / wallet, update file ini + test.
// Sengaja TIDAK import index.ts (Deno.serve side-effect) — test membaca
// teks index.ts dan memastikan token kontrak tetap sinkron.

/// Tipe data-only send-push: teks dirender client (bilingual), tanpa blok
/// notification FCM. Cermin `dataOnlyTypes` di send-push/index.ts.
export const SEND_PUSH_DATA_ONLY_TYPES = [
  'online',
  'follow',
  'friend_request',
  'subscribe',
  'call',
  'call_ended',
  'call_canceled',
  'message',
  'broadcast',
] as const;

/// Tipe fanout yang didukung + pola topic. Cermin fanout/index.ts.
export const FANOUT_TYPES = ['online', 'timeline', 'room'] as const;

export function fanoutTopic(type: string, id: string): string {
  if (type === 'online') return `online-${id}`;
  if (type === 'timeline') return 'timeline-all';
  return `room-${id}`;
}

/// Kunci wallet get_wallet yang dipakai PointsProvider (points_service.dart).
export const WALLET_KEYS = ['bonus', 'earned', 'total'] as const;

/// Kolom yang wajib ada supaya fitur tidak regresi (cermin schema_sync_test.sql).
export const REQUIRED_PRIVATE_MESSAGE_COLS = ['is_forwarded'] as const;
