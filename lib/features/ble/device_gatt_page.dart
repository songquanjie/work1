import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_error.dart';
import '../../services/ble_scanner.dart';
import 'ble_controller.dart';

/// 连接一台 BLE 设备并列出 GATT 服务。离开页面时取消连接，避免占着外设。
class DeviceGattPage extends StatefulWidget {
  const DeviceGattPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  State<DeviceGattPage> createState() => _DeviceGattPageState();
}

class _DeviceGattPageState extends State<DeviceGattPage> {
  late final BleController _ble;
  bool _loading = true;
  String? _error;
  List<BleGattServiceInfo> _services = <BleGattServiceInfo>[];

  @override
  void initState() {
    super.initState();
    _ble = context.read<BleController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_connect());
      }
    });
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<BleGattServiceInfo> services =
          await _ble.connectAndDiscover(widget.deviceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _services = services;
        _loading = false;
      });
    } on AppError catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'BLE_CANCELLED') {
        return;
      }
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'echonote',
          context: ErrorDescription('连接蓝牙设备'),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '无法连接该设备。';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_ble.disconnect(widget.deviceId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => unawaited(_connect()),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _services.isEmpty
                  ? const Center(child: Text('没有发现 GATT 服务。'))
                  : ListView.separated(
                      itemCount: _services.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final BleGattServiceInfo service = _services[index];
                        return ListTile(
                          title: const Text('GATT 服务'),
                          subtitle: Text(service.uuid),
                        );
                      },
                    ),
    );
  }
}
