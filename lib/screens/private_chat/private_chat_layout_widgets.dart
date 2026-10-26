part of '../private_chat_screen.dart';

/// Tombol panah navigasi hasil search — rapat tanpa jeda atas-bawah
/// (InkWell 32x32, tanpa padding IconButton bawaan).
class SearchNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const SearchNavButton({super.key, 
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
          size: 24,
        ),
      ),
    );
  }
}




/// Padding bawah = tinggi keyboard (viewInsets). Dibuat widget TERPISAH
/// supaya `MediaQuery.viewInsetsOf` hanya mendaftarkan element INI sebagai
/// depend — bukan element `PrivateChatScreen`. Tanpa ini, IME frame MIUI yang
/// redundan (puluhan/detik) me-rebuild SELURUH layar chat.
class KeyboardInset extends StatelessWidget {
  final Widget child;
  const KeyboardInset({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
