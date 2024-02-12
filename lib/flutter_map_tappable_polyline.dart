// ignore_for_file: overridden_fields, avoid_dynamic_calls

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A polyline with a tag
class TaggedPolyline extends Polyline {
  TaggedPolyline({
    required super.points,
    super.strokeWidth = 1.0,
    super.color = const Color(0xFF00FF00),
    super.borderStrokeWidth = 0.0,
    super.borderColor = const Color(0xFFFFFF00),
    super.gradientColors,
    super.colorsStop,
    super.isDotted = false,
    this.tag,
  });

  /// The name of the polyline
  final String? tag;
}

class TappablePolylineLayer extends PolylineLayer {
  const TappablePolylineLayer({
    this.polylines = const [],
    this.onTap,
    this.onMiss,
    this.pointerDistanceTolerance = 15,
    this.distance = const Distance(),
    super.polylineCulling,
    super.key,
  }) : super(polylines: polylines);
  final Distance distance;

  /// The list of [TaggedPolyline] which could be tapped
  @override
  final List<TaggedPolyline> polylines;

  /// The tolerated distance between pointer and
  /// user tap to trigger the [onTap] callback
  final double pointerDistanceTolerance;

  /// The callback to call when a polyline was hit by the tap
  final void Function(List<TaggedPolyline>, TapUpDetails tapPosition)? onTap;

  /// The optional callback to call when no polyline was hit by the tap
  final void Function(TapUpDetails tapPosition)? onMiss;

  @override
  Widget build(BuildContext context) {
    final mapCamera = MapCamera.of(context);

    return _build(
      context,
      Size(mapCamera.size.x, mapCamera.size.y),
      polylineCulling
          ? polylines
              .where(
                (p) => p.boundingBox.isOverlapping(mapCamera.visibleBounds),
              )
              .toList()
          : polylines,
    );
  }

  Widget _build(BuildContext context, Size size, List<TaggedPolyline> lines) {
    final mapState = MapCamera.of(context);

    return MobileLayerTransformer(
      child: GestureDetector(
        onDoubleTap: () {
          // For some strange reason i have to add this callback
          // for the onDoubleTapDown callback to be called.
        },
        onDoubleTapDown: (TapDownDetails details) {
          _zoomMap(details, context);
        },
        onTapUp: (TapUpDetails details) {
          _forwardCallToMapOptions(details, context);
          _handlePolylineTap(details, onTap, onMiss, mapState);
        },
        child: CustomPaint(
          painter: PolylinePainter(lines, mapState),
          size: size,
        ),
      ),
    );
  }

  List<Offset> getOffsets(
    Offset origin,
    List<LatLng> points,
    MapCamera mapState,
  ) =>
      List.generate(
        points.length,
        (index) => getOffset(origin, points[index], mapState),
        growable: false,
      );
  Offset getOffset(Offset origin, LatLng point, MapCamera mapState) {
    // Critically create as little garbage as possible.
    // This is called on every frame.
    final projected = mapState.project(point, mapState.zoom);
    return Offset(projected.x - origin.dx, projected.y - origin.dy);
  }

  double getSqSegDist(
    double px,
    double py,
    double x0,
    double y0,
    double x1,
    double y1,
  ) {
    var dx = x1 - x0;
    var dy = y1 - y0;
    if (dx != 0 || dy != 0) {
      final t = ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy);
      if (t > 1) {
        dx = px - x1;
        dy = py - y1;
        return dx * dx + dy * dy;
      } else if (t > 0) {
        dx = px - (x0 + dx * t);
        dy = py - (y0 + dy * t);
        return dx * dx + dy * dy;
      }
    }

    dx = px - x0;
    dy = py - y0;

    return dx * dx + dy * dy;
  }

  void _handlePolylineTap(
    TapUpDetails details,
    Function? onTap,
    Function? onMiss,
    MapCamera mapState,
  ) {
    // We might hit close to multiple polylines. We will therefore
    // keep a reference to these in this map.
    final candidates = <double, List<TaggedPolyline>>{};

    // Calculating taps in between points on the polyline. We
    // iterate over all the segments in the polyline to find any
    // matches with the tapped point within the
    // pointerDistanceTolerance.
    for (final polyline in polylines) {
      final origin =
          mapState.project(mapState.center, mapState.zoom).toOffset() -
              mapState.size.toOffset() / 2;

      final offsets = getOffsets(origin, polyline.points, mapState);

      for (var i = 0; i < offsets.length - 1; i++) {
        final o1 = offsets[i];
        final o2 = offsets[i + 1];
        final distance = sqrt(
          getSqSegDist(
            details.localPosition.dx,
            details.localPosition.dy,
            o1.dx,
            o1.dy,
            o2.dx,
            o2.dy,
          ),
        );
        if (distance > pointerDistanceTolerance) continue;
        if (candidates.containsKey(distance)) {
          candidates[distance]!.add(polyline);
        } else {
          candidates[distance] = [polyline];
        }
      }
    }

    if (candidates.isEmpty) {
      return;
    }

    // We look up in the map of distances to the tap,
    // and choose the shortest one.
    final closestToTapKey = candidates.keys.reduce(min);
    onTap!(candidates[closestToTapKey], details);
  }

  // ignore: unused_element
  double _metersToStrokeWidth(
    Offset origin,
    LatLng p0,
    Offset o0,
    double strokeWidthInMeters,
    MapCamera mapState,
  ) {
    final r = distance.offset(p0, strokeWidthInMeters, 180);
    final delta = o0 - getOffset(origin, r, mapState);
    return delta.distance;
  }

  void _forwardCallToMapOptions(TapUpDetails details, BuildContext context) {
    final latlng = _offsetToLatLng(
      details.localPosition,
      context.size!.width,
      context.size!.height,
      context,
    );

    final mapOptions = MapOptions.of(context);

    final tapPosition =
        TapPosition(details.globalPosition, details.localPosition);

    // Forward the onTap call to map.options so that we won't break onTap
    mapOptions.onTap?.call(tapPosition, latlng);
  }

  void _zoomMap(TapDownDetails details, BuildContext context) {
    final mapCamera = MapCamera.of(context);
    final mapController = MapController.of(context);

    final newCenter = _offsetToLatLng(
      details.localPosition,
      context.size!.width,
      context.size!.height,
      context,
    );
    mapController.move(newCenter, mapCamera.zoom + 0.5);
  }

  LatLng _offsetToLatLng(
    Offset offset,
    double width,
    double height,
    BuildContext context,
  ) {
    final mapCamera = MapCamera.of(context);

    final localPoint = Point(offset.dx, offset.dy);
    final localPointCenterDistance =
        Point((width / 2) - localPoint.x, (height / 2) - localPoint.y);
    final mapCenter = mapCamera.project(mapCamera.center);
    final point = mapCenter - localPointCenterDistance;
    return mapCamera.unproject(point);
  }
}
