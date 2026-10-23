import '../../models/message_model.dart';

/// Gabungkan pesan server [msgs] (urut naik waktu) dengan bubble lokal
/// [pending] supaya tampil BERURUTAN WAKTU.
///
/// Kasus normal: semua pending lebih baru dari pesan terakhir → cukup
/// ditempel di akhir (tanpa sort, O(n)). Bubble BLOKIR dari sesi lalu bisa
/// lebih TUA dari pesan lawan yang masuk belakangan → disisipkan sesuai
/// waktunya (bukan selalu di paling bawah).
List<MessageModel> mergePendingChrono(
  List<MessageModel> msgs,
  List<MessageModel> pending,
) {
  if (pending.isEmpty) return msgs;
  if (msgs.isEmpty) return [...pending];
  final last = msgs.last.timestamp;
  if (pending.every((p) => !p.timestamp.isBefore(last))) {
    return [...msgs, ...pending];
  }
  final out = <MessageModel>[];
  final sortedPending = [...pending]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  var i = 0;
  for (final m in msgs) {
    while (i < sortedPending.length &&
        sortedPending[i].timestamp.isBefore(m.timestamp)) {
      out.add(sortedPending[i++]);
    }
    out.add(m);
  }
  while (i < sortedPending.length) {
    out.add(sortedPending[i++]);
  }
  return out;
}
