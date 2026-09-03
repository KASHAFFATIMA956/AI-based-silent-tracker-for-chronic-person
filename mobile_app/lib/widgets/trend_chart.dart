import 'package:flutter/material.dart';

class TrendPoint {
  TrendPoint(this.timestamp, this.value);
  final DateTime timestamp;
  final double value;
}

/// A minimal hand-rolled line chart — no new charting package dependency,
/// in the same spirit as the web prototype's own hand-drawn SVG polylines
/// (`RozNoor.dc.html`'s d-detail Sleep/Weight cards). Renders a patient's
/// actual recorded values over time, chronologically ordered by the
/// caller. See PatientDetailScreen's own note on why this isn't a shaded
/// baseline band like the prototype's: no endpoint exposes
/// `baseline_history`'s min/max — see context/api-contracts.md.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, required this.lineColor});

  final List<TrendPoint> points;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(
        points: points,
        lineColor: lineColor,
        dotFillColor: Theme.of(context).cardColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.lineColor, required this.dotFillColor});

  final List<TrendPoint> points;
  final Color lineColor;
  final Color dotFillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minVal = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() < 0.001 ? 1.0 : (maxVal - minVal);
    const padding = 8.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    Offset offsetFor(int i) {
      final x = padding + w * i / (points.length - 1);
      final y = padding + h - ((points[i].value - minVal) / range) * h;
      return Offset(x, y);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.75
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = offsetFor(i);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotFill = Paint()..color = dotFillColor;
    final dotStroke = Paint()
      ..color = lineColor
      ..strokeWidth = 1.75
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final o = offsetFor(i);
      canvas.drawCircle(o, 3.5, dotFill);
      canvas.drawCircle(o, 3.5, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor;
  }
}
