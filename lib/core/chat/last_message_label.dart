import '../../config/strings.dart';

/// Terjemahkan label media dari server (trigger `handle_new_private_message`
/// menulis label BERBAHASA INDONESIA ke `private_chats.last_message`, mis.
/// `[Stiker]`) ke bahasa UI aktif. Teks biasa dikembalikan apa adanya.
/// Murni & testable.
String localizeLastMessage(String raw, S s) {
  switch (raw) {
    case '[Foto]':
      return s.msgPhoto;
    case '[Stiker]':
      return s.previewSticker;
    case '[Pesan suara]':
      return s.previewVoice;
    case '[Video]':
      return s.previewVideo;
    case '[Koin]':
      return s.previewCoin;
    case '[Hadiah]':
      return s.previewGift;
    case '[Lokasi]':
      return s.previewLocation;
    default:
      return raw;
  }
}
