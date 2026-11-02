/// Status pengajuan withdraw.
enum WithdrawStatus {
  pending,
  paid,
  rejected;

  static WithdrawStatus fromJson(dynamic v) => switch (v) {
    'paid' => WithdrawStatus.paid,
    'rejected' => WithdrawStatus.rejected,
    _ => WithdrawStatus.pending,
  };

  String get key => switch (this) {
    WithdrawStatus.paid => 'paid',
    WithdrawStatus.rejected => 'rejected',
    WithdrawStatus.pending => 'pending',
  };
}

/// Satu pengajuan withdraw (tabel `withdrawal_requests`).
class WithdrawRequest {
  final String id;
  final int coins;
  final int rate;
  final int grossIdr;
  final int feeIdr;
  final int netIdr;
  final WithdrawStatus status;
  final String payMethod;
  final String danaNumber;
  final String danaName;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const WithdrawRequest({
    required this.id,
    required this.coins,
    required this.rate,
    required this.grossIdr,
    required this.feeIdr,
    required this.netIdr,
    required this.status,
    this.payMethod = 'ewallet',
    required this.danaNumber,
    required this.danaName,
    this.adminNote,
    required this.createdAt,
    this.reviewedAt,
  });

  factory WithdrawRequest.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    return WithdrawRequest(
      id: json['id']?.toString() ?? '',
      coins: i(json['coin_amount']),
      rate: i(json['rate']),
      grossIdr: i(json['gross_idr']),
      feeIdr: i(json['fee_idr']),
      netIdr: i(json['payout_idr']),
      status: WithdrawStatus.fromJson(json['status']),
      payMethod: json['pay_method'] ?? 'ewallet',
      danaNumber: json['pay_account'] ?? '',
      danaName: json['pay_holder'] ?? '',
      adminNote: json['admin_note'],
      createdAt:
          DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse('${json['reviewed_at']}')
          : null,
    );
  }

  bool get isPending => status == WithdrawStatus.pending;
  bool get isPaid => status == WithdrawStatus.paid;
  bool get isRejected => status == WithdrawStatus.rejected;
}

/// Akun DANA tersimpan user.
class WithdrawAccount {
  final String danaNumber;
  final String danaName;

  const WithdrawAccount({required this.danaNumber, required this.danaName});

  factory WithdrawAccount.fromJson(Map<String, dynamic> json) =>
      WithdrawAccount(
        danaNumber: json['dana_number'] ?? '',
        danaName: json['dana_name'] ?? '',
      );
}

/// Hasil kalkulasi withdraw (preview sebelum submit).
class WithdrawQuote {
  final int coins;
  final int rate;
  final int grossIdr;
  final int feeIdr;
  final int netIdr;

  const WithdrawQuote({
    required this.coins,
    required this.rate,
    required this.grossIdr,
    required this.feeIdr,
    required this.netIdr,
  });

  /// Hitung dari setting server (dipakai untuk preview real-time di form).
  factory WithdrawQuote.calc(
    int coins, {
    required int rate,
    required int feePct,
    required int feeMinIdr,
  }) {
    final gross = coins * rate;
    var fee = (gross * feePct) / 100;
    if (fee < feeMinIdr) fee = feeMinIdr.toDouble();
    if (fee > gross) fee = gross.toDouble();
    return WithdrawQuote(
      coins: coins,
      rate: rate,
      grossIdr: gross,
      feeIdr: fee.round(),
      netIdr: gross - fee.round(),
    );
  }
}
