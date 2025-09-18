import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shop/constants.dart';

/// OSRM Service for calculating accurate driving distances and travel times
/// between user locations and store branches using real road networks
class OSRMService {
  static const String _baseUrl = osrmBaseUrl;

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final sanitized =
          value.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(sanitized) ?? 0.0;
    }
    // Support Firestore GeoPoint-like objects
    try {
      final lat = (value.latitude as num?)?.toDouble();
      final lng = (value.longitude as num?)?.toDouble();
      if (lat != null && lng == null) return lat;
      if (lng != null && lat == null) return lng;
    } catch (_) {}
    return 0.0;
  }

  /// Calculate driving distance and time between two points
  /// Returns a map with 'km' and 'minutes' keys, or null if calculation fails
  static Future<Map<String, dynamic>?> getDrivingDistanceAndTime({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    try {
      // OSRM expects longitude,latitude order
      final base = Uri.parse(_baseUrl);
      final slon = startLongitude.toStringAsFixed(6);
      final slat = startLatitude.toStringAsFixed(6);
      final elon = endLongitude.toStringAsFixed(6);
      final elat = endLatitude.toStringAsFixed(6);
      final path = '/route/v1/driving/$slon,$slat;$elon,$elat';
      final uri = Uri.https(base.host, path, {
        'overview': 'false',
        'alternatives': 'false',
        'steps': 'false',
      });

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        print('OSRM API error: ${response.statusCode} - ${response.body}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;

      if (routes == null || routes.isEmpty) {
        print('OSRM: No routes found');
        return null;
      }

      final firstRoute = routes[0] as Map<String, dynamic>;
      final distanceMeters = (firstRoute['distance'] as num?)?.toDouble();
      final durationSeconds = (firstRoute['duration'] as num?)?.toDouble();

      if (distanceMeters == null || durationSeconds == null) {
        print('OSRM: Invalid distance or duration data');
        return null;
      }

      return {
        'km': distanceMeters / 1000.0,
        'minutes': (durationSeconds / 60).round(),
        'meters': distanceMeters,
        'seconds': durationSeconds,
      };
    } catch (e) {
      print('OSRM calculation error: $e');
      return null;
    }
  }

  /// Calculate driving distance and time using Position objects
  static Future<Map<String, dynamic>?> getDrivingDistanceAndTimeFromPositions({
    required Position startPosition,
    required double endLatitude,
    required double endLongitude,
  }) async {
    return getDrivingDistanceAndTime(
      startLatitude: startPosition.latitude,
      startLongitude: startPosition.longitude,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
    );
  }

  /// Calculate driving distances from one point to multiple destinations
  /// Returns a list of maps with 'km' and 'minutes' keys
  static Future<List<Map<String, dynamic>?>>
      getDrivingDistancesToMultipleDestinations({
    required double startLatitude,
    required double startLongitude,
    required List<Map<String, double>>
        destinations, // [{'lat': x, 'lng': y}, ...]
  }) async {
    try {
      // Build coordinates string for OSRM table service (lon,lat;lon,lat...)
      final slon = startLongitude.toStringAsFixed(6);
      final slat = startLatitude.toStringAsFixed(6);
      String coordinates = '$slon,$slat';
      for (final dest in destinations) {
        final dlon = _toDouble(dest['lng']).toStringAsFixed(6);
        final dlat = _toDouble(dest['lat']).toStringAsFixed(6);
        coordinates += ';$dlon,$dlat';
      }
      final base = Uri.parse(_baseUrl);
      final path = '/table/v1/driving/$coordinates';
      final uri = Uri.https(base.host, path, {
        'annotations': 'distance,duration',
      });

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        print(
            'OSRM Table API error: ${response.statusCode} - ${response.body}');
        return List.filled(destinations.length, null);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final distances = data['distances'] as List?;
      final durations = data['durations'] as List?;

      if (distances == null || durations == null || distances.isEmpty) {
        print('OSRM Table: No distance/duration data found');
        return List.filled(destinations.length, null);
      }

      final firstRowDistances = distances[0] as List;
      final firstRowDurations = durations[0] as List;

      List<Map<String, dynamic>?> results = [];

      // Skip first element (distance from start to start)
      for (int i = 1; i < firstRowDistances.length; i++) {
        final distanceMeters = (firstRowDistances[i] as num?)?.toDouble();
        final durationSeconds = (firstRowDurations[i] as num?)?.toDouble();

        if (distanceMeters != null && durationSeconds != null) {
          results.add({
            'km': distanceMeters / 1000.0,
            'minutes': (durationSeconds / 60).round(),
            'meters': distanceMeters,
            'seconds': durationSeconds,
          });
        } else {
          results.add(null);
        }
      }

      return results;
    } catch (e) {
      print('OSRM Table calculation error: $e');
      return List.filled(destinations.length, null);
    }
  }

  /// Get the nearest branch based on driving distance (not straight-line)
  static Future<Map<String, dynamic>?> findNearestBranchByDrivingDistance({
    required Position userPosition,
    required List<Map<String, dynamic>>
        branches, // Branch data with coordinates
  }) async {
    try {
      // Prepare destinations for OSRM table service
      List<Map<String, double>> destinations = [];
      for (final branch in branches) {
        final coords = branch['coordinates'] as Map<String, dynamic>?;
        if (coords != null) {
          destinations.add({
            'lat': (coords['latitude'] ?? 0.0).toDouble(),
            'lng': (coords['longitude'] ?? 0.0).toDouble(),
          });
        }
      }

      if (destinations.isEmpty) {
        return null;
      }

      // Get driving distances to all branches
      final distances = await getDrivingDistancesToMultipleDestinations(
        startLatitude: userPosition.latitude,
        startLongitude: userPosition.longitude,
        destinations: destinations,
      );

      // Find the nearest branch
      int nearestIndex = -1;
      double nearestDistance = double.infinity;

      for (int i = 0; i < distances.length; i++) {
        final distance = distances[i];
        if (distance != null && distance['km'] < nearestDistance) {
          nearestDistance = distance['km'] as double;
          nearestIndex = i;
        }
      }

      if (nearestIndex == -1) {
        return null;
      }

      return {
        'branch': branches[nearestIndex],
        'drivingDistance': distances[nearestIndex],
        'index': nearestIndex,
      };
    } catch (e) {
      print('Error finding nearest branch: $e');
      return null;
    }
  }

  /// Format distance for display
  static String formatDistance(double? km) {
    if (km == null) return 'N/A';
    if (km < 1) {
      final meters = (km * 1000).round();
      return '$meters m';
    }
    return '${km.toStringAsFixed(2)} km';
  }

  /// Format time for display
  static String formatTime(int? minutes) {
    if (minutes == null) return 'N/A';
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '$minutes mins';
  }

  /// Get fallback straight-line distance if OSRM fails
  static double getStraightLineDistance({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return Geolocator.distanceBetween(
          startLatitude,
          startLongitude,
          endLatitude,
          endLongitude,
        ) /
        1000.0; // Convert to km
  }
}
