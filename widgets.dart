import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ConnState { off, connecting, on }

/// Slowly drifting colour blobs behind everything.
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  const AnimatedBackground({super.key, required this.child});
  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => CustomPaint(
        painter: _BlobPainter(_c.value, [cs.primary, cs.tertiary, cs.secondary], cs.surface),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final Color bg;
  _BlobPainter(this.t, this.colors, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    for (var i = 0; i < colors.length; i++) {
      final a = 2 * pi * (t + i / colors.length);
      final c = Offset(size.width * (0.5 + 0.38 * cos(a * (i + 1))),
          size.height * (0.35 + 0.3 * sin(a + i)));
      final r = size.width * (0.6 + 0.12 * sin(a * 2));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              colors[i].withOpacity(0.38),
              colors[i].withOpacity(0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter o) => o.t != t;
}

/// Android-widget-like rounded tile (optionally frosted glass).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool blur;
  final Color? tint;
  final VoidCallback? onTap, onLongPress;
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.radius = 28,
      this.blur = true,
      this.tint,
      this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final br = BorderRadius.circular(radius);
    Widget body = Material(
      color: (tint ?? cs.surfaceContainerHighest).withOpacity(blur ? 0.42 : 0.6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: padding,
          decoration: BoxDecoration(
              borderRadius: br,
              border: Border.all(color: Colors.white.withOpacity(0.08))),
          child: child,
        ),
      ),
    );
    if (blur) {
      body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body);
    }
    return ClipRRect(borderRadius: br, child: body);
  }
}

/// Big pulsing power button.
class ConnectButton extends StatefulWidget {
  final ConnState state;
  final VoidCallback onTap;
  const ConnectButton({super.key, required this.state, required this.onTap});
  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = widget.state;
    final color = switch (st) {
      ConnState.on => Colors.greenAccent.shade400,
      ConnState.connecting => cs.tertiary,
      ConnState.off => cs.primary,
    };
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: SizedBox(
        width: 230,
        height: 230,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _RingsPainter(_c.value, color, st != ConnState.off),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutBack,
                width: st == ConnState.on ? 146 : 130,
                height: st == ConnState.on ? 146 : 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, Color.lerp(color, Colors.black, 0.4)!],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(0.35 + 0.25 * sin(_c.value * 2 * pi).abs()),
                        blurRadius: 45,
                        spreadRadius: 4)
                  ],
                ),
                child: Center(
                  child: st == ConnState.connecting
                      ? Transform.rotate(
                          angle: _c.value * 4 * pi,
                          child: const Icon(Icons.autorenew_rounded, size: 58, color: Colors.white))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          transitionBuilder: (c, a) => ScaleTransition(
                              scale: a, child: RotationTransition(turns: a, child: c)),
                          child: Icon(
                            st == ConnState.on
                                ? Icons.shield_rounded
                                : Icons.power_settings_new_rounded,
                            key: ValueKey(st),
                            size: 58,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool active;
  _RingsPainter(this.t, this.color, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (!active) {
      final r = 78 + 4 * sin(t * 2 * pi);
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withOpacity(0.35));
      return;
    }
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(c, 66 + p * 48, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - p) + 0.5
        ..color = color.withOpacity((1 - p) * 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter o) => true;
}

class PingBadge extends StatelessWidget {
  final int? tcp, real;
  const PingBadge({super.key, this.tcp, this.real});

  @override
  Widget build(BuildContext context) {
    final useReal = real != null && real! > 0;
    final ms = useReal ? real : tcp;
    Color c;
    String label;
    if (ms == null) {
      c = Colors.grey;
      label = '•••';
    } else if (ms < 0) {
      c = Colors.redAccent;
      label = 'timeout';
    } else {
      c = ms < 300
          ? Colors.greenAccent
          : ms < 800
              ? Colors.amberAccent
              : Colors.orangeAccent;
      label = '$ms ms';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (useReal) Icon(Icons.bolt_rounded, size: 14, color: c),
        Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? color;
  const StatTile(
      {super.key, required this.icon, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: (color ?? cs.primary).withOpacity(0.2), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color ?? cs.primary),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                  position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a),
                  child: c)),
          child: Text(value,
              key: ValueKey(value),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
