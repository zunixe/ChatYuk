import 'package:flutter/foundation.dart';

import '../services/device_info_service.dart';

/// Provider info perangkat — screen tidak import `services/`.
class DeviceInfoProvider extends ChangeNotifier {
  final DeviceInfoService service;
  DeviceInfoProvider({DeviceInfoService? service})
      : service = service ?? DeviceInfoService.instance;

  Future<String> installId() => service.installId();
  Future<void> syncToServer({String ipAddress = ''}) =>
      service.syncToServer(ipAddress: ipAddress);

  String? _appVersionLabel;
  Future<String>? _appVersionLoading;

  /// Label versi aplikasi (mis. "v1.2.51+63") — di-cache supaya platform
  /// channel hanya dipanggil sekali.
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
