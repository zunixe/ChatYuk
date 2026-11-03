/// Hasil pembelian YukCoin via Google Play — dipancarkan TopupService supaya
/// UI (mis. dialog koin habis di tengah call) bisa menunggu kredit nyata,
/// bukan menebak dari sheet yang tertutup.
enum TopupEventKind { started, pending, credited, failed, canceled }

class TopupEvent {
  final TopupEventKind kind;
  final int coins;
  const TopupEvent(this.kind, [this.coins = 0]);
}
