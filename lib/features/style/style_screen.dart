import 'package:flutter/material.dart';
import '../../services/project_provider.dart';
import '../../models/overlay_style.dart';

class StyleScreen extends StatefulWidget {
  final ProjectProvider provider;
  const StyleScreen({super.key, required this.provider});

  @override
  State<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends State<StyleScreen> {
  late Color _whiteKeyColor;
  late Color _blackKeyColor;
  late double _stripThickness;
  late double _glowStrength;
  late double _glowRadius;
  late double _transparency;
  late double _fallSpeed;

  @override
  void initState() {
    super.initState();
    final style = widget.provider.project?.style ?? const OverlayStyle();
    _whiteKeyColor = style.whiteKeyColor;
    _blackKeyColor = style.blackKeyColor;
    _stripThickness = style.stripThickness;
    _glowStrength = style.glowStrength;
    _glowRadius = style.glowRadius;
    _transparency = style.transparency;
    _fallSpeed = style.fallSpeed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Overlay'),
        actions: [
          TextButton(
            onPressed: _proceedToPreview,
            child: const Text('Preview →'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Colors'),
          _colorRow('White Key Strip', _whiteKeyColor, (c) => setState(() => _whiteKeyColor = c)),
          _colorRow('Black Key Strip', _blackKeyColor, (c) => setState(() => _blackKeyColor = c)),
          const Divider(height: 32),
          _sectionTitle('Strip Appearance'),
          _sliderRow('Thickness', _stripThickness, 0.2, 1.0,
              (v) => setState(() => _stripThickness = v)),
          _sliderRow('Glow Strength', _glowStrength, 0.0, 1.0,
              (v) => setState(() => _glowStrength = v)),
          _sliderRow('Glow Radius', _glowRadius, 0.0, 20.0,
              (v) => setState(() => _glowRadius = v)),
          _sliderRow('Transparency', _transparency, 0.0, 1.0,
              (v) => setState(() => _transparency = v)),
          const Divider(height: 32),
          _sectionTitle('Timing'),
          _sliderRow('Fall Speed', _fallSpeed, 50.0, 500.0,
              (v) => setState(() => _fallSpeed = v)),
          const SizedBox(height: 32),
          Center(
            child: FilledButton.icon(
              onPressed: _proceedToPreview,
              icon: const Icon(Icons.preview),
              label: const Text('Preview with these settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
          SizedBox(width: 50, child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _colorRow(String label, Color color, ValueChanged<Color> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          GestureDetector(
            onTap: () => _showColorPicker(color, onChanged),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
        ],
      ),
    );
  }

  void _showColorPicker(Color current, ValueChanged<Color> onChanged) {
    final colors = [
      const Color(0xFF4FC3F7), const Color(0xFF81C784), const Color(0xFFFF7043),
      const Color(0xFFBA68C8), const Color(0xFFFFD54F), const Color(0xFFE57373),
      const Color(0xFF4DB6AC), const Color(0xFFFFFFFF), const Color(0xFFF06292),
      const Color(0xFF7986CB),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a Color'),
        content: Wrap(
          spacing: 8, runSpacing: 8,
          children: colors.map((c) => GestureDetector(
            onTap: () { onChanged(c); Navigator.pop(ctx); },
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(8),
                border: c == current ? Border.all(color: Colors.white, width: 3) : null,
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _saveStyle() {
    widget.provider.updateStyle(OverlayStyle(
      whiteKeyColor: _whiteKeyColor,
      blackKeyColor: _blackKeyColor,
      stripThickness: _stripThickness,
      glowStrength: _glowStrength,
      glowRadius: _glowRadius,
      transparency: _transparency,
      fallSpeed: _fallSpeed,
    ));
  }

  void _proceedToPreview() {
    _saveStyle();
    Navigator.pushNamed(context, '/preview');
  }
}
