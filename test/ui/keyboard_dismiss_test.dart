import 'package:debt_tracker/ui/widgets/keyboard_dismiss.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int pressed;

  Future<void> pump(WidgetTester tester) async {
    pressed = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => TapOutsideClosesKeyboard(child: child!),
      home: Scaffold(
        body: ListView(
          children: [
            const TextField(key: Key('a'), keyboardType: TextInputType.number),
            const TextField(key: Key('b'), keyboardType: TextInputType.number),
            Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  pressed++;
                  showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('dialog'),
                      content: TextField(key: Key('d'), keyboardType: TextInputType.number),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
          ],
        ),
      ),
    ));
  }

  bool focused(WidgetTester tester, String key) =>
      tester.widget<EditableText>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText))).focusNode.hasFocus;

  testWidgets('a tap on empty space closes the number pad', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(focused(tester, 'a'), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('row 3'));
    await tester.pump();
    expect(focused(tester, 'a'), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a tap on another field moves there; the keyboard stays', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('b')));
    await tester.pump();
    expect(focused(tester, 'a'), isFalse);
    expect(focused(tester, 'b'), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('scrolling keeps the keyboard up', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    final before = tester.getTopLeft(find.text('row 5')).dy;
    await tester.drag(find.text('row 5'), const Offset(0, -40));
    await tester.pump();
    expect(tester.getTopLeft(find.text('row 5')).dy, lessThan(before));
    expect(focused(tester, 'a'), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a button tapped while typing still works and closes the keyboard', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
    expect(focused(tester, 'a'), isFalse);

    // Inside a dialog too.
    await tester.tap(find.byKey(const Key('d')));
    await tester.pump();
    expect(focused(tester, 'd'), isTrue);
    await tester.tap(find.text('dialog'));
    await tester.pump();
    expect(focused(tester, 'd'), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('typing still works after the keyboard was closed and opened again', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.tap(find.text('row 2'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    tester.testTextInput.enterText('1500');
    await tester.pump();
    expect(find.text('1500'), findsOneWidget);
  });
}
