import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/avatar_provider.dart';
import 'package:chatyuk/providers/contact_provider.dart';
import 'package:chatyuk/providers/device_info_provider.dart';
import 'package:chatyuk/providers/location_provider.dart';
import 'package:chatyuk/services/avatar_service.dart';
import 'package:chatyuk/services/contact_service.dart';
import 'package:chatyuk/services/device_info_service.dart';
import 'package:chatyuk/services/geo_service.dart';
import 'package:chatyuk/services/location_service.dart';

class MockAvatarService extends Mock implements AvatarB64Service {}
class MockContactService extends Mock implements ContactService {}
class MockDeviceInfoService extends Mock implements DeviceInfoService {}
class MockLocationService extends Mock implements LocationService {}
class MockGeoService extends Mock implements GeoService {}

void main() {
  test('AvatarProvider meneruskan get/prefetch/clear', () async {
    final svc = MockAvatarService();
    when(() => svc.get('u1')).thenAnswer((_) async => 'b64');
    when(() => svc.prefetch(any())).thenAnswer((_) async {});
    final p = AvatarProvider(service: svc);
    expect(await p.get('u1'), 'b64');
    await p.prefetch(['u1', 'u2']);
    verify(() => svc.prefetch(['u1', 'u2'])).called(1);
    p.clearForUid('u1');
    verify(() => svc.clearForUid('u1')).called(1);
  });

  test('ContactProvider meneruskan submitMessage', () async {
    final svc = MockContactService();
    when(() => svc.submitMessage(
          message: any(named: 'message'),
          name: any(named: 'name'),
          userId: any(named: 'userId'),
        )).thenAnswer((_) async {});
    final p = ContactProvider(service: svc);
    await p.submitMessage(message: 'halo', userId: 'u1');
    verify(() => svc.submitMessage(message: 'halo', userId: 'u1')).called(1);
  });

  test('DeviceInfoProvider meneruskan installId/syncToServer', () async {
    final svc = MockDeviceInfoService();
    when(() => svc.installId()).thenAnswer((_) async => 'dev-1');
    when(() => svc.syncToServer(ipAddress: any(named: 'ipAddress')))
        .thenAnswer((_) async {});
    final p = DeviceInfoProvider(service: svc);
    expect(await p.installId(), 'dev-1');
    await p.syncToServer(ipAddress: '1.2.3.4');
    verify(() => svc.syncToServer(ipAddress: '1.2.3.4')).called(1);
  });

  test('LocationProvider meneruskan location + geo', () async {
    final loc = MockLocationService();
    final geo = MockGeoService();
    when(() => loc.requestPermission()).thenAnswer((_) async => true);
    when(() => geo.detectByIp('1.1.1.1'))
        .thenAnswer((_) async => null);
    final p = LocationProvider(location: loc, geo: geo);
    expect(await p.requestPermission(), true);
    expect(await p.detectByIp('1.1.1.1'), null);
    verify(() => geo.detectByIp('1.1.1.1')).called(1);
  });
}
