import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ble_scanner.dart';
import 'ble_controller.dart';
import 'device_gatt_page.dart';

/// 扫描附近 BLE，展示名称和信号强度，点一行去读 GATT 服务。
class DeviceListPage extends StatelessWidget {
  const DeviceListPage({super.key});

  Future<void> _openSettings(BuildContext context) async {
    await context.read<BleController>().openSettings();
  }

  void _openDevice(BuildContext context, BleDeviceInfo item) {
    final BleController ble = context.read<BleController>();
    if (!ble.tryStartDeviceSession()) {
      return;
    }
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => DeviceGattPage(
                deviceId: item.id,
                deviceName: item.displayName,
              ),
            ),
          )
          .whenComplete(ble.endDeviceSession),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BleController ble = context.watch<BleController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('附近设备'),
        actions: <Widget>[
          if (ble.scanning)
            TextButton(
              onPressed: () => unawaited(ble.stopScan()),
              child: const Text('停止'),
            )
          else
            TextButton(
              onPressed: () => unawaited(ble.startScan()),
              child: const Text('扫描'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (ble.errorMessage != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: Text(ble.errorMessage!),
                trailing: ble.permanentlyDenied
                    ? TextButton(
                        onPressed: () => unawaited(_openSettings(context)),
                        child: const Text('去设置'),
                      )
                    : null,
              ),
            ),
          if (ble.scanning) const LinearProgressIndicator(),
          Expanded(
            child: ble.devices.isEmpty
                ? Center(
                    child: Text(
                      ble.scanning
                          ? '正在扫描附近的蓝牙设备…'
                          : '还没有设备。打开另一台手机的蓝牙广播后点扫描。',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: ble.devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final BleDeviceInfo item = ble.devices[index];
                      return ListTile(
                        key: Key('ble_${item.id}'),
                        enabled: !ble.deviceSessionOpen,
                        title: Text(item.displayName),
                        subtitle: Text('${item.rssi} dBm'),
                        onTap: ble.deviceSessionOpen
                            ? null
                            : () => _openDevice(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
