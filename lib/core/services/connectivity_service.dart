import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';

final _log = Logger('Connectivity');

/// Tracks whether the device has a network path.
///
/// `connectivity_plus` reports the presence of an interface, not real
/// reachability, so this is used to decide when to *prefer* the cache and when
/// to queue a write — never as proof that a request will succeed. Requests are
/// still attempted and their failures still handled.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = true;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  /// Emits whenever the online state flips.
  Stream<bool> get onStatusChange => _controller.stream;

  Future<void> initialise() async {
    try {
      _isOnline = _evaluate(await _connectivity.checkConnectivity());
    } on Object catch (error, stack) {
      // A platform without the plugin (e.g. a unit test host) should behave as
      // if online rather than blocking every request.
      _log.fine('Connectivity check failed; assuming online', error, stack);
      _isOnline = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final next = _evaluate(results);
        if (next != _isOnline) {
          _isOnline = next;
          _log.info('Connectivity changed: ${next ? 'online' : 'offline'}');
          _controller.add(next);
        }
      },
      onError: (Object error) => _log.fine('Connectivity stream error', error),
    );
  }

  static bool _evaluate(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
