import 'package:permission_handler/permission_handler.dart';

/// Сервис запроса системных разрешений.
class PermissionService {
  Future<PermissionReport> requestAll() async {
    final results = <String, PermissionStatus>{};
    results['bluetoothScan'] = await Permission.bluetoothScan.request();
    results['bluetoothConnect'] = await Permission.bluetoothConnect.request();
    results['bluetoothAdvertise'] =
        await Permission.bluetoothAdvertise.request();
    results['location'] = await Permission.locationWhenInUse.request();
    results['nearby'] = await Permission.nearbyWifiDevices.request();
    results['notifications'] = await Permission.notification.request();
    return PermissionReport(results);
  }

  /// Проверяет, есть ли всё критичное для запуска mesh.
  bool canMesh(PermissionReport report) {
    return report.results['bluetoothScan']?.isGranted == true &&
        report.results['bluetoothConnect']?.isGranted == true &&
        report.results['location']?.isGranted == true;
  }
}

class PermissionReport {
  final Map<String, PermissionStatus> results;
  PermissionReport(this.results);

  bool granted(String key) =>
      results[key]?.isGranted == true || results[key]?.isLimited == true;

  String describe() {
    return results.entries
        .map((e) => '${e.key}=${e.value.toString().split('.').last}')
        .join('  ');
  }
}
