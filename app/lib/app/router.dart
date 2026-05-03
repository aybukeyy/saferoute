import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/about/about_screen.dart';
import '../features/feed/recent_reports_screen.dart';
import '../features/map/map_screen.dart';
import '../features/onboarding/model_download_screen.dart';
import '../features/route/route_detail_screen.dart';
import '../features/route/route_planner_screen.dart';
import '../features/route/route_share_view_screen.dart';

/// App-wide router. Home is the live MapScreen; secondary screens are
/// pushed via go_router named routes. The integration agent may extend
/// this with additional debug/dev routes after wiring the real services.
///
/// `initialLocation` is decided in `main.dart` — model-missing boots into
/// `/onboarding/models`, otherwise straight into `/`.
GoRouter buildAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/feed',
        name: 'feed',
        builder: (context, state) => const RecentReportsScreen(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/route',
        name: 'route',
        builder: (context, state) => const RoutePlannerScreen(),
      ),
      GoRoute(
        path: '/onboarding/models',
        name: 'onboarding_models',
        builder: (context, state) => const ModelDownloadScreen(),
      ),
      GoRoute(
        path: '/route/detail',
        name: 'route_detail',
        builder: (context, state) {
          final req = state.extra;
          if (req is RouteRequest) {
            return RouteDetailScreen(request: req);
          }
          return const Scaffold(
            body: Center(child: Text('Missing route request payload')),
          );
        },
      ),
      GoRoute(
        path: '/share/:id',
        name: 'route_share_view',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return RouteShareViewScreen(shareId: id);
        },
      ),
    ],
  );
}
