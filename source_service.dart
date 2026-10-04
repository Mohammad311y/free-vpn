import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server.dart';

class SourceService {
  /// Public subscription lists. Several of them are auto-collected from
  /// Telegram channels. Editable from the settings sheet inside the app.
  static const defaultSources = <String>[
    'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/splitted/mixed',
    'https://raw.githubusercontent.com/yebekhe/TelegramV2rayCollector/main/sub/normal/mix',
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub1.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub1.txt',
    'https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge.txt',
    'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt',
  ];

  static const perSourceLimit = 400;
  static const _kSources = 'sources';
  static const _kCache = 'servers_cache';

  Future<List<String>> loadSources() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kSources) ?? defaultSources;
  }

  Future<void> saveSources(List<String> s) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSources, s);
  }

  Future<List<VpnServer>> loadCache() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kCache) ?? [])
        .map(VpnServer.tryParse)
        .whereType<VpnServer>()
        .toList();
  }

  Future<void> saveCache(List<VpnServer> servers) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCache, servers.map((e) => e.link).toList());
  }

  static List<VpnServer> parseText(String body) {
    if (!body.contains('://')) {
      try {
        body = utf8.decode(base64.decode(normalizeB64(body)), allowMalformed: true);
      } catch (_) {}
    }
    return body
        .split(RegExp(r'[\r\n\s]+'))
        .map(VpnServer.tryParse)
        .whereType<VpnServer>()
        .toList();
  }

  Future<List<VpnServer>> _fetchOne(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      return parseText(utf8.decode(res.bodyBytes, allowMalformed: true))
          .take(perSourceLimit)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<VpnServer> dedupe(Iterable<VpnServer> list) {
    final seen = <String>{};
    return list.where((s) => seen.add('${s.protocol}|${s.host}|${s.port}')).toList();
  }

  Future<List<VpnServer>> fetchAll() async {
    final sources = await loadSources();
    final results = await Future.wait(sources.map(_fetchOne));
    return dedupe(results.expand((e) => e));
  }
}
