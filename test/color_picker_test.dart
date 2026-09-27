import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/shared/color_picker_dialog.dart';

/// The picker is a tall dialog. Give the test a surface big enough to show all
/// of it so drags land on the real widgets rather than a clipped edge.
void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the picker on its own and records every previewed color.
Future<List<Color>> _pumpPicker(
  WidgetTester tester, {
  Color initial = const Color(0x804FC3F7),
}) async {
  _useLargeSurface(tester);
  final previews = <Color>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ColorPickerDialog(
        initial: initial,
        onPreview: previews.add,
      ),
    ),
  ));
  return previews;
}

void main() {
  group('color picker', () {
    testWidgets('opens on the color it was given', (tester) async {
      await _pumpPicker(tester, initial: const Color(0xFF4FC3F7));

      expect(find.text('#FF4FC3F7'), findsOneWidget);
      expect(find.text('Opacity  100%'), findsOneWidget);
    });

    testWidgets('shows the incoming opacity', (tester) async {
      await _pumpPicker(tester, initial: const Color(0x404FC3F7));

      expect(find.text('Opacity  25%'), findsOneWidget);
    });

    testWidgets('tapping a preset previews it and keeps the opacity',
        (tester) async {
      final previews = await _pumpPicker(tester,
          initial: const Color(0x804FC3F7)); // 50% blue

      await tester.tap(find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == Colors.red.shade500));
      await tester.pump();

      expect(previews, hasLength(1));
      // The preset supplies the hue...
      expect(previews.single.red, Colors.red.shade500.red);
      expect(previews.single.green, Colors.red.shade500.green);
      expect(previews.single.blue, Colors.red.shade500.blue);
      // ...but the opacity the user already had is carried over.
      expect(previews.single.alpha, closeTo(0x80, 1));
    });

    testWidgets('typing a hex previews that color', (tester) async {
      final previews = await _pumpPicker(tester);

      await tester.enterText(find.byType(TextField), '#FF00FF00');
      await tester.pump();

      expect(previews.last.value, 0xFF00FF00);
    });

    testWidgets('a six digit hex is treated as fully opaque', (tester) async {
      final previews = await _pumpPicker(tester);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      expect(previews.last.value, 0xFF123456);
    });

    testWidgets('a half typed hex is ignored rather than throwing',
        (tester) async {
      final previews = await _pumpPicker(tester);

      await tester.enterText(find.byType(TextField), '#12');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'nonsense');
      await tester.pump();

      expect(previews, isEmpty);
    });

    testWidgets('dragging the opacity bar to the right makes it opaque',
        (tester) async {
      final previews = await _pumpPicker(tester,
          initial: const Color(0x204FC3F7)); // nearly transparent

      await tester.dragFrom(
        tester.getCenter(find.byKey(const Key('picker.alpha'))),
        const Offset(400, 0),
      );
      await tester.pump();

      expect(previews.last.alpha, 0xFF);
    });

    testWidgets('dragging the opacity bar to the left clears it',
        (tester) async {
      final previews = await _pumpPicker(tester, initial: const Color(0xFF4FC3F7));

      await tester.dragFrom(
        tester.getCenter(find.byKey(const Key('picker.alpha'))),
        const Offset(-400, 0),
      );
      await tester.pump();

      expect(previews.last.alpha, 0);
    });

    testWidgets('dragging to the bottom of the square yields black',
        (tester) async {
      final previews = await _pumpPicker(tester, initial: const Color(0xFF4FC3F7));
      final square = find.byKey(const Key('picker.saturationValue'));

      await tester.dragFrom(
        tester.getCenter(square),
        const Offset(0, 400),
      );
      await tester.pump();

      expect(previews.last.red, 0);
      expect(previews.last.green, 0);
      expect(previews.last.blue, 0);
      // Dragging brightness to nothing must not disturb the opacity.
      expect(previews.last.alpha, 0xFF);
    });

    testWidgets('the hex field follows a change made elsewhere',
        (tester) async {
      await _pumpPicker(tester, initial: const Color(0xFF4FC3F7));

      await tester.tap(find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == Colors.green.shade500));
      await tester.pump();

      final hex =
          '#FF${Colors.green.shade500.value.toRadixString(16).substring(2).toUpperCase()}';
      expect(find.text(hex), findsOneWidget);
    });
  });

  group('showOverlayColorPicker', () {
    /// Opens the picker over a host page and reports the final color.
    Future<Color?> open(WidgetTester tester, Color initial) async {
      Color? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showOverlayColorPicker(
                context: context,
                initial: initial,
                onChanged: (c) => result = c,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('OK keeps the explored color', (tester) async {
      await open(tester, const Color(0xFF4FC3F7));

      await tester.enterText(find.byType(TextField), '#FF00FF00');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The caller previewed green while exploring and keeps it.
      expect(find.byType(ColorPickerDialog), findsNothing);
    });

    testWidgets('cancel restores the original color', (tester) async {
      Color? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showOverlayColorPicker(
                context: context,
                initial: const Color(0xFF4FC3F7),
                onChanged: (c) => result = c,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '#FF00FF00');
      await tester.pump();
      expect(result!.value, 0xFF00FF00); // previewed live

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result!.value, 0xFF4FC3F7); // and put back on cancel
    });

    testWidgets('OK reports the color that was chosen', (tester) async {
      Color? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showOverlayColorPicker(
                context: context,
                initial: const Color(0xFF4FC3F7),
                onChanged: (c) => result = c,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '#8000FF00');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result!.value, 0x8000FF00);
    });

    testWidgets('the title names the setting being edited', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showOverlayColorPicker(
                context: context,
                initial: const Color(0xFF4FC3F7),
                onChanged: (_) {},
                title: 'White Keys',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('White Keys'), findsOneWidget);
    });
  });
}
