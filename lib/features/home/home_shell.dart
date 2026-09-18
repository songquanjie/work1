import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_controller.dart';
import '../ble/device_list_page.dart';
import '../recording_list/recording_list_page.dart';

/// 底栏切「笔记 / 设备」。IndexedStack 保住两个页的状态，避免每次重建列表。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _index != 1 || !mounted) {
      return;
    }
    unawaited(context.read<BleController>().startScan());
  }

  Future<void> _select(int index) async {
    if (index == _index) {
      return;
    }
    final BleController ble = context.read<BleController>();
    if (_index == 1) {
      await ble.stopScan();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _index = index;
    });
    if (index == 1) {
      unawaited(ble.startScan());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          RecordingListPage(),
          DeviceListPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => unawaited(_select(index)),
        destinations: const <Widget>[
          NavigationDestination(
            key: Key('nav_notes'),
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic),
            label: '笔记',
          ),
          NavigationDestination(
            key: Key('nav_devices'),
            icon: Icon(Icons.bluetooth_searching_outlined),
            selectedIcon: Icon(Icons.bluetooth_searching),
            label: '设备',
          ),
        ],
      ),
    );
  }
}
