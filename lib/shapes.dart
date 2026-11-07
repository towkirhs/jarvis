import 'dart:math';

import 'package:flutter/material.dart';

/// Material 3 Expressive-style geometric shapes, drawn as smooth polar curves: a scalloped "cookie" for
/// feature icons, a four-leaf "clover" for decisions, a "burst" for achievements. Used sparingly, as
/// containers for icons that mark what kind of thing you are looking at.
class Lobed extends ShapeBorder {
  const Lobed({required this.lobes, required this.depth, this.turn = 0});

  /// How many bumps around the edge, and how deep they go (0 is a circle, 0.3 is very wavy).
  final int lobes;
  final double depth;

  /// Rotation, in fractions of a full turn.
  final double turn;

  static const cookie = Lobed(lobes: 9, depth: 0.09);
  static const clover = Lobed(lobes: 4, depth: 0.28, turn: 0.125);
  static const burst = Lobed(lobes: 12, depth: 0.16);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final c = rect.center;
    final r = rect.shortestSide / 2;
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final a = 2 * pi * i / steps;
      // Peaks touch the bounds; valleys sit [depth] of the radius inside.
      final k = r * (1 - depth * (1 - cos(lobes * a)) / 2);
      final p = Offset(c.dx + k * cos(a + 2 * pi * turn), c.dy + k * sin(a + 2 * pi * turn));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// An icon inside a tinted geometric shape.
class ShapeIcon extends StatelessWidget {
  const ShapeIcon(this.icon, {super.key, this.shape = Lobed.cookie, this.color, this.size = 40, this.child});
  final IconData icon;
  final ShapeBorder shape;
  final Color? color;
  final double size;

  /// Shown instead of the icon, like a number on a badge.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(shape: shape, color: c.withValues(alpha: 0.16)),
      child: child ?? Icon(icon, size: size * 0.5, color: c),
    );
  }
}
