import 'dart:math';
import 'dart:typed_data';

import 'package:chatyuk/core/kyc/image_quality.dart';
import 'package:chatyuk/core/kyc/kyc_capture.dart';
import 'package:chatyuk/core/kyc/kyc_form_check.dart';
import 'package:chatyuk/core/kyc/liveness.dart';
import 'package:chatyuk/core/kyc/ktp_ocr.dart';
import 'package:chatyuk/core/kyc/nik.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4);

  group('Nik.parse', () {
    test('NIK perempuan valid → tgl lahir & gender', () {
      // 32 Jabar, 73 Bandung, 05 kec, 45 → tgl 5 (perempuan), 08, 98
      final i = Nik.parse('3273054508980001', now: now)!;
      expect(i.female, isTrue);
      expect(i.birthDate, DateTime(1998, 8, 5));
      expect(i.provinceCode, 32);
    });

    test('NIK laki-laki tahun 2000-an', () {
      final i = Nik.parse('3171021203050002', now: now)!;
      expect(i.female, isFalse);
      expect(i.birthDate, DateTime(2005, 3, 12));
    });

    test('struktur salah ditolak', () {
      expect(Nik.parse('1234567890123456', now: now), isNull); // prov 12 ok tapi tgl 78
      expect(Nik.parse('9973054508980001', now: now), isNull); // prov 99
      expect(Nik.parse('3200054508980001', now: now), isNull); // kab 00
      expect(Nik.parse('3273054508980000', now: now), isNull); // urut 0000
      expect(Nik.parse('3273057102980001', now: now), isNull); // 31 Feb (71-40)
      expect(Nik.parse('327305450898000', now: now), isNull); // 15 digit
      expect(Nik.parse('3273051513980001', now: now), isNull); // bulan 13
    });

    test('normalize koreksi huruf mirip angka', () {
      expect(Nik.normalize('3273O54S0898OOO1'), '3273054508980001');
      expect(Nik.normalize('32 73 05 45 08 98 0001'), '3273054508980001');
    });

    test('ageOn', () {
      expect(Nik.ageOn(DateTime(2008, 11, 5), now), 17);
      expect(Nik.ageOn(DateTime(2008, 11, 4), now), 18);
    });
  });

  group('KtpOcr.parse', () {
    test('layout satu baris "label : nilai"', () {
      final r = KtpOcr.parse([
        'PROVINSI JAWA BARAT',
        'KOTA BANDUNG',
        'NIK : 3273054508980001',
        'Nama : SITI AMINAH',
        'Tempat/Tgl Lahir : BANDUNG, 05-08-1998',
        'Jenis Kelamin : PEREMPUAN Gol. Darah : O',
        'Alamat : JL. MAWAR NO 1',
        'Agama : ISLAM',
        'Berlaku Hingga : SEUMUR HIDUP',
        'BANDUNG 12-01-2015',
      ], now: now);
      expect(r.nik, '3273054508980001');
      expect(r.name, 'SITI AMINAH');
      expect(r.birthDate, DateTime(1998, 8, 5));
      expect(r.female, isTrue);
      expect(r.looksLikeKtp, isTrue);
    });

    test('kolom label & nilai terpisah + NIK salah baca huruf', () {
      final r = KtpOcr.parse([
        'PROVINSI DKI JAKARTA',
        'JAKARTA PUSAT',
        'NIK',
        '3171O2I2O3O50002',
        'Nama',
        'BUDI SANTOSO',
        'Tempat/Tgl Lahir',
        'JAKARTA, 12-03-2005',
        'Jenis kelamin LAKI-LAKI',
        'Alamat',
      ], now: now);
      expect(r.nik, '3171021203050002');
      expect(r.name, 'BUDI SANTOSO');
      expect(r.birthDate, DateTime(2005, 3, 12));
      expect(r.female, isFalse);
    });

    test('bukan KTP (teks acak) → tidak lolos', () {
      final r = KtpOcr.parse(['STRUK BELANJA', 'TOTAL 50.000'], now: now);
      expect(r.looksLikeKtp, isFalse);
      expect(r.nik, isNull);
    });
  });

  group('nameSimilarity', () {
    test('sama / beda kapital & spasi', () {
      expect(nameSimilarity('Siti  Aminah', 'SITI AMINAH'), 1);
    });
    test('salah baca 1 huruf masih tinggi', () {
      expect(nameSimilarity('SITI AMINAH', 'SlTI AMINAH'), greaterThan(0.8));
    });
    test('nama lain rendah', () {
      expect(nameSimilarity('BUDI SANTOSO', 'SITI AMINAH'), lessThan(0.5));
    });
  });

  group('FrameQuality', () {
    Uint8List plane(int w, int h, int Function(int x, int y) f) {
      final b = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          b[y * w + x] = f(x, y);
        }
      }
      return b;
    }

    test('pola tajam lolos, rata (blur) gagal', () {
      final sharp = plane(120, 80, (x, y) => ((x ~/ 2 + y ~/ 2) % 2) * 200 + 30);
      final flat = plane(120, 80, (x, y) => 128);
      expect(FrameQuality.fromLuma(sharp, 120, 80, 120).sharp, isTrue);
      expect(FrameQuality.fromLuma(flat, 120, 80, 120).sharp, isFalse);
    });

    test('silau & gelap terdeteksi', () {
      final glare = plane(120, 80, (x, y) => 255);
      final dark = plane(120, 80, (x, y) => 10);
      expect(FrameQuality.fromLuma(glare, 120, 80, 120).glare, isTrue);
      expect(FrameQuality.fromLuma(dark, 120, 80, 120).dark, isTrue);
    });
  });

  group('LivenessTracker', () {
    FaceSample face({double yaw = 0, double eyes = 0.9, int id = 7}) =>
        FaceSample(count: 1, trackingId: id, yaw: yaw, leftEye: eyes, rightEye: eyes);

    void doBlink(LivenessTracker t) {
      t.feed(face(eyes: 0.9));
      t.feed(face(eyes: 0.1));
      t.feed(face(eyes: 0.9));
    }

    void doTurn(LivenessTracker t) {
      t.feed(face(yaw: 25));
      t.feed(face(yaw: -25));
    }

    LivenessTracker positioned() {
      final t = LivenessTracker(random: Random(1));
      for (var i = 0; i < 3; i++) {
        t.feed(face());
      }
      expect(t.phase, LivenessPhase.challenge);
      return t;
    }

    test('alur lengkap → done', () {
      final t = positioned();
      for (final c in List.of(t.challenges)) {
        c == LivenessChallenge.blink ? doBlink(t) : doTurn(t);
      }
      expect(t.phase, LivenessPhase.straight);
      t.feed(face());
      t.feed(face());
      expect(t.phase, LivenessPhase.done);
      expect(t.completed.toSet(), {'blink', 'turn'});
    });

    test('toleh satu sisi saja tidak cukup', () {
      final t = positioned();
      if (t.current == LivenessChallenge.blink) doBlink(t);
      t.feed(face(yaw: 30));
      t.feed(face(yaw: 28));
      expect(t.current, LivenessChallenge.turn);
    });

    test('wajah berganti (tracking id) → ulang dari awal', () {
      final t = positioned();
      t.feed(face(id: 99));
      expect(t.phase, LivenessPhase.position);
      expect(t.restarted, isTrue);
    });

    test('dua wajah → multiple', () {
      final t = LivenessTracker();
      expect(t.feed(const FaceSample(count: 2)), LivenessPhase.multiple);
    });
  });

  group('KycFormCheck', () {
    const doc = KycDocCapture(
      path: 'x',
      ocr: KtpOcrResult(
        nik: '3273054508980001',
        name: 'SITI AMINAH',
        birthDate: null,
        keywordHits: 6,
      ),
    );
    const selfie = KycSelfieCapture(path: 'y', live: true);

    KycFormCheck eval({
      String nik = '3273054508980001',
      String name = 'Siti Aminah',
      DateTime? birth,
      String gender = 'female',
      KycDocCapture? d = doc,
    }) =>
        KycFormCheck.evaluate(
          nik: nik,
          name: name,
          birth: birth ?? DateTime(1998, 8, 5),
          doc: d,
          selfie: selfie,
          profileGender: gender,
          now: now,
        );

    test('data cocok → tanpa error & warning', () {
      final c = eval();
      expect(c.error, isNull);
      expect(c.warnings, isEmpty);
      expect(c.checks['live'], isTrue);
      expect(c.checks['nik_match_ocr'], isTrue);
    });

    test('tgl lahir beda dengan NIK → birthMismatch', () {
      expect(eval(birth: DateTime(1998, 8, 6)).error, KycFormError.birthMismatch);
    });

    test('NIK diubah dari hasil KTP → warning nikMismatch', () {
      final c = eval(nik: '3273054508980002');
      expect(c.warnings, contains(KycFormWarning.nikMismatch));
    });

    test('nama beda & gender profil beda → warning', () {
      final c = eval(name: 'Budi Santoso', gender: 'male');
      expect(c.warnings, containsAll([
        KycFormWarning.nameMismatch,
        KycFormWarning.genderMismatch,
      ]));
    });

    test('foto belum lengkap → photos', () {
      expect(eval(d: null).error, KycFormError.photos);
    });
  });
}
