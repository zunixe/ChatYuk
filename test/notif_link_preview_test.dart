import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/notif/link_preview_notif.dart';

/// Notifikasi pesan berisi LINK: tampilkan deskripsi/judul preview (bukan URL
/// mentah) + hanya pakai gambar https untuk BigPicture.
void main() {
  test('body: deskripsi → judul → teks asli', () {
    expect(
      notifBodyForLinkPreview(
        {'previewDesc': 'Deskripsi video', 'previewTitle': 'Judul'},
        'https://youtu.be/x',
      ),
      'Deskripsi video',
    );
    expect(
      notifBodyForLinkPreview({'previewTitle': 'Judul'}, 'https://youtu.be/x'),
      'Judul',
    );
    expect(
      notifBodyForLinkPreview({'previewDesc': '  ', 'previewTitle': ''}, 'halo'),
      'halo',
    );
    expect(notifBodyForLinkPreview({}, '📇 Budi'), '📇 Budi');
  });

  test('gambar: hanya https', () {
    expect(isNotifPreviewImage('https://cdn.x/a.jpg'), isTrue);
    expect(isNotifPreviewImage('http://cdn.x/a.jpg'), isFalse);
    expect(isNotifPreviewImage(''), isFalse);
    expect(isNotifPreviewImage(null), isFalse);
  });

  test('judul gambar preview', () {
    expect(notifPreviewImageTitle({'previewTitle': 'Judul'}), 'Judul');
    expect(notifPreviewImageTitle({}), '');
  });
}
