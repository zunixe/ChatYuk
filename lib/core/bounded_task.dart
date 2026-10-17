/// Jalankan [run] untuk tiap item dengan konkurensi MAKSIMAL [maxConcurrent].
///
/// Dipakai jalur upload foto post: dulu semua foto diunggah serentak → lonjakan
/// memori/bandwidth di HP kelas menengah. Urutan item dipertahankan oleh
/// pemanggil (indeks diteruskan ke [run]); fungsi ini hanya membatasi jumlah
/// pekerjaan yang berjalan bersamaan.
///
/// Tidak melempar: error dari [run] diteruskan ke pemanggil (biarkan [run]
/// menangani sendiri) — di sini `await` di dalam worker akan meneruskan
/// exception; pemanggil yang menentukan. Untuk pemakaian upload, `run`
/// menangkap error per-item.
Future<void> runBounded<T>({
  required List<T> items,
  required int maxConcurrent,
  required Future<void> Function(T item, int index) run,
}) async {
  if (items.isEmpty) return;
  final limit = maxConcurrent.clamp(1, items.length);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      await run(items[i], i);
    }
  }

  await Future.wait(List.generate(limit, (_) => worker()));
}
