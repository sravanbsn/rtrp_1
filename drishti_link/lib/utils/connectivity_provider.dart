import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

/// Global connectivity provider for monitoring network status
/// Shows 'No Internet' snackbar when connection is lost
class ConnectivityProvider extends ChangeNotifier {
  static final ConnectivityProvider _instance =
      ConnectivityProvider._internal();
  factory ConnectivityProvider() => _instance;
  ConnectivityProvider._internal();

  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  bool _isShowingOfflineMessage = false;

  ConnectivityResult get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus != ConnectivityResult.none;
  bool get isShowingOfflineMessage => _isShowingOfflineMessage;

  /// Initialize connectivity monitoring
  void initialize() {
    // Check initial connection status
    _checkInitialConnection();

    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      _connectionStatus = result;
      notifyListeners();

      // Show/hide offline message based on connection status
      _handleConnectionChange(result);
    });
  }

  /// Check initial connection status
  Future<void> _checkInitialConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _connectionStatus = result;
      notifyListeners();
    } catch (e) {
      // Default to connected if check fails
      _connectionStatus = ConnectivityResult.wifi;
      notifyListeners();
    }
  }

  /// Handle connection changes and show appropriate messages
  void _handleConnectionChange(ConnectivityResult result) {
    if (result == ConnectivityResult.none) {
      _showOfflineMessage();
    } else {
      _hideOfflineMessage();
    }
  }

  /// Show 'No Internet' snackbar
  void _showOfflineMessage() {
    if (!_isShowingOfflineMessage) {
      _isShowingOfflineMessage = true;
      notifyListeners();

      // Get current context (this needs to be called from a widget context)
      final context = _currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text(
                  'No Internet Connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  /// Hide offline message
  void _hideOfflineMessage() {
    if (_isShowingOfflineMessage) {
      _isShowingOfflineMessage = false;
      notifyListeners();

      // Hide any existing snackbars
      final context = _currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    }
  }

  /// Store current context for showing snackbars
  BuildContext? _currentContext;

  /// Set context for showing connectivity messages
  void setContext(BuildContext context) {
    _currentContext = context;
  }

  /// Clear context when widget is disposed
  void clearContext() {
    _currentContext = null;
  }

  /// Get user-friendly connection status text
  String get connectionStatusText {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return 'Connected to WiFi';
      case ConnectivityResult.mobile:
        return 'Connected to Mobile Data';
      case ConnectivityResult.ethernet:
        return 'Connected to Ethernet';
      case ConnectivityResult.bluetooth:
        return 'Connected via Bluetooth';
      case ConnectivityResult.none:
        return 'No Internet Connection';
      default:
        return 'Unknown Connection Status';
    }
  }

  /// Get connection icon based on status
  IconData get connectionIcon {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return Icons.wifi;
      case ConnectivityResult.mobile:
        return Icons.signal_cellular_alt;
      case ConnectivityResult.ethernet:
        return Icons.settings_ethernet;
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth;
      case ConnectivityResult.none:
        return Icons.wifi_off;
      default:
        return Icons.device_hub;
    }
  }

  /// Check if connection is suitable for navigation
  bool get isSuitableForNavigation {
    return isConnected && _connectionStatus != ConnectivityResult.bluetooth;
  }
}

/// Mixin to easily access connectivity provider
mixin ConnectivityMixin<T extends StatefulWidget> on State<T> {
  late ConnectivityProvider _connectivity;

  @override
  void initState() {
    super.initState();
    _connectivity = Provider.of<ConnectivityProvider>(context, listen: false);
    _connectivity.setContext(context);
  }

  @override
  void dispose() {
    _connectivity.clearContext();
    super.dispose();
  }

  /// Check if connected before performing network operations
  bool get isConnected => _connectivity.isConnected;

  /// Show connectivity status
  String get connectionStatus => _connectivity.connectionStatusText;

  /// Check if suitable for navigation
  bool get isSuitableForNavigation => _connectivity.isSuitableForNavigation;
}
