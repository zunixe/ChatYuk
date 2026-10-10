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

/// path storage umum (chat/posts/timeline/voice/story/room-icons + ekstensi
/// dikenal). Cerminan `StoragePhotoService.isPath`.
bool isStoragePathValue(String value) =>
    (value.startsWith('chat/') ||
        value.startsWith('posts/') ||
        value.startsWith('timeline/') ||
        value.startsWith('voice/') ||
        value.startsWith('story/') ||
        value.startsWith('room-icons/')) &&
    (value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.png') ||
        value.contains('.m4a') ||
        value.contains('.mp3') ||
        value.contains('.mp4') ||
        value.contains('.mov'));

/// `chat/...mp4|mov` — path video chat. Cerminan `isChatVideoPath`.
bool isChatVideoPathValue(String v) =>
    v.startsWith('chat/') && (v.contains('.mp4') || v.contains('.mov'));

/// Batas ukuran & durasi video chat — cerminan konstanta
/// `StoragePhotoService.chatVideoMaxBytes/MaxMs` (dipakai validasi UI).
const int chatVideoMaxBytesValue = 8 * 1024 * 1024; // 8 MB
const int chatVideoMaxMsValue = 60 * 1000; // 60 detik
