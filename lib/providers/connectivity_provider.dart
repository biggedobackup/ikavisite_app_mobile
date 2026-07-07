import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isConnected = true;

  ConnectivityProvider() {
    _init();
  }

  bool get isConnected => _isConnected;

  void _init() {
    _connectivity.checkConnectivity().then((results) {
      _isConnected = !results.contains(ConnectivityResult.none);
      notifyListeners();
    });

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _isConnected = !results.contains(ConnectivityResult.none);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
