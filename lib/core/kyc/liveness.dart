import 'dart:math';

/// Satu sampel wajah dari deteksi ML Kit (sudah diringkas, murni → dites).
class FaceSample {
  /// Jumlah wajah di frame.
  final int count;
  final int? trackingId;

  /// Rotasi kepala kiri/kanan (Y) & atas/bawah (X), derajat.
  final double yaw;
  final double pitch;

  /// Probabilitas mata terbuka 0..1 (null = tak tersedia).
  final double? leftEye;
  final double? rightEye;

  /// Wajah cukup besar & di tengah (dalam oval).
  final bool framed;

  const FaceSample({
    required this.count,
    this.trackingId,
    this.yaw = 0,
    this.pitch = 0,
    this.leftEye,
    this.rightEye,
    this.framed = true,
  });

  static const none = FaceSample(count: 0);

  double? get eyes => leftEye == null || rightEye == null
      ? null
      : (leftEye! + rightEye!) / 2;
}

enum LivenessChallenge { blink, turn }

enum LivenessPhase {
  /// Menunggu satu wajah lurus di oval.
  position,
  multiple,
  challenge,

  /// Semua tantangan lolos — hadap lurus untuk dipotret.
  straight,
  done,
}

/// State machine liveness: wajah di oval → tantangan acak (kedip & toleh
/// kiri-kanan) → hadap lurus → jepret. Wajah hilang terlalu lama atau
/// tracking id berganti (wajah/foto ditukar) → mulai ulang.
class LivenessTracker {
  LivenessTracker({Random? random})
      : challenges = [LivenessChallenge.blink, LivenessChallenge.turn]
          ..shuffle(random ?? Random());

  final List<LivenessChallenge> challenges;
  LivenessPhase phase = LivenessPhase.position;
  int index = 0;
  final List<String> completed = [];

  /// true sekali saat tracker baru saja di-reset (UI menampilkan pesan).
  bool restarted = false;

  int? _trackId;
  int _missing = 0;
  int _positionedFrames = 0;
  int _straightFrames = 0;

  // Kedip: terbuka → tertutup → terbuka.
  bool _sawOpen = false;
  bool _sawClosed = false;

  // Toleh: harus melewati kedua sisi.
  bool _sawLeft = false;
  bool _sawRight = false;

  static const _turnDeg = 20.0;
  static const _straightDeg = 10.0;
  static const _maxMissing = 6;

  LivenessChallenge? get current =>
      phase == LivenessPhase.challenge ? challenges[index] : null;

  /// 0..1 untuk busur progres.
  double get progress => switch (phase) {
        LivenessPhase.position || LivenessPhase.multiple => 0,
        LivenessPhase.challenge => (index + 1) / (challenges.length + 2),
        LivenessPhase.straight => (challenges.length + 1) / (challenges.length + 2),
        LivenessPhase.done => 1,
      };

  int get step => switch (phase) {
        LivenessPhase.position || LivenessPhase.multiple => 1,
        LivenessPhase.challenge => index + 2,
        _ => challenges.length + 2,
      };

  int get totalSteps => challenges.length + 2;

  void _reset() {
    final hadProgress = phase != LivenessPhase.position || index > 0;
    phase = LivenessPhase.position;
    index = 0;
    completed.clear();
    _trackId = null;
    _positionedFrames = 0;
    _straightFrames = 0;
    _sawOpen = _sawClosed = _sawLeft = _sawRight = false;
    challenges.shuffle();
    restarted = hadProgress;
  }

  /// Masukkan satu sampel. Return [phase] terbaru.
  LivenessPhase feed(FaceSample f) {
    restarted = false;
    if (phase == LivenessPhase.done) return phase;
    if (f.count > 1) {
      if (phase != LivenessPhase.position) _reset();
      phase = LivenessPhase.multiple;
      return phase;
    }
    if (f.count == 0) {
      if (phase == LivenessPhase.multiple) phase = LivenessPhase.position;
      if (++_missing > _maxMissing && _trackId != null) _reset();
      return phase;
    }
    _missing = 0;
    if (_trackId != null &&
        f.trackingId != null &&
        f.trackingId != _trackId) {
      _reset();
    }
    if (phase == LivenessPhase.multiple) phase = LivenessPhase.position;

    switch (phase) {
      case LivenessPhase.position:
        final straight = f.yaw.abs() < 15 && f.pitch.abs() < 15;
        _positionedFrames = f.framed && straight ? _positionedFrames + 1 : 0;
        if (_positionedFrames >= 3) {
          _trackId = f.trackingId;
          phase = LivenessPhase.challenge;
        }
      case LivenessPhase.challenge:
        if (_challengeMet(challenges[index], f)) {
          completed.add(challenges[index].name);
          index++;
          if (index >= challenges.length) phase = LivenessPhase.straight;
        }
      case LivenessPhase.straight:
        final ok = f.framed &&
            f.yaw.abs() < _straightDeg &&
            f.pitch.abs() < 12 &&
            (f.eyes ?? 1) > 0.6;
        _straightFrames = ok ? _straightFrames + 1 : 0;
        if (_straightFrames >= 2) phase = LivenessPhase.done;
      case LivenessPhase.multiple:
      case LivenessPhase.done:
        break;
    }
    return phase;
  }

  bool _challengeMet(LivenessChallenge c, FaceSample f) {
    switch (c) {
      case LivenessChallenge.blink:
        final e = f.eyes;
        if (e == null) return false;
        if (!_sawOpen) {
          _sawOpen = e > 0.7;
        } else if (!_sawClosed) {
          _sawClosed = e < 0.25;
        } else if (e > 0.6) {
          return true;
        }
        return false;
      case LivenessChallenge.turn:
        // Arah kamera depan ter-mirror → cukup lewati KEDUA sisi.
        if (f.yaw > _turnDeg) _sawLeft = true;
        if (f.yaw < -_turnDeg) _sawRight = true;
        return _sawLeft && _sawRight;
    }
  }
}
