import 'package:flutter/material.dart';

/// Opens the shared overlay color picker.
///
/// [onChanged] fires live while the user explores, so the overlay behind the
/// dialog updates as they drag. Cancelling or dismissing restores [initial].
Future<void> showOverlayColorPicker({
  required BuildContext context,
  required Color initial,
  required ValueChanged<Color> onChanged,
  String title = 'Pick Color',
}) async {
  final picked = await showDialog<Color>(
    context: context,
    builder: (ctx) => ColorPickerDialog(
      initial: initial,
      title: title,
      onPreview: onChanged,
    ),
  );
  // A dismissed dialog returns null, which means "leave it as it was".
  onChanged(picked ?? initial);
}

/// A palette-plus-custom color picker with a hex field and an opacity slider.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;

  /// Called on every change so the caller can preview it immediately.
  final ValueChanged<Color> onPreview;

  const ColorPickerDialog({
    super.key,
    required this.initial,
    required this.onPreview,
    this.title = 'Pick Color',
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  /// Hue families for the preset grid, three shades of each.
  static const List<MaterialColor> _families = <MaterialColor>[
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
  ];

  static const List<Color> _neutrals = <Color>[
    Colors.white,
    Color(0xFFE0E0E0),
    Color(0xFFBDBDBD),
    Color(0xFF9E9E9E),
    Color(0xFF616161),
    Color(0xFF424242),
    Color(0xFF212121),
    Colors.black,
  ];

  late HSVColor _hsv;
  late TextEditingController _hexController;

  /// True while a pointer is down on one of the picker surfaces. Scrolling is
  /// suspended for the duration so a vertical drag on the saturation square
  /// changes brightness instead of scrolling the dialog out from under it.
  bool _interacting = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial)
        .withAlpha(widget.initial.opacity);
    _hexController = TextEditingController(text: _toHex(widget.initial));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  /// Applies [next] and previews it. [syncHex] is false while the user is
  /// typing in the hex field, so their caret is not yanked around.
  void _apply(HSVColor next, {bool syncHex = true}) {
    setState(() {
      _hsv = next;
      if (syncHex) _hexController.text = _toHex(next.toColor());
    });
    widget.onPreview(next.toColor());
  }

  void _onHexChanged(String raw) {
    var text = raw.trim().replaceFirst('#', '');
    if (text.length == 6) text = 'FF$text';
    if (text.length != 8) return;
    final value = int.tryParse(text, radix: 16);
    if (value == null) return;
    _apply(HSVColor.fromColor(Color(value)), syncHex: false);
  }

  static String _toHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          physics: _interacting
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Presets'),
              _paletteGrid(),
              const SizedBox(height: 16),
              _label('Custom'),
              SizedBox(
                height: 130,
                child: _PointerSurface(
                  key: const Key('picker.saturationValue'),
                  painter: _SaturationValuePainter(_hsv),
                  onStart: () => setState(() => _interacting = true),
                  onEnd: () => setState(() => _interacting = false),
                  onPick: (x, y) =>
                      _apply(_hsv.withSaturation(x).withValue(1.0 - y)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 20,
                child: _PointerSurface(
                  key: const Key('picker.hue'),
                  painter: _HuePainter(_hsv),
                  onStart: () => setState(() => _interacting = true),
                  onEnd: () => setState(() => _interacting = false),
                  onPick: (x, _) => _apply(_hsv.withHue(x * 360.0)),
                ),
              ),
              const SizedBox(height: 10),
              _label('Opacity  ${(_hsv.alpha * 100).round()}%'),
              SizedBox(
                height: 20,
                child: _PointerSurface(
                  key: const Key('picker.alpha'),
                  painter: _AlphaPainter(_hsv),
                  onStart: () => setState(() => _interacting = true),
                  onEnd: () => setState(() => _interacting = false),
                  onPick: (x, _) => _apply(_hsv.withAlpha(x)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _swatchPreview(_color, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Hex (#RRGGBB or #AARRGGBB)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onHexChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );

  Widget _paletteGrid() {
    final presets = <Color>[
      for (final family in _families) family.shade300,
      for (final family in _families) family.shade500,
      for (final family in _families) family.shade700,
      ..._neutrals,
    ];
    final current = _color;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in presets)
          GestureDetector(
            // Presets choose a hue, not a transparency, so the opacity the
            // user already dialled in is carried over.
            onTap: () =>
                _apply(HSVColor.fromColor(preset).withAlpha(_hsv.alpha)),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: preset,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: preset.value == current.withOpacity(1).value
                      ? Colors.white
                      : Colors.white24,
                  width: preset.value == current.withOpacity(1).value ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _swatchPreview(Color color, {double size = 28}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: const CheckerPainter(),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

/// A painted surface that reports where the pointer is as a 0-1 fraction of
/// its own size.
///
/// This tracks raw pointer events rather than using a gesture recognizer: a
/// pan recognizer inside a scroll view loses the gesture arena to the
/// scrollable, which would make vertical drags on the saturation square scroll
/// the dialog instead of changing the color.
class _PointerSurface extends StatelessWidget {
  final CustomPainter painter;
  final void Function(double x, double y) onPick;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _PointerSurface({
    super.key,
    required this.painter,
    required this.onPick,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void handle(Offset local) => onPick(
              (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
              (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
            );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            onStart();
            handle(event.localPosition);
          },
          onPointerMove: (event) => handle(event.localPosition),
          onPointerUp: (_) => onEnd(),
          onPointerCancel: (_) => onEnd(),
          child: CustomPaint(
            painter: painter,
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }
}

/// The saturation (x) by value (y) square for the current hue.
class _SaturationValuePainter extends CustomPainter {
  final HSVColor hsv;

  _SaturationValuePainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    _drawThumb(
      canvas,
      Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

/// A horizontal hue ramp.
class _HuePainter extends CustomPainter {
  final HSVColor hsv;

  _HuePainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0 % 360.0, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.restore();
    _drawThumb(canvas, Offset(hsv.hue / 360.0 * size.width, size.height / 2));
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => oldDelegate.hsv != hsv;
}

/// A horizontal opacity ramp over a checkerboard.
class _AlphaPainter extends CustomPainter {
  final HSVColor hsv;

  _AlphaPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    final opaque = hsv.withAlpha(1).toColor();

    canvas.save();
    canvas.clipRRect(rrect);
    _paintChecker(canvas, rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [opaque.withOpacity(0), opaque],
        ).createShader(rect),
    );
    canvas.restore();
    _drawThumb(canvas, Offset(hsv.alpha * size.width, size.height / 2));
  }

  @override
  bool shouldRepaint(_AlphaPainter oldDelegate) => oldDelegate.hsv != hsv;
}

/// Grey checkerboard so transparency is visible against the dialog.
class CheckerPainter extends CustomPainter {
  const CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      _paintChecker(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(CheckerPainter oldDelegate) => false;
}

void _paintChecker(Canvas canvas, Rect rect, {double cell = 6}) {
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final dark = Paint()..color = const Color(0xFFCCCCCC);
  for (var y = 0; y * cell < rect.height; y++) {
    for (var x = 0; x * cell < rect.width; x++) {
      if ((x + y).isEven) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + x * cell,
          rect.top + y * cell,
          cell,
          cell,
        ).intersect(rect),
        dark,
      );
    }
  }
}

/// A white ring with a dark outline, readable over any backdrop.
void _drawThumb(Canvas canvas, Offset center) {
  canvas.drawCircle(
    center,
    7,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white,
  );
  canvas.drawCircle(
    center,
    8.5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black54,
  );
}
