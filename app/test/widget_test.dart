import 'package:flutter_test/flutter_test.dart';

import 'package:drople/main.dart';

void main() {
  testWidgets('App menampilkan judul Drople', (WidgetTester tester) async {
    await tester.pumpWidget(const DropleApp());
    await tester.pump();

    expect(find.text('Drople'), findsOneWidget);
  });
}
