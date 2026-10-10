/// Predikat path storage — MURNI (tanpa I/O, tanpa plugin, tanpa service).
///
/// Dipisah di `core/` supaya layer UI (screens/widgets/providers) bisa
/// mengecek tipe path TANPA import `services/` (boundary Fase B).
/// KONTRAK: prefix HARUS sinkron dengan `StoragePhotoService` (satu-satunya
/// penulis path). Bila prefix berubah di sana, ubah di sini juga.
library;

/// `avatars/...` — path foto avatar.
bool isAvatarPathValue(String v) => v.startsWith('avatars/');

/// `gallery/...` — path foto galeri.
bool isGalleryPathValue(String v) => v.startsWith('gallery/');

/// `voice/...m4a` — path pesan suara.
bool isVoicePathValue(String v) => v.startsWith('voice/') && v.contains('.m4a');
