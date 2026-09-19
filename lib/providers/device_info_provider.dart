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
}
