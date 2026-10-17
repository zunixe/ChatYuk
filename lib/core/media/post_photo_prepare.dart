import 'dart:typed_data';

import '../media/blurhash.dart';
import '../media/chat_photo_helper.dart';
import '../media/native_image.dart';

/// Pemroses foto post (resize/kompresi). Default = jalur native
/// (`NativeImage.processPost`); bisa diinjeksi untuk test.
typedef PostPhotoProcessor =
    Future<({Uint8List bytes, int width, int height})?> Function(
      Uint8List raw,
    );

/// Penghitung BlurHash. Default = [computeBlurHash]; bisa diinjeksi untuk test.
typedef PostBlurHashFn = Future<String?> Function(Uint8List bytes);

/// Proses satu foto pilih → bytes siap upload + dimensi + BlurHash.
///
/// Aturan (FASE 2):
///  - Kompresi/resize lewat [processor] (native). Bila GAGAL (`null`), pakai
///    **file ASLI** — jangan hilangkan foto user — dan tetap hitung metadata.
///  - Dimensi diambil dari hasil proses (yang benar-benar diunggah); bila
///    tidak tersedia, fallback ke header file asli.
///  - BlurHash dari versi kecil (32px) — dihitung dari bytes yang diunggah.
///  - Return null hanya bila bytes bukan gambar yang bisa dibaca (pemanggil
///    menampilkan pesan gagal).
Future<({Uint8List bytes, int w, int h, String blurhash})?> preparePostPhoto(
  Uint8List raw, {
  PostPhotoProcessor? processor,
  PostBlurHashFn? blurhashOf,
}) async {
  if (raw.isEmpty) return null;
  var bytes = raw;
  var w = 0;
  var h = 0;

  ({Uint8List bytes, int width, int height})? processed;
  try {
    processed = processor != null
        ? await processor(raw)
        : await NativeImage.processPost(raw);
  } catch (_) {
    processed = null; // kompresi gagal → fallback file asli
  }
  if (processed != null) {
    bytes = processed.bytes;
    w = processed.width;
    h = processed.height;
  }

  if (w <= 0 || h <= 0) {
    final dims = parseImageDimensions(bytes);
    w = dims?.width ?? 0;
    h = dims?.height ?? 0;
  }
  if (w <= 0 || h <= 0) return null;

  final bh = await (blurhashOf != null ? blurhashOf(bytes) : computeBlurHash(bytes));
  return (bytes: bytes, w: w, h: h, blurhash: bh ?? '');
}
