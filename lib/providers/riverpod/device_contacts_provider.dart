import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/device_contacts_service.dart';
export '../../services/device_contacts_service.dart'
    show
        ContactsPermission,
        DeviceContact,
        DeviceContactsService;

/// Kontak HP (buku telepon perangkat) — action-only, pembungkus service.
///
/// Layar TIDAK boleh import `services/` (boundary AGENTS) → pakai provider ini.
class DeviceContactsNotifier {
  final DeviceContactsService service;
  DeviceContactsNotifier([DeviceContactsService? service])
      : service = service ?? DeviceContactsService();

  ContactsPermission get permission => service.permission;

  Future<List<DeviceContact>> load({bool requestPermission = true}) =>
      service.load(requestPermission: requestPermission);

  Future<ContactsPermission> ensurePermission({bool request = true}) =>
      service.ensurePermission(request: request);

  Future<void> openSettings() => service.openSettings();

  void clearCache() => service.clearCache();
}

final deviceContactsProvider =
    Provider<DeviceContactsNotifier>((_) => DeviceContactsNotifier());
