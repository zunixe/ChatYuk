import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/avatar_service.dart';
import '../../services/storage_photo_service.dart';
import 'avatar_provider.dart';
import 'message_reaction_provider.dart';
import 'storage_provider.dart';

/// Akses service dari lapisan UI (widgets) TANPA import `services/` langsung
/// dan TANPA wajib `ProviderScope` (mis. preview/test widget telanjang).
///
/// Boundary Fase B (2026-10-10): widgets/mixins/screens dilarang import
/// `services/`. Provider transparan di atas (avatarProvider/storageProvider)
/// dipakai saat scope ada; helper di file ini jadi fallback aman bila scope
/// belum ada (unit test widget murni / preview).
///
/// Widget sebaiknya tetap pakai provider lewat `safe*` di bawah supaya tidak
/// crash saat di-mount tanpa `ProviderScope`.
class UiServices {
  UiServices._();

  static AvatarB64Service get avatar => AvatarB64Service.instance;
  static StoragePhotoService get storage => StoragePhotoService.instance;
}

/// Baca provider; fallback ke [fallback] bila `ProviderScope` tidak ada
/// (unit test widget murni / preview). Widget tetap render tanpa crash.
T safeRead<T>(BuildContext context, ProviderListenable<T> provider, T fallback) {
  try {
    return ProviderScope.containerOf(context, listen: false).read(provider);
  } catch (_) {
    return fallback;
  }
}

/// AvatarNotifier aman (provider bila scope ada, singleton bila tidak).
AvatarNotifier safeAvatar(BuildContext context) =>
    safeRead(context, avatarProvider, AvatarNotifier(UiServices.avatar));

/// StorageNotifier aman (provider bila scope ada, singleton bila tidak).
StorageNotifier safeStorage(BuildContext context) =>
    safeRead(context, storageProvider, StorageNotifier(UiServices.storage));

/// MessageReactionNotifier aman — fallback singleton.
MessageReactionNotifier safeReactions(BuildContext context) => safeRead(
      context,
      messageReactionProvider,
      MessageReactionNotifier(),
    );
