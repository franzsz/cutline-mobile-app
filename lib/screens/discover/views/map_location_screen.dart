import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_map/flutter_map.dart';
import 'package:shop/constants.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shop/notifications.dart';
import 'package:shop/services/osrm_service.dart';
import 'package:shop/route/route_constants.dart';

class QueueMapTrackingScreen extends StatefulWidget {
  final String queueDocId;
  final VoidCallback onQueueCancelled;

  const QueueMapTrackingScreen({
    super.key,
    required this.queueDocId,
    required this.onQueueCancelled,
  });

  @override
  State<QueueMapTrackingScreen> createState() => _QueueMapTrackingScreenState();
}

class _QueueMapTrackingScreenState extends State<QueueMapTrackingScreen> {
  int? _lastQueuePosition;
  ll.LatLng? userLocation;
  ll.LatLng? branchLocation; // dynamic branch location from Firestore
  String? _currentBranchId; // branch of this queue

  // 🏬 Fallback coordinates (Monumento). Will be overridden by branchLocation
  final ll.LatLng supremoLocation =
      const ll.LatLng(14.657532223617563, 120.97809424510439);

  // 🔒 Proximity confirmation system
  static const double _proximityThreshold = 50.0; // 50 meters

  // Real-time distance tracking
  double? _currentDistance;
  String? _distanceType;
  bool _isCheckingProximity = false;
  bool _isLocationLocked = false;

  // Location caching to prevent unnecessary GPS calls
  DateTime? _lastLocationUpdate;
  static const Duration _locationCacheTimeout = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    // Calculate initial distance after a short delay to ensure location is available
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && userLocation != null) {
        _calculateInitialDistance();
      }
    });
  }

  // ===== Utilities =====

  double _distanceToShopMeters(double lat, double lng) {
    return Geolocator.distanceBetween(
      lat,
      lng,
      (branchLocation ?? supremoLocation).latitude,
      (branchLocation ?? supremoLocation).longitude,
    );
  }

  Future<void> _loadBranchLocation(String branchId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .get();
      final data = doc.data();
      if (data == null) return;
      final coords = data['coordinates'];
      double? lat;
      double? lng;
      if (coords != null) {
        try {
          // GeoPoint support
          lat = (coords.latitude as num?)?.toDouble();
          lng = (coords.longitude as num?)?.toDouble();
        } catch (_) {
          // Map support
          final m = coords as Map<String, dynamic>;
          lat = (m['latitude'] as num?)?.toDouble();
          lng = (m['longitude'] as num?)?.toDouble();
          // String fallback
          if (lat == null && m['latitude'] is String) {
            lat = double.tryParse((m['latitude'] as String)
                .replaceAll(',', '.')
                .replaceAll(RegExp(r'[^0-9.\-]'), ''));
          }
          if (lng == null && m['longitude'] is String) {
            lng = double.tryParse((m['longitude'] as String)
                .replaceAll(',', '.')
                .replaceAll(RegExp(r'[^0-9.\-]'), ''));
          }
        }
      }
      if (lat != null && lng != null) {
        if (!mounted) return;
        setState(() {
          branchLocation = ll.LatLng(lat!, lng!);
        });
      }
    } catch (_) {}
  }

  int _compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
    final bool aLocked = (a['locked'] as bool?) ?? false;
    final bool bLocked = (b['locked'] as bool?) ?? false;

    // 1) Locked come first
    if (aLocked != bLocked) return aLocked ? -1 : 1;

    if (aLocked && bLocked) {
      // 1a) Both locked: order by lockIndex, then lockTime
      final num aIdx = (a['lockIndex'] as num?) ?? double.maxFinite;
      final num bIdx = (b['lockIndex'] as num?) ?? double.maxFinite;
      if (aIdx != bIdx) return aIdx.compareTo(bIdx);

      final Timestamp? aT = a['lockTime'] as Timestamp?;
      final Timestamp? bT = b['lockTime'] as Timestamp?;
      if (aT != null && bT != null) return aT.compareTo(bT);
      if (aT != null) return -1;
      if (bT != null) return 1;
      return 0;
    }

    // 2) Both unlocked: dynamic by distance to SHOP, then createdAt
    final double d1 = ((a['distance'] as num?) ?? double.maxFinite).toDouble();
    final double d2 = ((b['distance'] as num?) ?? double.maxFinite).toDouble();
    if (d1 != d2) return d1.compareTo(d2);

    final Timestamp? t1 = a['createdAt'] as Timestamp?;
    final Timestamp? t2 = b['createdAt'] as Timestamp?;
    if (t1 != null && t2 != null) return t1.compareTo(t2);
    if (t1 != null) return -1;
    if (t2 != null) return 1;
    return 0;
  }

  Future<int?> _computeCurrentDynamicIndex() async {
    final String? branchId = _currentBranchId;
    if (branchId == null) return null;
    final qs = await FirebaseFirestore.instance
        .collection('queue')
        .where('status', isEqualTo: 'pending')
        .where('branchId', isEqualTo: branchId)
        .get();

    final list = qs.docs.map((doc) {
      final data = doc.data();

      final double lat = (data['userLat'] as num?)?.toDouble() ?? 0.0;
      final double lng = (data['userLng'] as num?)?.toDouble() ?? 0.0;

      // Prefer server-computed driving distance (km) if you store it;
      // otherwise use straight-line distance TO THE SHOP.
      final double distanceMeters = (data['drivingKm'] != null)
          ? (data['drivingKm'] as num).toDouble() * 1000.0
          : _distanceToShopMeters(lat, lng);

      // IMPORTANT: treat this user as *unlocked* during pre-lock calculation
      final bool locked = (doc.id == widget.queueDocId)
          ? false
          : ((data['proximityConfirmed'] as bool?) ?? false);

      return {
        'id': doc.id,
        'distance': distanceMeters,
        'createdAt': data['createdAt'] as Timestamp?,
        'locked': locked,
        'lockIndex': data['lockIndex'] as num?,
        'lockTime': data['proximityConfirmedAt'] as Timestamp?,
      };
    }).toList();

    list.sort(_compareEntries);
    final idx = list.indexWhere((e) => e['id'] == widget.queueDocId);
    if (idx == -1) return null;
    return idx + 1; // 1-based
  }

  // ===== Distance & Location =====

  Future<void> _calculateInitialDistance() async {
    if (userLocation == null) return;

    try {
      final straightLineDistance = Geolocator.distanceBetween(
        userLocation!.latitude,
        userLocation!.longitude,
        (branchLocation ?? supremoLocation).latitude,
        (branchLocation ?? supremoLocation).longitude,
      );

      final drivingData = await OSRMService.getDrivingDistanceAndTime(
        startLatitude: userLocation!.latitude,
        startLongitude: userLocation!.longitude,
        endLatitude: (branchLocation ?? supremoLocation).latitude,
        endLongitude: (branchLocation ?? supremoLocation).longitude,
      );

      final distance = drivingData != null
          ? ((drivingData['meters'] as num?)?.toDouble() ??
              straightLineDistance)
          : straightLineDistance;

      final distanceType = drivingData != null ? 'driving' : 'straight-line';

      if (mounted) {
        setState(() {
          _currentDistance = distance;
          _distanceType = distanceType;
        });
      }

      // If location is locked, update the queue document with ETA
      if (_isLocationLocked) {
        await _updateQueueWithEta(distance);
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _updateQueueWithEta(double distanceMeters) async {
    try {
      await FirebaseFirestore.instance
          .collection('queue')
          .doc(widget.queueDocId)
          .update({
        'etaMeters': distanceMeters,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
        'lockedLocation': {
          'latitude': userLocation!.latitude,
          'longitude': userLocation!.longitude,
        },
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _lockCurrentPosition() async {
    if (userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Location not available. Please enable GPS.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Ensure we have a fresh distance reading before locking
    if (_currentDistance == null) {
      await _calculateInitialDistance();
    }

    // Enforce proximity threshold: must be within 50 meters
    if (_currentDistance == null || _currentDistance! > _proximityThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '🔒 You must be within ${_proximityThreshold.toStringAsFixed(0)} meters of the branch to lock your position.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLocationLocked = true;
    });

    // Update queue document with locked location and ETA
    await _updateQueueWithEta(_currentDistance ?? 0);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            '🔒 Position locked! Your ETA will be used for queue ordering.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _unlockPosition() async {
    setState(() {
      _isLocationLocked = false;
    });

    // Remove ETA from queue document
    try {
      await FirebaseFirestore.instance
          .collection('queue')
          .doc(widget.queueDocId)
          .update({
        'etaMeters': FieldValue.delete(),
        'lockedLocation': FieldValue.delete(),
        'lastLocationUpdate': FieldValue.delete(),
      });
    } catch (e) {
      // ignore
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('🔓 Position unlocked. Queue ordering will use join time.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _getUserLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      userLocation = ll.LatLng(pos.latitude, pos.longitude);
      _lastLocationUpdate = DateTime.now();
    });
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  // ===== Proximity + Lock =====

  Future<void> _checkProximityManually({bool forceRefresh = false}) async {
    if (_isCheckingProximity) return; // Prevent multiple simultaneous checks

    setState(() {
      _isCheckingProximity = true;
    });

    try {
      // Only get fresh location if it's been a while since last update or forced
      final now = DateTime.now();
      if (forceRefresh ||
          _lastLocationUpdate == null ||
          now.difference(_lastLocationUpdate!) > _locationCacheTimeout) {
        await _getUserLocation();
      }

      if (userLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Location not available. Please enable GPS.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final straightLineDistance = Geolocator.distanceBetween(
        userLocation!.latitude,
        userLocation!.longitude,
        (branchLocation ?? supremoLocation).latitude,
        (branchLocation ?? supremoLocation).longitude,
      );

      final drivingData = await OSRMService.getDrivingDistanceAndTime(
        startLatitude: userLocation!.latitude,
        startLongitude: userLocation!.longitude,
        endLatitude: (branchLocation ?? supremoLocation).latitude,
        endLongitude: (branchLocation ?? supremoLocation).longitude,
      );

      final distance = drivingData != null
          ? ((drivingData['meters'] as num?)?.toDouble() ??
              straightLineDistance)
          : straightLineDistance;

      final distanceType = drivingData != null ? 'driving' : 'straight-line';

      setState(() {
        _currentDistance = distance;
        _distanceType = distanceType;
      });

      if (distance <= _proximityThreshold) {
        // Before locking, compute current dynamic index (treating this user as unlocked)
        final lockPos = await _computeCurrentDynamicIndex();

        // Lock with a transaction to reduce race conditions when multiple users lock at once
        await FirebaseFirestore.instance.runTransaction((txn) async {
          final ref = FirebaseFirestore.instance
              .collection('queue')
              .doc(widget.queueDocId);

          // (Optional) could re-read the doc: final snap = await txn.get(ref);

          txn.update(ref, {
            'proximityConfirmed': true,
            'proximityConfirmedAt': FieldValue.serverTimestamp(),
            'proximityConfirmedLocation': {
              'latitude': userLocation!.latitude,
              'longitude': userLocation!.longitude,
            },
            'proximityDistance': distance,
            'proximityDistanceType': distanceType,
            // Freeze current position for locked ordering
            'lockIndex': lockPos ?? 999999,
          });
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Proximity confirmed! You\'re ${distance.toStringAsFixed(1)}m away ($distanceType). Position locked!',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        NotificationService.showNotification(
          title: 'Proximity Confirmed!',
          body:
              'Your queue position is now locked. You\'re within ${_proximityThreshold.toStringAsFixed(0)}m of the branch.',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Too far! You\'re ${distance.toStringAsFixed(1)}m away ($distanceType). Get within ${_proximityThreshold.toStringAsFixed(0)}m to lock your position.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error checking proximity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isCheckingProximity = false;
      });
    }
  }

  // ===== Service Completion Handling =====

  Future<void> _handleServiceCompleted(
      BuildContext context, Map<String, dynamic> queueData) async {
    try {
      // Show completion message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '🎉 Service completed! Redirecting to transaction history...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate to transaction history after a short delay
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            transactionHistoryScreenRoute,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing completion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final queueRef =
        FirebaseFirestore.instance.collection('queue').doc(widget.queueDocId);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Track Your Queue"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: queueRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            // Queue document was deleted (likely completed by cashier)
            // Navigate to transaction history
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(
                context,
                transactionHistoryScreenRoute,
              );
            });
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Service Completed!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Redirecting to transaction history...'),
                ],
              ),
            );
          }
          // Ensure branch location is loaded for this queue's branch
          final String? branchId = (data['branchId'] as String?);
          if (branchId != null && branchLocation == null) {
            // fire and forget; map will update when setState runs
            _loadBranchLocation(branchId);
          }
          if (_currentBranchId != branchId) {
            _currentBranchId = branchId;
          }

          final status = (data['status'] ?? 'pending').toString().toLowerCase();
          final ticketNumber =
              '#Q${widget.queueDocId.substring(0, 4).toUpperCase()}';

          // Check if location is already locked
          if (data['lockedLocation'] != null && !_isLocationLocked) {
            setState(() {
              _isLocationLocked = true;
            });
          }

          // Handle completed status - navigate to transaction history
          if (status == 'completed') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleServiceCompleted(context, data);
            });
          }

          return Column(
            children: [
              Expanded(
                flex: 4,
                child: userLocation == null
                    ? const Center(child: CircularProgressIndicator())
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: ll.LatLng(
                            (userLocation!.latitude +
                                    (branchLocation ?? supremoLocation)
                                        .latitude) /
                                2,
                            (userLocation!.longitude +
                                    (branchLocation ?? supremoLocation)
                                        .longitude) /
                                2,
                          ),
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: osmTileUrl,
                            userAgentPackageName: 'com.example.shop',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: userLocation!,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.person_pin_circle,
                                  size: 36,
                                  color: Colors.blue,
                                ),
                              ),
                              Marker(
                                point: branchLocation ?? supremoLocation,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.store_mall_directory,
                                  size: 36,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: const [
                              TextSourceAttribution(
                                  '© OpenStreetMap contributors'),
                            ],
                          ),
                        ],
                      ),
              ),
              Expanded(
                flex: 6,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Your Ticket',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text(ticketNumber,
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Chip(
                              label: Text(status.toString().toUpperCase()),
                              backgroundColor: status == 'pending'
                                  ? Colors.orange[100]
                                  : status == 'in_service'
                                      ? Colors.green[100]
                                      : status == 'completed'
                                          ? Colors.blue[100]
                                          : Colors.grey[300],
                              labelStyle: TextStyle(
                                color: status == 'pending'
                                    ? Colors.orange
                                    : status == 'in_service'
                                        ? Colors.green
                                        : status == 'completed'
                                            ? Colors.blue
                                            : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Service Completion Message
                            if (status == 'completed') ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '🎉 Service Completed!',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Redirecting to transaction history...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Proximity Status Display
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        color: Colors.orange,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '📍 Proximity Check Required',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Get within ${_proximityThreshold.toStringAsFixed(0)} meters of the branch to lock your position',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.orange.shade600,
                                              ),
                                            ),
                                            if (_currentDistance != null) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _currentDistance! <=
                                                          _proximityThreshold
                                                      ? Colors.green.shade50
                                                      : Colors.orange.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: _currentDistance! <=
                                                            _proximityThreshold
                                                        ? Colors.green.shade300
                                                        : Colors
                                                            .orange.shade300,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _currentDistance! <=
                                                              _proximityThreshold
                                                          ? Icons.check_circle
                                                          : Icons.location_on,
                                                      color: _currentDistance! <=
                                                              _proximityThreshold
                                                          ? Colors
                                                              .green.shade600
                                                          : Colors
                                                              .orange.shade600,
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            '${_currentDistance!.toStringAsFixed(1)}m (${_distanceType ?? 'calc'})',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: _currentDistance! <=
                                                                      _proximityThreshold
                                                                  ? Colors.green
                                                                      .shade700
                                                                  : Colors
                                                                      .orange
                                                                      .shade700,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            maxLines: 1,
                                                          ),
                                                          if (_lastLocationUpdate !=
                                                              null)
                                                            Text(
                                                              'Updated ${_getTimeAgo(_lastLocationUpdate!)}',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onLongPress: _isCheckingProximity
                                              ? null
                                              : () {
                                                  _checkProximityManually(
                                                      forceRefresh: true);
                                                },
                                          child: ElevatedButton.icon(
                                            onPressed: _isCheckingProximity
                                                ? null
                                                : _checkProximityManually,
                                            icon: _isCheckingProximity
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                    ),
                                                  )
                                                : const Icon(Icons.my_location),
                                            label: Text(_isCheckingProximity
                                                ? 'Checking...'
                                                : 'Check Proximity Now'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  _isCheckingProximity
                                                      ? Colors.grey
                                                      : Colors.orange,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _isLocationLocked
                                              ? _unlockPosition
                                              : (_currentDistance != null &&
                                                      _currentDistance! <=
                                                          _proximityThreshold
                                                  ? _lockCurrentPosition
                                                  : null),
                                          icon: Icon(_isLocationLocked
                                              ? Icons.lock
                                              : Icons.lock_open),
                                          label: Text(_isLocationLocked
                                              ? 'Unlock Position'
                                              : 'Lock Position'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _isLocationLocked
                                                ? Colors.red
                                                : ((_currentDistance != null &&
                                                        _currentDistance! <=
                                                            _proximityThreshold)
                                                    ? Colors.green
                                                    : Colors.grey),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.blue.shade200),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.info,
                                                color: Colors.blue.shade600,
                                                size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${_proximityThreshold.toStringAsFixed(0)}m',
                                              style: TextStyle(
                                                color: Colors.blue.shade600,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ===== Live position with new ordering rules =====
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('queue')
                                  .where('status', isEqualTo: 'pending')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData || userLocation == null) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final entries = snapshot.data!.docs.map((doc) {
                                  final d = doc.data() as Map<String, dynamic>;

                                  final double lat =
                                      (d['userLat'] as num?)?.toDouble() ?? 0.0;
                                  final double lng =
                                      (d['userLng'] as num?)?.toDouble() ?? 0.0;

                                  // distance to SHOP (not viewer)
                                  final double distanceMeters =
                                      (d['drivingKm'] != null)
                                          ? (d['drivingKm'] as num).toDouble() *
                                              1000.0
                                          : _distanceToShopMeters(lat, lng);

                                  return {
                                    'id': doc.id,
                                    'distance': distanceMeters,
                                    'createdAt': d['createdAt'] as Timestamp?,
                                    'locked':
                                        (d['proximityConfirmed'] as bool?) ??
                                            false,
                                    'lockIndex': d['lockIndex'] as num?,
                                    'lockTime':
                                        d['proximityConfirmedAt'] as Timestamp?,
                                  };
                                }).toList();

                                // Sort: locked first (by lockIndex), then unlocked by distance to shop
                                entries.sort(_compareEntries);

                                final position = entries.indexWhere(
                                    (e) => e['id'] == widget.queueDocId);

                                if (position != -1) {
                                  final currentPosition = position + 1;

                                  if (_lastQueuePosition != null &&
                                      currentPosition < _lastQueuePosition!) {
                                    NotificationService.showNotification(
                                      title: 'Queue Update',
                                      body:
                                          'Your position is now #$currentPosition!',
                                    );
                                  }

                                  _lastQueuePosition = currentPosition;

                                  final isLocked =
                                      (entries[position]['locked'] as bool?) ??
                                          false;

                                  return Row(
                                    children: [
                                      Text(
                                        'Your Queue #: $currentPosition',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isLocked)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: Colors.green.shade300),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.lock,
                                                  size: 14,
                                                  color: Colors.green.shade700),
                                              const SizedBox(width: 4),
                                              Text('Locked',
                                                  style: TextStyle(
                                                    color:
                                                        Colors.green.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                } else {
                                  return const Text(
                                      'Unable to determine queue position.');
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('queue')
                            .doc(widget.queueDocId)
                            .delete();
                        widget.onQueueCancelled();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel Queue'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
