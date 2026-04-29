// Smoke test for the wired-up app. Builds `SafeRouteApp` inside a
// `ProviderScope` (no overrides) so the UI fixtures from
// `lib/features/providers.dart` drive the screens. The integration overrides
// in `main.dart` would require sqflite + Firebase init, which the Flutter
// test harness can't satisfy by default.
//
// We pump-and-settle until the first real frame, then assert the home
// AppBar title shows up. The earlier "Skeleton ready" placeholder no longer
// exists — MapScreen replaces it.

import 'package:app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home renders the Safe Route app shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SafeRouteApp()));
    // FlutterMap kicks off some long-running async work — pump a few frames
    // rather than `pumpAndSettle` so we don't time out on background timers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Safe Route'), findsOneWidget);
    expect(find.byTooltip('Plan a route'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });
}
