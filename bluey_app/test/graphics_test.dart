import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/graphics/blob_shape.dart';
import 'package:bluey_app/graphics/cursor_overlay_graphics.dart';
import 'package:bluey_app/graphics/face_animator.dart';

void main() {
  group('Graphics & Physics Tests', () {
    test('BlobShape path bounds match rect', () {
      final rect = const Rect.fromLTWH(0, 0, 100, 100);
      final path = BlobShape.path(rect);
      final bounds = path.getBounds();

      expect(bounds.left, equals(0));
      expect(bounds.top, equals(0));
      expect(bounds.width, equals(100));
      expect(bounds.height, equals(100));
    });

    test('Crown path bounds match bounding rect', () {
      final rect = const Rect.fromLTWH(10, 10, 60, 40);
      final crownPath = Crown.path(rect);
      final bounds = crownPath.getBounds();

      expect(bounds.left, greaterThanOrEqualTo(10));
      expect(bounds.top, greaterThanOrEqualTo(10));
      expect(bounds.right, lessThanOrEqualTo(70));
      expect(bounds.bottom, lessThanOrEqualTo(50));
    });

    test('Spring physics step calculation', () {
      final spring = Spring(0, stiffness: 200, damping: 0.7);
      spring.step(100, 0.016); // 16ms frame step

      expect(spring.value, greaterThan(0));
      expect(spring.velocity, greaterThan(0));
    });

    test('TimingCurve cubic bezier flight values', () {
      const curve = TimingCurve.launch;
      expect(curve.value(0.0), equals(0.0));
      expect(curve.value(1.0), equals(1.0));
      expect(curve.value(0.5), greaterThan(0.0));
      expect(curve.value(0.5), lessThan(1.0));
    });

    test('TeardropPath star and teardrop paths non-empty', () {
      final teardrop = TeardropPath.path(size: 72, tipRadius: 6);
      expect(teardrop.getBounds().isEmpty, isFalse);

      final star = TeardropPath.star(radius: 10);
      expect(star.getBounds().isEmpty, isFalse);
    });
  });
}
