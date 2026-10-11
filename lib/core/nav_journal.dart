/// Jurnal navigasi PERSISTEN untuk diagnosa berulang "back mati / blank".
///
/// Masalah yang dipecahkan: logcat HyperOS memblokir stdout app sehingga
/// `debugPrint` ([RouteTracker], handler back) TAK terlihat di HP user.
/// Tanpa jejak, tiap laporan "blank" harus ditebak ulang dari nol.
///
/// Jurnal ini mencatat setiap push/pop/replace/back ke file app-private
/// (`nav_journal.txt`, CAP 200KB, nama rute DIREDact dari id) — bisa ditarik
/// BERULANG kali tanpa interaksi user:
///   adb shell run-as com.chatyuk.chatyuk cat app_flutter/nav_journal.txt
/// (butuh build debuggable = `--profile`; di release run-as ditolak).
///
/// Semua tulis fire-and-forget: tak pernah memblokir UI/back handler.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class NavJournal {
  NavJournal._();

  static const _fileName = 'nav_journal.txt';
  static const _maxFileBytes = 200 * 1024;
  static const _ringCap = 300;

  static final List<String> _ring = [];
  static int _writesSinceSizeCheck = 0;
  static Future<Directory>? _dirFuture;
  static Directory? _testDir;

  /// Hook unit test: arahkan tulis file ke direktori sementara.
  @visibleForTesting
  static void testSetDir(Directory d) => _testDir = d;

  /// Isi ring buffer (baca-saja, untuk test).
  @visibleForTesting
  static List<String> get ringForTest => List.unmodifiable(_ring);
  /// Samarkan id sensitif dari nama rute:
  /// 'private-chat:abc123' → 'private-chat'. Id chat/uid user JANGAN
  /// bocor ke file (walau app-private, prinsipnya minimal).
  @visibleForTesting
  static String redact(String s) => s.replaceAllMapped(
        RegExp(r'(private-chat|room|user|chat):[^,\]\s]+'),
        (m) => '${m[1]}',
      );

  /// Catat satu event navigasi. Tak pernah melempar.
  static void log(String event) {
    try {
      final line = '${DateTime.now().toIso8601String()} ${redact(event)}';
      _ring.add(line);
      while (_ring.length > _ringCap) {
        _ring.removeAt(0);
      }
      _appendFile(line);
    } catch (_) {}
  }

  static void _appendFile(String line) {
    () async {
      try {
        // Jangan sentuh MethodChannel bila direktori test di-set (unit test
        // tanpa binding) — probe channel hanya di runtime sungguhan.
        if (_testDir == null) {
          _dirFuture ??= getApplicationDocumentsDirectory();
        }
        final dir = _testDir ?? await _dirFuture!;
        final f = File('${dir.path}/$_fileName');
        if (_writesSinceSizeCheck >= 20) {
          _writesSinceSizeCheck = 0;
          try {
            if (await f.exists() && await f.length() > _maxFileBytes) {
              await f.writeAsString('', mode: FileMode.write);
            }
          } catch (_) {}
        }
        _writesSinceSizeCheck++;
        await f.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {}
    }();
  }
}

/// Penjaga veto back anti "mati permanen" SEKALIGUS anti "salah keluar".
///
/// Konteks (insiden 2026-10-11, terbukti via NavJournal): antara evaluasi
/// `canPop` dan callback `onPopInvoked`, state bisa dibersihkan konkuren
/// (mis. rebuild stream memanggil clear) → veto BASI (tak ada yang menahan).
/// Force-pop saat veto basi SALAH: niat user (batal seleksi) sudah terpenuhi,
/// pop malah mengeluarkan app sampai launcher.
///
/// Aturan:
/// - Veto basi (tak ada yang menahan SAAT callback) → NO-OP, kecuali basi
///   yang SAMA berulang ≥2x (signature identik = state macet beneran) →
///   escape sekali.
/// - Handler melempar + route masih mounted & masih tertahan → escape sekali.
/// - Escape = flag `_backEscape` (PopScope juga mem-veto pop programatik!)
///   + [safePop] (mounted-check + try/catch: pop di context mati melempar
///   dan merusak dispatcher).
class BackVetoGuard {
  String _lastSig = '';
  int _repeat = 0;

  /// Veto basi dengan [sig] ini boleh escape? True hanya bila [sig] yang
  /// SAMA sudah terlihat ≥2x berturut (bukan perubahan konkuren).
  bool shouldEscape(String sig) {
    if (sig == _lastSig) {
      _repeat++;
    } else {
      _lastSig = sig;
      _repeat = 1;
    }
    return _repeat >= 2;
  }

  /// Panggil tiap veto ASLI (masih ada yang menahan) & tiap pop sukses —
  /// penghitung pengulangan mulai dari nol lagi.
  void reset() {
    _lastSig = '';
    _repeat = 0;
  }

  /// Pop yang tak pernah melempar (context mati / navigator rusak).
  static void safePop(BuildContext context) {
    try {
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {}
  }
}
