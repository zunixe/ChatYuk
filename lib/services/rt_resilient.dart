import 'dart:async';
import 'dart:math';
import '../utils.dart';

/// Bungkus `Stream.listen` realtime dengan auto-resubscribe saat error.
///
/// Latar: subscription Supabase `.stream()` yang kena error (mis.
/// `RealtimeSubscribeException channelError` saat network blip) MATI
/// permanen — `onError` yang cuma log membuat list/story/counts freeze
/// sampai app di-restart ("tiba-tiba blank, harus tutup-buka lagi").
///
/// Helper ini membuka ulang stream dengan backoff (2→4→8…→60 dtk +
/// jitter) sampai sukses atau di-cancel/dispose. Mengembalikan
/// [StreamSubscription] asli sehingga field bertipe itu tetap cocok.
StreamSubscription<T> listenResilient<T>(
  Stream<T> Function() open,
  void Function(T event) onData, {
  required bool Function() isDisposed,
  void Function(Object error)? onError,
  void Function()? onRecovered,
}) {
  return _ResilientSubscription<T>(
    open: open,
    onData: onData,
    isDisposed: isDisposed,
    onError: onError,
    onRecovered: onRecovered,
  );
}

class _ResilientSubscription<T> implements StreamSubscription<T> {
  final Stream<T> Function() _open;
  final void Function(T event) _onData;
  final bool Function() _isDisposed;
  final void Function(Object error)? _onError;
  final void Function()? _onRecovered;

  StreamSubscription<T>? _current;
  bool _cancelled = false;
  int _attempt = 0;
  Timer? _retryTimer;
  Completer<void>? _cancelCompleter;

  static const _delays = [2, 4, 8, 16, 32, 60];
  static final _rnd = Random();

  _ResilientSubscription({
    required Stream<T> Function() open,
    required void Function(T event) onData,
    required bool Function() isDisposed,
    void Function(Object error)? onError,
    void Function()? onRecovered,
  })  : _open = open,
        _onData = onData,
        _isDisposed = isDisposed,
        _onError = onError,
        _onRecovered = onRecovered {
    _subscribe();
  }

  void _subscribe() {
    if (_cancelled || _isDisposed()) return;
    late final StreamSubscription<T> sub;
    try {
      sub = _open().listen(
        (event) {
          _attempt = 0; // sukses → reset backoff
          _onData(event);
        },
        onError: (Object e) => _scheduleRetry(e),
        onDone: () {
          // Stream selesai tanpa error (mis. server tutup) → coba lagi.
          if (!_cancelled && !_isDisposed()) _scheduleRetry(StateError('stream done'));
        },
        cancelOnError: false,
      );
    } catch (e) {
      _scheduleRetry(e);
      return;
    }
    _current = sub;
    if (_cancelled || _isDisposed()) {
      unawaited(sub.cancel());
      _current = null;
    }
  }

  bool _reconnecting = false;

  void _scheduleRetry(Object e) {
    // Error + onDone sering datang bersamaan (sink yang throw juga
    // menyelesaikan stream) — jadwalkan retry pertama saja.
    if (_reconnecting) return;
    _reconnecting = true;
    _current = null;
    try {
      _onError?.call(e);
    } catch (_) {}
    if (_cancelled || _isDisposed()) {
      _cancelCompleter?.complete();
      return;
    }
    final base = _delays[_attempt.clamp(0, _delays.length - 1)];
    if (_attempt < _delays.length - 1) _attempt++;
    // Jitter ±25% supaya banyak device tidak retry serentak.
    final delay =
        Duration(milliseconds: (base * 1000 * (0.75 + _rnd.nextDouble() * 0.5)).round());
    dlog('[RT-RESILIENT] error, retry in ${delay.inSeconds}s: $e');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_cancelled || _isDisposed()) {
        _cancelCompleter?.complete();
        return;
      }
      try {
        _onRecovered?.call();
      } catch (_) {}
      _reconnecting = false;
      _subscribe();
    });
  }

  @override
  Future<void> cancel() {
    _cancelled = true;
    _retryTimer?.cancel();
    final c = _current;
    _current = null;
    if (c == null) {
      _cancelCompleter ??= Completer<void>();
      return _cancelCompleter!.future;
    }
    return c.cancel();
  }

  // ── Delegasi ke subscription aktif ──
  @override
  void onData(void Function(T data)? handleData) => _current?.onData(handleData);

  @override
  void onError(Function? handleError) => _current?.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _current?.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _current?.pause(resumeSignal);

  @override
  void resume() => _current?.resume();

  @override
  bool get isPaused => _current?.isPaused ?? false;

  @override
  Future<E> asFuture<E>([E? futureValue]) =>
      _current?.asFuture<E>(futureValue) ?? Future<E>.value(futureValue as E);
}
