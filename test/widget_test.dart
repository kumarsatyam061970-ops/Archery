// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archer/main.dart';

void main() {
  testWidgets('ArcheryGame can mount inside GameWidget', (tester) async {
    await tester.pumpWidget(
      GameWidget(
        game: ArcheryGame(),
      ),
    );

    // Flame games render to a CustomPaint widget; verify it's present.
    expect(find.byType(GameWidget), findsOneWidget);
  });
}
