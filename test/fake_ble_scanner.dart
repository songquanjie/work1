import 'dart:async';

import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/features/ble/ble_permissions.dart';
import 'package:echonote/services/ble_scanner.dart';

class FakeBleScanner implements BleScanner {
  FakeBleScanner({
    this.adapterOn = true,
    this.services = const <BleGattServiceInfo>[
      BleGattServiceInfo(uuid: '00001800-0000-1000-8000-00805f9b34fb'),
    ],
  });

  bool adapterOn;
  List<BleGattServiceInfo> services;
  String? connectedId;
  int startCount = 0;
  int stopCount = 0;
  int connectCount = 0;
  int disconnectCount = 0;
  Future<void>? connectBlocker;

  final StreamController<List<BleDeviceInfo>> devicesController =
      StreamController<List<BleDeviceInfo>>.broadcast();
  final StreamController<bool> scanningController =
      StreamController<bool>.broadcast();

  @override
  Stream<List<BleDeviceInfo>> get devices => devicesController.stream;

  @override
  Stream<bool> get scanning => scanningController.stream;

  @override
  Future<bool> isAdapterOn() async => adapterOn;

  @override
  Future<void> startScan() async {
    startCount += 1;
    scanningController.add(true);
  }

  @override
  Future<void> stopScan() async {
    stopCount += 1;
    scanningController.add(false);
  }

  @override
  Future<void> connect(String id) async {
    final Future<void>? blocker = connectBlocker;
    if (blocker != null) {
      await blocker;
    }
    connectCount += 1;
    connectedId = id;
  }

  @override
  Future<void> disconnect(String id) async {
    disconnectCount += 1;
  }

  @override
  Future<List<BleGattServiceInfo>> discoverServices(String id) async {
    return services;
  }

  @override
  Future<void> dispose() async {
    await devicesController.close();
    await scanningController.close();
  }
}

class FakeBlePermissionGate implements BlePermissionGate {
  FakeBlePermissionGate({
    this.result = const BlePermissionResult(granted: true),
  });

  BlePermissionResult result;
  int requestCount = 0;
  int openSettingsCount = 0;
  Future<BlePermissionResult> Function()? onRequest;

  @override
  Future<BlePermissionResult> request() async {
    requestCount += 1;
    final Future<BlePermissionResult> Function()? override = onRequest;
    if (override != null) {
      return override();
    }
    return result;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    return true;
  }
}

class ConnectFailScanner extends FakeBleScanner {
  @override
  Future<void> connect(String id) async {
    throw const AppError(code: 'BLE_CONNECT', message: '无法连接该设备。');
  }
}
