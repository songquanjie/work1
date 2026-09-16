import 'package:echonote/core/utils/time_format.dart';
import 'package:echonote/features/recorder/recorder_page.dart';
import 'package:echonote/features/recorder/recorder_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('idle state only enables start', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderControlBar(
            state: RecorderState.idle,
            onStart: () {},
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    expect(_enabled(tester, 'recorder_start'), isTrue);
    expect(_enabled(tester, 'recorder_pause'), isFalse);
    expect(_enabled(tester, 'recorder_resume'), isFalse);
    expect(_enabled(tester, 'recorder_stop'), isFalse);
  });

  testWidgets('recording enables pause and stop', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderControlBar(
            state: RecorderState.recording,
            onStart: () {},
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    expect(_enabled(tester, 'recorder_start'), isFalse);
    expect(_enabled(tester, 'recorder_pause'), isTrue);
    expect(_enabled(tester, 'recorder_resume'), isFalse);
    expect(_enabled(tester, 'recorder_stop'), isTrue);
  });

  testWidgets('paused enables resume and stop', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderControlBar(
            state: RecorderState.paused,
            onStart: () {},
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    expect(_enabled(tester, 'recorder_resume'), isTrue);
    expect(_enabled(tester, 'recorder_stop'), isTrue);
    expect(_enabled(tester, 'recorder_start'), isFalse);
  });

  testWidgets('saving and busy lock every control', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecorderControlBar(
            state: RecorderState.recording,
            busy: true,
            onStart: () {},
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    expect(_enabled(tester, 'recorder_start'), isFalse);
    expect(_enabled(tester, 'recorder_pause'), isFalse);
    expect(_enabled(tester, 'recorder_resume'), isFalse);
    expect(_enabled(tester, 'recorder_stop'), isFalse);
  });

  testWidgets('recorder chrome shows title and clock', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecorderScaffold(
          state: RecorderState.idle,
          elapsed: Duration.zero,
          volumeLevel: 0,
          errorMessage: null,
          permanentlyDenied: false,
          onStart: () {},
          onPause: () {},
          onResume: () {},
          onStop: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    expect(find.text('随身录音笔记'), findsOneWidget);
    expect(find.text(formatClock(Duration.zero)), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
  });

  test('ui policy matches widget rules', () {
    expect(RecorderUiPolicy.canStart(RecorderState.saveFailed), isTrue);
    expect(RecorderUiPolicy.buttonsLocked(RecorderState.saving), isTrue);
    expect(RecorderUiPolicy.canPause(RecorderState.paused), isFalse);
  });
}

bool _enabled(WidgetTester tester, String key) {
  final Finder finder = find.byKey(Key(key));
  final FilledButton button = tester.widget<FilledButton>(
    find.descendant(of: finder, matching: find.byType(FilledButton)),
  );
  return button.onPressed != null;
}
