import 'dart:convert';

/// Definisi poll (disimpan di kolom `private_messages.poll`):
/// `{"q": pertanyaan, "o": [opsi...], "m": boleh banyak pilihan}`.
class ChatPoll {
  final String question;
  final List<String> options;
  final bool multi;

  static const int minOptions = 2;
  static const int maxOptions = 12;
  static const int maxQuestionLen = 255;
  static const int maxOptionLen = 100;

  const ChatPoll({
    required this.question,
    required this.options,
    this.multi = false,
  });

  /// Toleran: Map (realtime/PostgREST/cache) atau string JSON. null bila
  /// tidak valid (bubble jatuh ke teks biasa).
  static ChatPoll? tryParse(dynamic raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is! Map) return null;
      final q = '${m['q'] ?? ''}'.trim();
      final o = (m['o'] is List)
          ? (m['o'] as List).map((e) => '$e').toList()
          : const <String>[];
      if (q.isEmpty || o.length < minOptions) return null;
      return ChatPoll(question: q, options: o, multi: m['m'] == true);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {'q': question, 'o': options, 'm': multi};

  /// Teks pesan untuk notif / daftar chat / balasan.
  String get previewText => '📊 $question';
}

/// Hasil poll (dari RPC get_poll_results / vote_poll).
class PollResult {
  final List<int> counts;
  final Set<int> mine;
  final int voters;
  const PollResult({
    required this.counts,
    required this.mine,
    required this.voters,
  });

  static PollResult empty(int n) =>
      PollResult(counts: List.filled(n, 0), mine: const {}, voters: 0);

  static PollResult? tryParse(dynamic r) {
    if (r is! Map) return null;
    final c = r['counts'];
    final mi = r['mine'];
    return PollResult(
      counts: c is List ? c.map((e) => (e as num).toInt()).toList() : const [],
      mine: mi is List ? mi.map((e) => (e as num).toInt()).toSet() : const {},
      voters: (r['voters'] as num?)?.toInt() ?? 0,
    );
  }

  int get maxCount => counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);
}
