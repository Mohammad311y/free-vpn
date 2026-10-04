import 'dart:convert';

String normalizeB64(String s) {
  s = s.replaceAll(RegExp(r'\s'), '').replaceAll('-', '+').replaceAll('_', '/');
  while (s.length % 4 != 0) {
    s += '=';
  }
  return s;
}

class VpnServer {
  final String link;
  final String protocol;
  final String remark;
  final String host;
  final int port;
  int? tcpPing; // ms, -1 = unreachable
  int? realPing; // ms through the core, -1 = failed

  VpnServer({
    required this.link,
    required this.protocol,
    required this.remark,
    required this.host,
    required this.port,
  });

  String get id => '$protocol|$host|$port|${link.hashCode}';

  /// real-tested working > tcp-only > real-failed > dead
  int get sortKey {
    final r = realPing, t = tcpPing;
    if (r != null && r > 0) return r;
    if (t != null && t > 0) return (r == -1) ? t + 100000 : t + 2000;
    return 1 << 30;
  }

  bool get alive => sortKey < (1 << 30);

  static VpnServer? tryParse(String raw) {
    final link = raw.trim();
    if (!link.contains('://')) return null;
    final scheme = link.split('://').first.toLowerCase();
    try {
      VpnServer? s;
      switch (scheme) {
        case 'vmess':
          final body = link.substring(8).split('#').first;
          final j = jsonDecode(utf8.decode(base64.decode(normalizeB64(body))))
              as Map<String, dynamic>;
          s = VpnServer(
            link: link,
            protocol: 'vmess',
            remark: (j['ps'] ?? '').toString(),
            host: j['add'].toString(),
            port: int.parse(j['port'].toString()),
          );
          break;
        case 'vless':
        case 'trojan':
          final u = Uri.parse(link);
          s = VpnServer(
            link: link,
            protocol: scheme,
            remark: Uri.decodeComponent(u.fragment),
            host: u.host,
            port: u.port,
          );
          break;
        case 'ss':
          var u = Uri.parse(link);
          if (u.host.isEmpty) {
            final body = link.substring(5).split('#').first;
            u = Uri.parse('ss://${utf8.decode(base64.decode(normalizeB64(body)))}');
          }
          s = VpnServer(
            link: link,
            protocol: 'ss',
            remark: Uri.decodeComponent(Uri.parse(link).fragment),
            host: u.host,
            port: u.port,
          );
          break;
      }
      if (s == null || s.host.isEmpty || s.port <= 0) return null;
      if (s.remark.trim().isEmpty) {
        return VpnServer(
            link: s.link,
            protocol: s.protocol,
            remark: '${s.protocol.toUpperCase()} ${s.host}',
            host: s.host,
            port: s.port);
      }
      return s;
    } catch (_) {
      return null;
    }
  }
}
