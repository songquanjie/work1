import 'dart:async';

import 'package:echonote/app.dart';
import 'package:echonote/core/errors/app_error.dart';
import 'package:echonote/data/local/recording_database.dart';
import 'package:echonote/features/ble/ble_controller.dart';
import 'package:echonote/features/ble/ble_permissions.dart';
import 'package:echonote/features/ble/device_gatt_page.dart';
import 'package:echonote/features/ble/device_list_page.dart';
import 'package:echonote/features/home/home_shell.dart';
import 'package:echonote/features/recorder/recorder_controller.dart';
import 'package:echonote/models/recording.dart';
import 'package:echonote/repositories/recording_repository.dart';
import 'package:echonote/services/ble_scanner.dart';
import 'package:echonote/services/player_service.dart';
import 'package:echonote/services/recorder_service.dart';
import 'package:echonote/services/recording_file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fake_ble_scanner.dart';

void main() {
  test('startScan asks permission then starts the scanner', () async {
    final FakeBleScanner scanner = FakeBleScanner();
    final FakeBlePermissionGate permissions = FakeBlePermissionGate();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: permissions,
    );
    addTearDown(ble.dispose);

    await ble.startScan();

    expect(permissions.requestCount, 1);
    expect(scanner.startCount, 1);
    expect(ble.errorMessage, isNull);
  });

  test('bluetooth off shows a user-facing message', () async {
    final FakeBleScanner scanner = FakeBleScanner(adapterOn: false);
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    await ble.startScan();

    expect(scanner.startCount, 0);
    expect(ble.errorMessage, '请先打开手机蓝牙。');
  });

  test('denied permission does not start scan', () async {
    final FakeBleScanner scanner = FakeBleScanner();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(
        result: const BlePermissionResult(granted: false),
      ),
    );
    addTearDown(ble.dispose);

    await ble.startScan();

    expect(scanner.startCount, 0);
    expect(ble.errorMessage, contains('附近的设备和定位权限'));
  });

  test('stopScan cancels an in-flight startScan', () async {
    final FakeBleScanner scanner = FakeBleScanner();
    final Completer<BlePermissionResult> delayed =
        Completer<BlePermissionResult>();
    final FakeBlePermissionGate permissions = FakeBlePermissionGate();
    permissions.onRequest = () => delayed.future;
    final BleController ble = BleController(
      scanner: scanner,
      permissions: permissions,
    );
    addTearDown(ble.dispose);

    final Future<void> started = ble.startScan();
    await ble.stopScan();
    delayed.complete(const BlePermissionResult(granted: true));
    await started;

    expect(scanner.startCount, 0);
  });

  test('second device session is ignored until the first closes', () {
    final BleController ble = BleController(
      scanner: FakeBleScanner(),
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    expect(ble.tryStartDeviceSession(), isTrue);
    expect(ble.tryStartDeviceSession(), isFalse);
    ble.endDeviceSession();
    expect(ble.tryStartDeviceSession(), isTrue);
  });

  test('disconnect during connect cancels discovery', () async {
    final FakeBleScanner scanner = FakeBleScanner();
    final Completer<void> blocker = Completer<void>();
    scanner.connectBlocker = blocker.future;
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    final Future<List<BleGattServiceInfo>> connecting =
        ble.connectAndDiscover('dev-1');
    await ble.disconnect('dev-1');
    blocker.complete();

    await expectLater(
      connecting,
      throwsA(
        isA<AppError>().having(
          (AppError error) => error.code,
          'code',
          'BLE_CANCELLED',
        ),
      ),
    );
    expect(scanner.disconnectCount, greaterThanOrEqualTo(1));
  });

  testWidgets('device list shows name and RSSI', (WidgetTester tester) async {
    final FakeBleScanner scanner = FakeBleScanner();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<BleController>.value(
        value: ble,
        child: const MaterialApp(home: DeviceListPage()),
      ),
    );
    scanner.devicesController.add(
      const <BleDeviceInfo>[
        BleDeviceInfo(id: 'aa:bb', name: 'nRF Phone', rssi: -42),
      ],
    );
    await tester.pump();

    expect(find.text('nRF Phone'), findsOneWidget);
    expect(find.text('-42 dBm'), findsOneWidget);
  });

  testWidgets('tapping a device lists GATT services then disconnects on pop', (
    WidgetTester tester,
  ) async {
    final FakeBleScanner scanner = FakeBleScanner();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<BleController>.value(
        value: ble,
        child: const MaterialApp(home: DeviceListPage()),
      ),
    );
    scanner.devicesController.add(
      const <BleDeviceInfo>[
        BleDeviceInfo(id: 'dev-1', name: 'Advertiser', rssi: -50),
      ],
    );
    await tester.pump();
    await tester.tap(find.text('Advertiser'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceGattPage), findsOneWidget);
    expect(scanner.connectCount, 1);
    expect(scanner.connectedId, 'dev-1');
    expect(
      find.text('00001800-0000-1000-8000-00805f9b34fb'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scanner.disconnectCount, 1);
  });

  testWidgets('failed connect shows retry', (WidgetTester tester) async {
    final ConnectFailScanner scanner = ConnectFailScanner();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<BleController>.value(
        value: ble,
        child: const MaterialApp(
          home: DeviceGattPage(deviceId: 'x', deviceName: '失败设备'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法连接该设备。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('home shell switches between notes and devices', (
    WidgetTester tester,
  ) async {
    final FakeBleScanner scanner = FakeBleScanner();
    final BleController ble = BleController(
      scanner: scanner,
      permissions: FakeBlePermissionGate(),
    );
    addTearDown(ble.dispose);

    final RecordingRepository repository = RecordingRepository(
      database: _MemoryStore(),
      files: RecordingFileStore(),
      playback: _SilentPlayback(),
    );
    final PlayerService player = PlayerService();
    final RecorderController recorder = RecorderController(
      recorder: RecorderService(),
      repository: repository,
    );
    addTearDown(repository.dispose);
    addTearDown(player.dispose);
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      EchoNoteApp(
        repository: repository,
        player: player,
        recorderController: recorder,
        bleController: ble,
        pollingEnabled: false,
        child: const MaterialApp(home: HomeShell()),
      ),
    );

    expect(find.text('随身录音笔记'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);

    await tester.tap(find.text('设备'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('附近设备'), findsOneWidget);
    expect(scanner.startCount, 1);

    await tester.tap(find.text('笔记'));
    await tester.pump();
    expect(scanner.stopCount, greaterThanOrEqualTo(1));
  });
}

class _MemoryStore implements RecordingStore {
  @override
  Future<void> insert(Recording recording) async {}

  @override
  Future<void> update(Recording recording) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Recording?> findById(String id) async => null;

  @override
  Future<List<Recording>> findAllNewestFirst() async => <Recording>[];

  @override
  Future<void> close() async {}
}

class _SilentPlayback implements RecordingPlayback {
  @override
  Future<void> stopIfPlaying(String id) async {}
}
