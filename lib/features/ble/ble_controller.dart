import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../services/ble_scanner.dart';
import 'ble_permissions.dart';

/// 设备页用例：权限、扫描、连接。不直接调 flutter_blue_plus。
///
/// [startScan] / [connectAndDiscover] 用世代号作废进行中的请求。
/// 切走设备页、进后台或关掉 GATT 页时先 [stopScan] / [disconnect]，
/// 避免权限弹窗回来后又把扫描跑起来，或断开之后连接才成功。
class BleController extends ChangeNotifier {
  BleController({
    required BleScanner scanner,
    BlePermissionGate? permissions,
  })  : _scanner = scanner,
        _permissions =
            permissions ?? const PermissionHandlerBlePermissionGate() {
    _devicesSub = _scanner.devices.listen(
      (List<BleDeviceInfo> next) {
        devices = next;
        notifyListeners();
      },
      onError: (Object error) {
        errorMessage = error is AppError ? error.message : '扫描失败，请重试。';
        scanning = false;
        notifyListeners();
      },
    );
    _scanningSub = _scanner.scanning.listen((bool next) {
      scanning = next;
      notifyListeners();
    });
  }

  final BleScanner _scanner;
  final BlePermissionGate _permissions;
  StreamSubscription<List<BleDeviceInfo>>? _devicesSub;
  StreamSubscription<bool>? _scanningSub;
  int _scanGeneration = 0;
  int _connectGeneration = 0;
  bool _deviceSessionOpen = false;

  List<BleDeviceInfo> devices = <BleDeviceInfo>[];
  bool scanning = false;
  bool permanentlyDenied = false;
  String? errorMessage;
  String? connectingId;

  bool get deviceSessionOpen => _deviceSessionOpen;

  bool tryStartDeviceSession() {
    if (_deviceSessionOpen) {
      return false;
    }
    _deviceSessionOpen = true;
    notifyListeners();
    return true;
  }

  void endDeviceSession() {
    if (!_deviceSessionOpen) {
      return;
    }
    _deviceSessionOpen = false;
    notifyListeners();
  }

  Future<void> startScan() async {
    final int generation = ++_scanGeneration;
    errorMessage = null;
    permanentlyDenied = false;
    notifyListeners();
    try {
      await _ensurePermissions();
      if (!_scanIsCurrent(generation)) {
        return;
      }
      if (!await _scanner.isAdapterOn()) {
        throw const AppError(code: 'BLE_OFF', message: '请先打开手机蓝牙。');
      }
      if (!_scanIsCurrent(generation)) {
        return;
      }
      await _scanner.startScan();
    } on AppError catch (error) {
      if (!_scanIsCurrent(generation)) {
        return;
      }
      errorMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanGeneration++;
    await _scanner.stopScan();
    scanning = false;
    notifyListeners();
  }

  Future<List<BleGattServiceInfo>> connectAndDiscover(String id) async {
    final int generation = ++_connectGeneration;
    connectingId = id;
    notifyListeners();
    try {
      await _scanner.connect(id);
      if (!_connectIsCurrent(generation)) {
        await _scanner.disconnect(id);
        throw const AppError(code: 'BLE_CANCELLED', message: '已取消连接。');
      }
      final List<BleGattServiceInfo> services =
          await _scanner.discoverServices(id);
      if (!_connectIsCurrent(generation)) {
        await _scanner.disconnect(id);
        throw const AppError(code: 'BLE_CANCELLED', message: '已取消连接。');
      }
      return services;
    } finally {
      if (_connectIsCurrent(generation)) {
        connectingId = null;
        notifyListeners();
      }
    }
  }

  Future<void> disconnect(String id) async {
    _connectGeneration++;
    connectingId = null;
    await _scanner.disconnect(id);
    // dispose 期间树是锁住的，不能立刻 notify。
    scheduleMicrotask(_notifyIfActive);
  }

  void _notifyIfActive() {
    if (hasListeners) {
      notifyListeners();
    }
  }

  Future<bool> openSettings() => _permissions.openSettings();

  bool _scanIsCurrent(int generation) => generation == _scanGeneration;

  bool _connectIsCurrent(int generation) => generation == _connectGeneration;

  Future<void> _ensurePermissions() async {
    final BlePermissionResult result = await _permissions.request();
    permanentlyDenied = result.permanentlyDenied;
    if (!result.granted) {
      throw AppError(
        code: result.permanentlyDenied ? 'BLE_PERM_PERM' : 'BLE_PERM',
        message: result.permanentlyDenied
            ? '需要附近的设备和定位权限才能扫描。请在系统设置中开启。'
            : '需要附近的设备和定位权限才能扫描蓝牙设备。',
      );
    }
  }

  @override
  void dispose() {
    _scanGeneration++;
    _connectGeneration++;
    unawaited(_devicesSub?.cancel());
    unawaited(_scanningSub?.cancel());
    unawaited(_scanner.dispose());
    super.dispose();
  }
}
