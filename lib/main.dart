import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';
import 'core/services/cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/recovery_screens.dart';
import 'shared/providers/core_providers.dart';
import 'shared/providers/profile_providers.dart';

/// Startup.
///
/// Services that need an await — the cache and connectivity — are created here
/// and injected as provider overrides rather than looked up lazily. That keeps
/// providers synchronous and makes them trivially replaceable in tests.
Future<void> main() async {
  // Caught here so a failure in a plugin or in Firebase initialisation shows a
  // readable screen instead of a grey one.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _configureLogging();

      if (!AppConfig.isConfigured) {
        runApp(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: ConfigurationErrorScreen(missing: AppConfig.configurationHint),
          ),
        );
        return;
      }

      final cache = await CacheService.create();
      final connectivity = ConnectivityService();
      await connectivity.initialise();

      try {
        await FirebaseService.initialise();
      } on Object catch (error, stack) {
        Logger('main').severe('Firebase initialisation failed', error, stack);
        runApp(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: const _StartupFailureScreen(),
          ),
        );
        return;
      }

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        Logger('flutter').severe(
          details.exceptionAsString(),
          details.exception,
          details.stack,
        );
      };

      runApp(
        ProviderScope(
          overrides: [
            cacheServiceProvider.overrideWithValue(cache),
            connectivityServiceProvider.overrideWithValue(connectivity),
          ],
          child: const FinoraApp(),
        ),
      );
    },
    (error, stack) => Logger('uncaught').severe('Uncaught error', error, stack),
  );
}

void _configureLogging() {
  // Verbose in debug, warnings only in release. Nothing is sent anywhere: log
  // records can contain storage paths and provider detail, and shipping those
  // off-device is not something a finance app should do silently.
  Logger.root.level = kDebugMode ? Level.INFO : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    if (!kDebugMode && record.level < Level.WARNING) return;
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}'
      '${record.error == null ? '' : '\n${record.error}'}',
    );
  });
}

class FinoraApp extends ConsumerWidget {
  const FinoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        // Caps text scaling. Finance screens are dense with figures, and beyond
        // about 1.4x the layouts stop being readable rather than more readable.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(1).clamp(0.85, 1.4),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48),
              const SizedBox(height: 20),
              Text(
                "Finora couldn't start",
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'We could not reach the server. Check your connection and '
                'reopen the app.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
