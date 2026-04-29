import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/app.dart';
import 'package:piano_overlay/services/project_provider.dart';

void main() {
  testWidgets('App launches and shows home screen', (WidgetTester tester) async {
    final provider = ProjectProvider();
    await tester.pumpWidget(PianoOverlayApp(projectProvider: provider));
    expect(find.text('Piano Overlay'), findsWidgets);
    expect(find.text('New Project'), findsOneWidget);
  });
}
