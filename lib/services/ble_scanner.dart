/// 扫描到的一台 BLE 外设。id 用来连接，不展示给用户。
class BleDeviceInfo {
  const BleDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  String get displayName => name.trim().isEmpty ? '未命名设备' : name;
}

/// 已发现的 GATT 服务 UUID。
class BleGattServiceInfo {
  const BleGattServiceInfo({required this.uuid});

  final String uuid;
}

/// BLE 扫描/连接。页面不直接碰 flutter_blue_plus。
abstract class BleScanner {
  Stream<List<BleDeviceInfo>> get devices;
  Stream<bool> get scanning;
  Future<bool> isAdapterOn();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<void> disconnect(String id);
  Future<List<BleGattServiceInfo>> discoverServices(String id);
  Future<void> dispose();
}
