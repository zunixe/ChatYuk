/// Kategori room yang sama dipakai untuk SETIAP negara.
/// Dipindah ke config agar screen boleh import (boundary: screen
/// dilarang import services/ — lihat scripts/check_screen_boundary.sh).
const List<Map<String, String>> roomCategories = [
  {'id': 'general', 'name': 'General', 'icon': '💬', 'desc': 'Chat umum'},
  {'id': 'curhat', 'name': 'Curhat', 'icon': '💭', 'desc': 'Cerita & curhat'},
  {
    'id': 'pertemanan',
    'name': 'Pertemanan',
    'icon': '🤝',
    'desc': 'Cari teman baru',
  },
  {
    'id': 'teknologi',
    'name': 'Teknologi',
    'icon': '💻',
    'desc': 'Diskusi tech',
  },
  {'id': 'gaming', 'name': 'Gaming', 'icon': '🎮', 'desc': 'Main & bahas game'},
  {'id': 'musik', 'name': 'Musik', 'icon': '🎵', 'desc': 'Sharing musik'},
  {'id': 'film', 'name': 'Film & TV', 'icon': '🎬', 'desc': 'Review film'},
  {'id': 'joke', 'name': 'Joke & Meme', 'icon': '😂', 'desc': 'Bikin ngakak'},
  {'id': 'belajar', 'name': 'Belajar', 'icon': '📚', 'desc': 'Diskusi belajar'},
  {'id': 'flirt', 'name': 'Flirt', 'icon': '💘', 'desc': 'Ngobrol asyik'},
];
