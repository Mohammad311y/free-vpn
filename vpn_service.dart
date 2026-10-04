import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/server.dart';
import '../ui/widgets.dart';

/// Wraps the Xray core shipped by flutter_v2ray.
class VpnService extends ChangeNotifier {
  late final FlutterV2ray _v2ray = FlutterV2ray(onStatusChanged: (s) {
    status = s;
    if (s.state == 'CONNECTED' || s.state == 'DISCONNECTED') _connecting = false;
    notifyListeners();
  });

  V2RayStatus status = V2RayStatus();
  bool _connecting = false;
  VpnServer? current;

  Future<void> init() => _v2ray.initializeV2Ray();

  ConnState get connState {
    if (status.state == 'CONNECTED') return ConnState.on;
    if (_connecting) return ConnState.connecting;
    return ConnState.off;
  }

  Future<bool> connect(VpnServer s) async {
    try {
      final parsed = FlutterV2ray.parseFromURL(s.link);
      if (!await _v2ray.requestPermission()) return false;
      _connecting = true;
      current = s;
      notifyListeners();
      await _v2ray.startV2Ray(
        remark: parsed.remark,
        config: parsed.getFullConfiguration(),
        proxyOnly: false,
      );
      Future.delayed(const Duration(seconds: 15), () {
        if (_connecting) {
          _connecting = false;
          notifyListeners();
        }
      });
      return true;
    } catch (_) {
      _connecting = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _connecting = false;
    await _v2ray.stopV2Ray();
    notifyListeners();
  }

  /// Real delay: runs the config through the core and hits generate_204.
  Future<int> realDelay(VpnServer s) async {
    try {
      final p = FlutterV2ray.parseFromURL(s.link);
      return await _v2ray.getServerDelay(config: p.getFullConfiguration());
    } catch (_) {
      return -1;
    }
  }
}
