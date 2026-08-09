// CLI forensik untuk foto view-once yang bocor.
//
// Cara pakai:
//   dart run tool/extract_watermark.dart --input <foto_bocor.jpg> --seeds <uid.txt>
//
// Opsi:
//   --input <path>    Wajib. Gambar bocor (hasil recapture/crop layar).
//   --seeds <path>    File berisi kandidat UID, satu per baris.
//   --uid <uid>       Tambah satu kandidat UID (bisa diulang).
//   --fetch-users     Ambil daftar UID dari Supabase (butuh SUPABASE_KEY / pakai anon).
//   --json            Output JSON untuk diparse.
//
// Kandidat seed = UID penerima. Hanya penerima yang bisa melihat foto view-once,
// jadi korrelasi tertinggi menunjuk ke akun yang membocorkan foto.
import 'dart:convert';
import 'dart:io';

import 'package:chatyuk/services/forensic_watermark.dart';

Future<List<String>> fetchProfileUids() async {
  const url = 'https://fohcucyyejdryryoxitm.supabase.co';
  const table = 'profiles';
  final key = Platform.environment['SUPABASE_KEY'] ??
      'sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg';
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client
        .getUrl(Uri.parse('$url/rest/v1/$table?select=id&limit=1000'));
    req.headers
      ..set('apikey', key)
      ..set('Authorization', 'Bearer $key');
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('Gagal fetch users: HTTP ${res.statusCode}');
      return const [];
    }
    final body = await res.transform(utf8.decoder).join();
    final rows = jsonDecode(body) as List;
    return rows.map((r) => (r as Map)['id'].toString()).toList();
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  String? inputPath;
  String? seedsPath;
  final extraUids = <String>[];
  var fetchUsers = false;
  var asJson = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        inputPath = args[++i];
      case '--seeds':
        seedsPath = args[++i];
      case '--uid':
        extraUids.add(args[++i]);
      case '--fetch-users':
        fetchUsers = true;
      case '--json':
        asJson = true;
      default:
        stderr.writeln('Argumen tidak dikenal: ${args[i]}');
        exit(2);
    }
  }

  if (inputPath == null) {
    stderr.writeln('Gunakan: dart run tool/extract_watermark.dart --input <file> '
        '[--seeds <file>] [--uid <uid>...] [--fetch-users] [--json]');
    exit(2);
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('File tidak ditemukan: $inputPath');
    exit(1);
  }

  final candidates = <String>{...extraUids};
  if (seedsPath != null) {
    final f = File(seedsPath);
    if (f.existsSync()) {
      for (final line in f.readAsLinesSync()) {
        final t = line.trim();
        if (t.isNotEmpty) candidates.add(t);
      }
    } else {
      stderr.writeln('File seeds tidak ditemukan: $seedsPath');
    }
  }
  if (fetchUsers) {
    final uids = await fetchProfileUids();
    candidates.addAll(uids);
    if (uids.isEmpty) {
      stderr.writeln('Tidak ada UID dari --fetch-users '
          '(RLS mungkin membatasi; beri --seeds atau SUPABASE_KEY service role).');
    }
  }

  if (candidates.isEmpty) {
    stderr.writeln('Tidak ada kandidat seed. Berikan --seeds, --uid, atau --fetch-users.');
    exit(1);
  }

  final bytes = inputFile.readAsBytesSync();
  final results = ForensicWatermark.detect(bytes, candidates.toList());

  if (asJson) {
    stdout.writeln(jsonEncode(results
        .map((r) =>
            {'seed': r.seed, 'rho': r.rho, 'z': r.z, 'matched': r.matched})
        .toList()));
    exit(0);
  }

  stdout.writeln('Input : $inputPath');
  stdout.writeln('Hasil (korelasi, threshold z ${ForensicWatermark.threshold}):');
  stdout.writeln('-' * 48);
  for (final r in results.take(10)) {
    final mark = r.matched ? ' <== MATCH' : '';
    stdout.writeln(
        '${r.seed}  rho=${r.rho.toStringAsFixed(4)}  z=${r.z.toStringAsFixed(2)}$mark');
  }
}
