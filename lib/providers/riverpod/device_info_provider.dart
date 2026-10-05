import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/device_info_service.dart';

/// Info perangkat — action-only (+ cache appVersionLabel internal).
/// Migrasi dari ChangeNotifier (0 notifyListeners) → Provider.
class DeviceInfoNotifier {
  final DeviceInfoService service;
  DeviceInfoNotifier([DeviceInfoService? service])
      : service = service ?? DeviceInfoService.instance;

  Future<String> installId() => service.installId();
  Future<void> syncToServer({String ipAddress = ''}) =>
      service.syncToServer(ipAddress: ipAddress);

  String? _appVersionLabel;
  Future<String>? _appVersionLoading;

  Future<String> appVersionLabel() {
    if (_appVersionLabel != null) return Future.value(_appVersionLabel);
    return _appVersionLoading ??= service.collectDeviceInfo().then((info) {
      final v = info.appVersion;
      final b = info.buildNumber;
      _appVersionLabel = v.isEmpty ? '' : (b.isEmpty ? 'v$v' : 'v$v+$b');
      return _appVersionLabel!;
    });
  }
}

final deviceInfoProvider =
    Provider<DeviceInfoNotifier>((_) => DeviceInfoNotifier());
