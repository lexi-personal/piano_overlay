import 'package:flutter/material.dart';
import '../../services/project_provider.dart';
import '../../models/overlay_style.dart';

class SyncScreen extends StatefulWidget {
  final ProjectProvider provider;
  const SyncScreen({super.key, required this.provider});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late double _offsetMs;
  static const double _minOffset = -60000.0;
  static const double _maxOffset = 60000.0;

  @override
  void initState() {
    super.initState();
    _offsetMs = widget.provider.project?.sync.offsetMs ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Align MIDI to Audio'),
        actions: [
          TextButton(
            onPressed: _proceedToStyle,
            child: const Text('Continue →'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text('MIDI Offset', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${_offsetMs.toStringAsFixed(0)} ms',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _offsetMs < 0
                          ? 'MIDI plays ${(-_offsetMs).toStringAsFixed(0)}ms earlier'
                          : _offsetMs > 0
                              ? 'MIDI plays ${_offsetMs.toStringAsFixed(0)}ms later'
                              : 'No offset',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Coarse Adjustment', style: Theme.of(context).textTheme.titleSmall),
            Slider(
              value: _offsetMs,
              min: _minOffset,
              max: _maxOffset,
              divisions: 1000,
              label: '${_offsetMs.toStringAsFixed(0)} ms',
              onChanged: (v) => setState(() => _offsetMs = v),
              onChangeEnd: (_) => _saveSync(),
            ),
            const SizedBox(height: 16),
            Text('Fine Adjustment', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _nudgeButton('-100ms', -100),
                _nudgeButton('-10ms', -10),
                _nudgeButton('-1ms', -1),
                const SizedBox(width: 24),
                _nudgeButton('+1ms', 1),
                _nudgeButton('+10ms', 10),
                _nudgeButton('+100ms', 100),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _offsetMs = 0);
                  _saveSync();
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset to 0'),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Play the video and adjust the offset until the note strips '
                'align with the sounds you hear. Negative offset makes MIDI '
                'play earlier; positive makes it play later.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nudgeButton(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _offsetMs = (_offsetMs + amount).clamp(_minOffset, _maxOffset);
          });
          _saveSync();
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(50, 36),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  void _saveSync() {
    widget.provider.updateSync(SyncSettings(offsetMs: _offsetMs));
  }

  void _proceedToStyle() {
    _saveSync();
    Navigator.pushNamed(context, '/style');
  }
}
