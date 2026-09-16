import 'package:echonote/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows product title', (WidgetTester tester) async {
    await tester.pumpWidget(const EchoNoteApp());
    expect(find.text('随身录音笔记'), findsOneWidget);
    expect(find.text('欢迎使用'), findsOneWidget);
  });
}
