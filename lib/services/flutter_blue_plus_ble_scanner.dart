import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/errors/app_error.dart';
import 'ble_scanner.dart';

/// 用 flutter_blue_plus 扫附近 BLE、连接并读 GATT 服务。
///
/// 一次扫描约 15 秒。扫描期间对端停播约 3 秒后从列表去掉。
/// RSSI 最多每秒刷新一次，且按首次出现顺序排列，避免整表跟着信号跳。
class FlutterBluePlusBleScanner implements BleScanner {
  FlutterBluePlusBleScanner();

  final Map<String, BluetoothDevice> _byId = <String, BluetoothDevice>{};
  final List<String> _order = <String>[];
  final StreamController<List<BleDeviceInfo>> _devices =
      StreamController<List<BleDeviceInfo>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;
  final StreamController<bool> _scanning = StreamController<bool>.broadcast();
  Timer? _rssiTimer;
  List<BleDeviceInfo>? _pending;
  Set<String> _visibleIds = <String>{};

  @override
  Stream<List<BleDeviceInfo>> get devices => _devices.stream;

  @override
  Stream<bool> get scanning => _scanning.stream;

  @override
  Future<bool> isAdapterOn() async {
    final BluetoothAdapterState state =
        await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  @override
  Future<void> startScan() async {
    await stopScan();
    _byId.clear();
    _order.clear();
    _pending = null;
    _visibleIds = <String>{};
    _rssiTimer?.cancel();
    _rssiTimer = null;
    _emitDevices(const <BleDeviceInfo>[]);
    _scanSub = FlutterBluePlus.onScanResults.listen(
      _onResults,
      onError: (Object error, StackTrace stack) {
        _report('BLE_SCAN', '扫描失败，请重试。', error, stack);
        if (!_devices.isClosed) {
          _devices.addError(
            const AppError(code: 'BLE_SCAN', message: '扫描失败，请重试。'),
            stack,
          );
        }
      },
    );
    _scanningSub = FlutterBluePlus.isScanning.listen((bool value) {
      if (!_scanning.isClosed) {
        _scanning.add(value);
      }
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      _throwAppError(
        'BLE_SCAN',
        '无法开始扫描。请打开蓝牙和定位后再试。',
        error,
        stack,
      );
    }
  }

  void _onResults(List<ScanResult> results) {
    final Map<String, BluetoothDevice> nextMap = <String, BluetoothDevice>{};
    final Map<String, BleDeviceInfo> infos = <String, BleDeviceInfo>{};
    for (final ScanResult result in results) {
      final String id = result.device.remoteId.str;
      nextMap[id] = result.device;
      final String advertised = result.advertisementData.advName.trim();
      final String platform = result.device.platformName.trim();
      infos[id] = BleDeviceInfo(
        id: id,
        name: advertised.isNotEmpty ? advertised : platform,
        rssi: result.rssi,
      );
    }
    _byId
      ..clear()
      ..addAll(nextMap);
    _order.removeWhere((String id) => !nextMap.containsKey(id));
    for (final String id in nextMap.keys) {
      if (!_order.contains(id)) {
        _order.add(id);
      }
    }
    final List<BleDeviceInfo> next =
        _order.map((String id) => infos[id]!).toList();
    final Set<String> ids = nextMap.keys.toSet();
    final bool membershipChanged =
        ids.length != _visibleIds.length || !ids.containsAll(_visibleIds);
    _pending = next;
    if (membershipChanged) {
      _flushPending();
    } else {
      _rssiTimer ??= Timer(const Duration(seconds: 1), _flushPending);
    }
  }

  void _flushPending() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    final List<BleDeviceInfo>? pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    _visibleIds = pending.map((BleDeviceInfo item) => item.id).toSet();
    _emitDevices(pending);
  }

  void _emitDevices(List<BleDeviceInfo> next) {
    if (!_devices.isClosed) {
      _devices.add(next);
    }
  }

  @override
  Future<void> stopScan() async {
    _flushPending();
    await _scanSub?.cancel();
    _scanSub = null;
    await _scanningSub?.cancel();
    _scanningSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (error, stack) {
      // 停扫失败不影响下次再扫，只记下来方便排障。
      _report('BLE_STOP', '停止扫描失败', error, stack);
    }
    if (!_scanning.isClosed) {
      _scanning.add(false);
    }
  }

  BluetoothDevice _require(String id) {
    return _byId.putIfAbsent(id, () => BluetoothDevice.fromId(id));
  }

  @override
  Future<void> connect(String id) async {
    await stopScan();
    try {
      await _require(id).connect(timeout: const Duration(seconds: 20));
    } catch (error, stack) {
      _throwAppError('BLE_CONNECT', '无法连接该设备。', error, stack);
    }
  }

  @override
  Future<void> disconnect(String id) async {
    try {
      await _require(id).disconnect();
    } catch (error, stack) {
      _report('BLE_DISCONNECT', '断开连接失败', error, stack);
    }
  }

  @override
  Future<List<BleGattServiceInfo>> discoverServices(String id) async {
    try {
      final List<BluetoothService> services =
          await _require(id).discoverServices();
      return services
          .map(
            (BluetoothService service) => BleGattServiceInfo(
              uuid: service.uuid.str,
            ),
          )
          .toList();
    } catch (error, stack) {
      _throwAppError('BLE_GATT', '无法读取 GATT 服务。', error, stack);
    }
  }

  @override
  Future<void> dispose() async {
    await stopScan();
    await _devices.close();
    await _scanning.close();
  }

  Never _throwAppError(
    String code,
    String message,
    Object error,
    StackTrace stack,
  ) {
    _report(code, message, error, stack);
    throw AppError(code: code, message: message);
  }

  void _report(
    String code,
    String message,
    Object error,
    StackTrace stack,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'echonote',
        context: ErrorDescription(message),
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<String>('code', code),
        ],
      ),
    );
  }
}
