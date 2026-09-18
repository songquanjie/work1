import 'package:permission_handler/permission_handler.dart';

/// 附近设备扫描所需的系统权限。测试可换成假实现，避免真调系统弹窗。
class BlePermissionResult {
  const BlePermissionResult({
    required this.granted,
    this.permanentlyDenied = false,
  });

  final bool granted;
  final bool permanentlyDenied;
}

abstract class BlePermissionGate {
  Future<BlePermissionResult> request();
  Future<bool> openSettings();
}

class PermissionHandlerBlePermissionGate implements BlePermissionGate {
  const PermissionHandlerBlePermissionGate();

  @override
  Future<BlePermissionResult> request() async {
    final Map<Permission, PermissionStatus> statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    bool denied = false;
    bool forever = false;
    for (final PermissionStatus status in statuses.values) {
      if (status.isPermanentlyDenied) {
        forever = true;
        denied = true;
      } else if (status.isDenied || status.isRestricted) {
        denied = true;
      }
    }
    return BlePermissionResult(
      granted: !denied,
      permanentlyDenied: forever,
    );
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
