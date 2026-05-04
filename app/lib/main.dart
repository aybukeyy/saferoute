// App entry point.
//
// Boot order:
//   1. Open the local SQLite DB (sqflite).
//   2. Best-effort init Firebase + anonymous auth (skips silently in
//      `local-only` mode if `firebase_options.dart` isn't generated yet).
//   3. Build a `ProviderContainer` that overrides the UI's `*Like` providers
//      from `lib/features/providers.dart` with the production adapters from
//      `lib/app/real_providers.dart`.
//   4. First-launch seed (`SeedLoader`) — populates a curated set of demo
//      reports so the heatmap is non-empty on first boot.
//   5. Fire-and-forget warm-up of the Gemma 4 E2B classifier.
//
// Every step is wrapped in try/catch so a missing manual-setup step (no
// Firebase, no Gemma weights, no OSM graph) only degrades that subsystem
// instead of crashing the whole app.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai/model_storage.dart';
import 'app/real_providers.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/l10n/app_strings.dart';
import 'data/classification_worker.dart';
import 'data/local_db.dart';
import 'data/proximity_alert_service.dart';
import 'data/seed_loader.dart';
import 'data/sync_service.dart' as data;
import 'features/providers.dart' as ui;
import 'features/settings/locale_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Step 0 — flutter_gemma plugin init. Must run before any installModel()
  // call. Idempotent in plugin internals; cheap.
  try {
    await FlutterGemma.initialize();
  } catch (e) {
    debugPrint('[main] FlutterGemma.initialize failed: $e');
  }

  // Step 1 — Local DB.
  final localDb = LocalDb();
  try {
    await localDb.init();
  } catch (e, st) {
    debugPrint('[main] LocalDb init failed: $e\n$st');
  }

  // Local notifications init. Skipped under flutter_test where the native
  // plugin channels aren't bound and would throw MissingPluginException.
  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  NotificationDispatcher dispatcher = ({
    required int id,
    required String title,
    required String body,
  }) async {
    debugPrint('[proximity] (no-op) $title — $body');
  };
  if (!Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      await notificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      try {
        final android = notificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            kProximityChannelId,
            'Proximity alerts',
            description:
                'Warns when you enter a high-risk area near recent reports.',
            importance: Importance.high,
          ),
        );
      } catch (e) {
        debugPrint('[main] Android notification setup failed: $e');
      }
      try {
        final ios = notificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } catch (e) {
        debugPrint('[main] iOS notification permission failed: $e');
      }
      dispatcher = ({
        required int id,
        required String title,
        required String body,
      }) async {
        await notificationsPlugin.show(
          id,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              kProximityChannelId,
              'Proximity alerts',
              channelDescription:
                  'Warns when you enter a high-risk area near recent reports.',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      };
    } catch (e) {
      debugPrint('[main] FlutterLocalNotifications init failed: $e');
    }
  }

  // Step 2 — Best-effort Firebase + anonymous auth.
  String userUid = 'local-only';
  try {
    final sync = await data.SyncService.tryInitialize();
    userUid = await sync.ensureAnonymousAuth();
  } catch (e) {
    debugPrint('[main] Firebase not configured (continuing local-only): $e');
  }

  // Step 3 — Wire the container with overrides.
  final container = ProviderContainer(
    overrides: [
      // Pin shared singletons.
      localDbProvider.overrideWithValue(localDb),
      currentUserUidValueProvider.overrideWithValue(userUid),
      proximityNotificationDispatcherProvider.overrideWithValue(dispatcher),

      // Bridge the UI `*Like` interfaces to the real implementations.
      ui.locationServiceProvider
          .overrideWith((ref) => ref.watch(realLocationServiceLikeProvider)),
      ui.reportsRepositoryProvider
          .overrideWith((ref) => ref.watch(realReportsRepositoryLikeProvider)),
      ui.riskEngineProvider
          .overrideWith((ref) => ref.watch(realRiskEngineLikeProvider)),
      ui.routingServiceProvider
          .overrideWith((ref) => ref.watch(realRoutingServiceLikeProvider)),
      ui.syncServiceProvider
          .overrideWith((ref) => ref.watch(realSyncServiceLikeProvider)),
    ],
  );

  // Step 4 — First-launch seed. Best-effort.
  try {
    final risk = container.read(realRiskEngineProvider);
    await SeedLoader.seedIfFirstLaunch(
      localDb: localDb,
      riskEngine: risk,
      defaultUid: userUid,
    );
  } catch (e, st) {
    debugPrint('[main] Seed loader failed (continuing): $e\n$st');
  }

  // Step 5 — Decide initial route. The Gemma weights are downloaded at
  // runtime (not bundled), so a fresh install lands on the onboarding
  // screen instead of the map. The check is a fast `File.exists` only —
  // no sha256 verify on the boot path.
  String initialRoute = '/';
  try {
    final storage = container.read(modelStorageProvider);
    final manifest = await container.read(modelManifestProvider.future);
    final filenames =
        manifest.models.values.map((m) => m.filename).toList();
    final allPresent = await storage.areAllPresent(filenames);
    if (!allPresent) {
      initialRoute = '/onboarding/models';
    }
  } catch (e) {
    // If the manifest is malformed or the support dir can't be resolved,
    // skip the gate — MapScreen's banner will surface the missing model.
    debugPrint('[main] model presence check failed (continuing): $e');
  }

  // Step 6 — Warm Gemma 4 E2B in the background only if the weights are
  // actually on disk. ModelMissingException is silently swallowed so the
  // onboarding flow surfaces the issue rather than the boot logs.
  unawaited(() async {
    if (initialRoute != '/') return;
    try {
      await container.read(realGemmaServiceProvider).warmUpE2B();
    } on ModelMissingException catch (e) {
      debugPrint(
          '[main] Gemma warm-up skipped — model missing ($e); '
          'onboarding banner will surface.');
    } catch (e) {
      debugPrint('[main] Gemma warm-up failed (continuing): $e');
    }
  }());

  // Step 7 — Boot the classification worker. PENDING rows that exist on
  // disk get drained, future submissions stream in via watchPending().
  unawaited(() async {
    try {
      await container.read(classificationWorkerProvider.future);
    } catch (e, st) {
      debugPrint('[main] classification worker boot failed: $e\n$st');
    }
  }());

  unawaited(() async {
    try {
      await container.read(realReputationSyncProvider.future);
    } catch (e, st) {
      debugPrint('[main] reputation sync boot failed: $e\n$st');
    }
  }());

  unawaited(() async {
    try {
      await container.read(realProximityAlertServiceProvider.future);
    } catch (e, st) {
      debugPrint('[main] proximity alert boot failed: $e\n$st');
    }
  }());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: SafeRouteApp(initialRoute: initialRoute),
    ),
  );
}

class SafeRouteApp extends ConsumerWidget {
  const SafeRouteApp({super.key, this.initialRoute = '/'});

  final String initialRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeNotifierProvider);
    return MaterialApp.router(
      title: 'Safe Route',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: buildAppRouter(initialLocation: initialRoute),
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
