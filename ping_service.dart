import 'dart:io';
import '../models/server.dart';

class PingService {
  static Future<int> tcpPing(String host, int port,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Pings every server with a bounded worker pool.
  static Future<void> pingAll(List<VpnServer> servers,
      {int concurrency = 48,
      void Function(int done)? onProgress,
      bool Function()? cancelled}) async {
    var index = 0, done = 0;
    Future<void> worker() async {
      while (index < servers.length) {
        if (cancelled?.call() ?? false) return;
        final s = servers[index++];
        s.tcpPing = await tcpPing(s.host, s.port);
        onProgress?.call(++done);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
  }
}
