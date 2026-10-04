import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/server.dart';
import '../services/ping_service.dart';
import '../services/source_service.dart';
import '../services/vpn_service.dart';
import 'widgets.dart';

enum SortMode { ping, name, protocol }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final vpn = VpnService();
  final sources = SourceService();
  List<VpnServer> all = [];
  String? selectedId;
  String filter = 'all';
  SortMode sort = SortMode.ping;
  bool loading = false, pinging = false, _cancelPing = false;
  int pingDone = 0;

  static const filters = ['all', 'vless', 'vmess', 'trojan', 'ss'];

  @override
  void initState() {
    super.initState();
    vpn.init();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final c = await sources.loadCache();
    if (c.isNotEmpty) {
      setState(() => all = c);
    } else {
      _refresh();
    }
  }

  List<VpnServer> get visible {
    final l = all.where((s) => filter == 'all' || s.protocol == filter).toList();
    switch (sort) {
      case SortMode.ping:
        l.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      case SortMode.name:
        l.sort((a, b) => a.remark.compareTo(b.remark));
      case SortMode.protocol:
        l.sort((a, b) => a.protocol.compareTo(b.protocol));
    }
    return l;
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));

  Future<void> _refresh() async {
    if (loading) return;
    setState(() => loading = true);
    final list = await sources.fetchAll();
    if (!mounted) return;
    setState(() {
      loading = false;
      if (list.isNotEmpty) all = list;
    });
    await sources.saveCache(all);
    _snack(list.isEmpty
        ? 'هیچ سروری دریافت نشد، اینترنت یا منابع رو چک کن'
        : '${list.length} سرور رایگان دریافت شد');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final found = SourceService.parseText(data?.text ?? '');
    if (found.isEmpty) return _snack('کانفیگ معتبری توی کلیپ‌بورد نبود');
    setState(() => all = SourceService.dedupe([...found, ...all]));
    await sources.saveCache(all);
    _snack('${found.length} کانفیگ اضافه شد');
  }

  Future<void> _pingAll() async {
    if (pinging) {
      _cancelPing = true;
      return;
    }
    if (all.isEmpty) return;
    setState(() {
      pinging = true;
      _cancelPing = false;
      pingDone = 0;
      for (final s in all) {
        s.tcpPing = null;
        s.realPing = null;
      }
    });
    await PingService.pingAll(all,
        cancelled: () => _cancelPing,
        onProgress: (d) {
          if (mounted && (d % 15 == 0 || d == all.length)) setState(() => pingDone = d);
        });
    // real delay through the core for the fastest ones
    final top = all.where((s) => (s.tcpPing ?? -1) > 0).toList()
      ..sort((a, b) => a.tcpPing!.compareTo(b.tcpPing!));
    for (final s in top.take(20)) {
      if (_cancelPing) break;
      s.realPing = await vpn.realDelay(s);
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() {
      pinging = false;
      sort = SortMode.ping;
    });
    _snack('${all.where((s) => s.alive).length} سرور زنده پیدا شد');
  }

  Future<void> _toggle() async {
    if (vpn.connState != ConnState.off) {
      await vpn.disconnect();
      return;
    }
    VpnServer? target;
    for (final s in all) {
      if (s.id == selectedId) target = s;
    }
    if (target == null) {
      final v = visible;
      if (v.isEmpty) return _snack('اول لیست سرورها رو بگیر');
      target = v.first; // best ping after sorting
      setState(() => selectedId = target!.id);
    }
    final ok = await vpn.connect(target);
    if (!ok) _snack('اتصال انجام نشد (مجوز VPN یا کانفیگ خراب)');
  }

  String _speed(int b) {
    if (b < 1024) return '$b B/s';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = visible;
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: vpn,
            builder: (context, _) {
              final st = vpn.connState;
              final aliveCount = all.where((s) => s.alive).length;
              final f0 = list.isNotEmpty && list.first.alive ? list.first : null;
              final best = f0 == null ? null : ((f0.realPing ?? -1) > 0 ? f0.realPing : f0.tcpPing);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(child: _header(cs).animate().fadeIn(duration: 500.ms).slideY(begin: -0.3)),
                    SliverToBoxAdapter(
                      child: Center(child: ConnectButton(state: st, onTap: _toggle))
                          .animate().scale(duration: 700.ms, curve: Curves.easeOutBack),
                    ),
                    SliverToBoxAdapter(child: _statusText(st, cs)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Column(children: [
                          Row(children: [
                            Expanded(child: StatTile(icon: Icons.south_rounded, label: 'دانلود', value: _speed(vpn.status.downloadSpeed), color: Colors.lightBlueAccent)),
                            const SizedBox(width: 10),
                            Expanded(child: StatTile(icon: Icons.north_rounded, label: 'آپلود', value: _speed(vpn.status.uploadSpeed), color: Colors.pinkAccent)),
                            const SizedBox(width: 10),
                            Expanded(child: StatTile(icon: Icons.timer_rounded, label: 'زمان اتصال', value: vpn.status.duration, color: Colors.amberAccent)),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: StatTile(icon: Icons.dns_rounded, label: 'کل سرورها', value: '${all.length}')),
                            const SizedBox(width: 10),
                            Expanded(child: StatTile(icon: Icons.favorite_rounded, label: 'سرور زنده', value: '$aliveCount', color: Colors.greenAccent)),
                            const SizedBox(width: 10),
                            Expanded(child: StatTile(icon: Icons.speed_rounded, label: 'بهترین پینگ', value: best == null ? '-' : '$best ms', color: cs.tertiary)),
                          ]),
                        ]).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.2),
                      ),
                    ),
                    SliverToBoxAdapter(child: _toolbar(cs)),
                    if (loading || pinging) SliverToBoxAdapter(child: _progress(cs)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (c, i) => _serverTile(list[i], i, cs),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShaderMask(
                shaderCallback: (r) => LinearGradient(colors: [cs.primary, cs.tertiary]).createShader(r),
                child: const Text('FreeVPN',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Text('سرورهای رایگان تلگرام و اینترنت',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          IconButton.filledTonal(
              onPressed: _pasteFromClipboard,
              tooltip: 'افزودن از کلیپ‌بورد',
              icon: const Icon(Icons.content_paste_rounded)),
          const SizedBox(width: 6),
          IconButton.filledTonal(
              onPressed: _openSettings,
              tooltip: 'منابع سرور',
              icon: const Icon(Icons.tune_rounded)),
        ]),
      );

  Widget _statusText(ConnState st, ColorScheme cs) {
    final text = switch (st) {
      ConnState.on => 'متصل به ${vpn.current?.remark ?? ''}',
      ConnState.connecting => 'در حال اتصال...',
      ConnState.off => 'برای اتصال ضربه بزن',
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Text(text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
    );
  }

  Widget _toolbar(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: loading ? null : _refresh,
                icon: const Icon(Icons.cloud_download_rounded),
                label: const Text('دریافت سرورها'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _pingAll,
                icon: Icon(pinging ? Icons.stop_rounded : Icons.network_ping_rounded),
                label: Text(pinging ? 'توقف' : 'تست پینگ'),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<SortMode>(
              tooltip: 'مرتب‌سازی',
              icon: const Icon(Icons.sort_rounded),
              initialValue: sort,
              onSelected: (m) => setState(() => sort = m),
              itemBuilder: (_) => const [
                PopupMenuItem(value: SortMode.ping, child: Text('بر اساس پینگ')),
                PopupMenuItem(value: SortMode.name, child: Text('بر اساس نام')),
                PopupMenuItem(value: SortMode.protocol, child: Text('بر اساس پروتکل')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(f == 'all' ? 'همه' : f.toUpperCase()),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _progress(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: pinging && all.isNotEmpty ? pingDone / all.length : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(pinging ? 'پینگ $pingDone از ${all.length}' : 'در حال جمع‌آوری سرورها...',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ).animate().fadeIn();

  Widget _serverTile(VpnServer s, int i, ColorScheme cs) {
    final sel = s.id == selectedId;
    final connected = vpn.connState == ConnState.on && vpn.current?.id == s.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        blur: false,
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        tint: sel ? cs.primaryContainer : null,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => selectedId = s.id);
        },
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: s.link));
          _snack('کانفیگ کپی شد');
        },
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: connected ? Colors.greenAccent.withOpacity(.25) : cs.primary.withOpacity(.18),
            ),
            alignment: Alignment.center,
            child: Text(s.protocol.toUpperCase().substring(0, s.protocol.length.clamp(0, 3)),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11,
                    color: connected ? Colors.greenAccent : cs.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.remark, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${s.host}:${s.port}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          PingBadge(tcp: s.tcpPing, real: s.realPing),
        ]),
      ),
    )
        .animate(key: ValueKey(s.id))
        .fadeIn(duration: 350.ms, delay: ((i % 12) * 35).ms)
        .slideX(begin: 0.15, curve: Curves.easeOutCubic);
  }

  void _openSettings() async {
    final ctrl = TextEditingController(text: (await sources.loadSources()).join('\n'));
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('منابع سرور (هر خط یک لینک subscription)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 8,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => ctrl.text = SourceService.defaultSources.join('\n'),
                child: const Text('پیش‌فرض'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final list = ctrl.text.split('\n').map((e) => e.trim()).where((e) => e.startsWith('http')).toList();
                  await sources.saveSources(list);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                },
                child: const Text('ذخیره و دریافت'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
