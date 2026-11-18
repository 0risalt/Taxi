import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/image.dart' as image_provider;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../assets/map_style.dart';
import '../config.dart';
import '../services/yandex_api.dart';
import '../theme/app_colors.dart';

/// Управление картой из экрана: маркеры, маршрут, камера.
class TaxiMapController {
  ymk.Map? _map;
  // MapKit хранит слушателя слабой ссылкой — держим его здесь.
  _TapListener? _tapListener;
  ymk.PolylineMapObject? _route;

  bool get isReady => _map != null;

  static final image_provider.ImageProvider _pinIcon =
      image_provider.ImageProvider.fromImageProvider(
    const AssetImage('assets/images/pink_marker.png'),
  );
  static final image_provider.ImageProvider _carIcon =
      image_provider.ImageProvider.fromImageProvider(
    const AssetImage('assets/images/car_marker.png'),
  );

  void _attach(ymk.Map map, void Function(double lat, double lon)? onTap) {
    _map = map;
    if (!map.setMapStyle(pinkMapStyle)) {
      debugPrint('Не удалось применить розовый стиль карты');
    }
    if (onTap != null) {
      _tapListener = _TapListener(onTap);
      map.addInputListener(_tapListener!);
    }
    moveTo(AppConfig.defaultLat, AppConfig.defaultLon, zoom: 12);
  }

  void moveTo(double lat, double lon, {double zoom = 15}) {
    _map?.move(
      ymk.CameraPosition(
        ymk.Point(latitude: lat, longitude: lon),
        zoom: zoom,
        azimuth: 0.0,
        tilt: 0.0,
      ),
    );
  }

  /// Розовый пин (кончик пина указывает точно на координату).
  ymk.PlacemarkMapObject? addPin(double lat, double lon) =>
      _addMarker(lat, lon, _pinIcon);

  /// Машина водителя.
  ymk.PlacemarkMapObject? addCar(double lat, double lon) =>
      _addMarker(lat, lon, _carIcon);

  ymk.PlacemarkMapObject? _addMarker(
    double lat,
    double lon,
    image_provider.ImageProvider icon,
  ) {
    final marker = _map?.mapObjects.addPlacemark();
    if (marker == null) return null;
    marker
      ..geometry = ymk.Point(latitude: lat, longitude: lon)
      ..setIcon(icon)
      ..setIconStyle(ymk.IconStyle(scale: 0.5));
    return marker;
  }

  void moveMarker(ymk.PlacemarkMapObject? marker, double lat, double lon) {
    if (marker != null) {
      marker.geometry = ymk.Point(latitude: lat, longitude: lon);
    }
  }

  void removeMarker(ymk.PlacemarkMapObject? marker) {
    if (marker != null) _map?.mapObjects.remove(marker);
  }

  void setRoute(List<LatLon> points) {
    clearRoute();
    if (points.length < 2) return;
    final line = _map?.mapObjects.addPolyline();
    if (line == null) return;
    line.geometry = ymk.Polyline(
      points.map((p) => ymk.Point(latitude: p.lat, longitude: p.lon)).toList(),
    );
    line.setStrokeColor(AppColors.primary);
    line.strokeWidth = 6.0;
    _route = line;
  }

  void clearRoute() {
    final r = _route;
    if (r != null) {
      _map?.mapObjects.remove(r);
      _route = null;
    }
  }
}

class _TapListener implements ymk.MapInputListener {
  _TapListener(this.onTap);
  final void Function(double lat, double lon) onTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) =>
      onTap(point.latitude, point.longitude);

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) {}
}

class TaxiMap extends StatefulWidget {
  const TaxiMap({
    super.key,
    required this.controller,
    this.onReady,
    this.onTap,
  });

  final TaxiMapController controller;
  final VoidCallback? onReady;
  final void Function(double lat, double lon)? onTap;

  @override
  State<TaxiMap> createState() => _TaxiMapState();
}

class _TaxiMapState extends State<TaxiMap> {
  void _onMapCreated(ymk.MapWindow mapWindow) {
    widget.controller._attach(mapWindow.map, widget.onTap);
    widget.onReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    return YandexMap(onMapCreated: _onMapCreated);
  }
}
