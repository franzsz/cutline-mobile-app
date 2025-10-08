import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_map/flutter_map.dart';
import 'package:shop/constants.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shop/notifications.dart';
import 'package:shop/services/osrm_service.dart';
import 'package:shop/route/route_constants.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;

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

class _QueueMapTrackingScreenState extends State<QueueMapTrackingScreen>
    with TickerProviderStateMixin {
  int? _lastQueuePosition;
  ll.LatLng? userLocation;
  ll.LatLng? branchLocation;
  String? _currentBranchId;
  final MapController _mapController = MapController();

  // Fallback coordinates (Monumento)
  final ll.LatLng supremoLocation =
      const ll.LatLng(14.657532223617563, 120.97809424510439);

  // Proximity confirmation system
  static const double _proximityThreshold = 50.0;

  // Real-time distance tracking
  double? _currentDistance;
  String? _distanceType;
  bool _isLocationLocked = false;

  // Location caching
  DateTime? _lastLocationUpdate;

  // Automatic proximity monitoring
  Timer? _proximityTimer;
  bool _isAutoMonitoring = false;
  static const Duration _proximityCheckInterval = Duration(seconds: 30);

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  // Queue visualization data
  // List<QueueCustomer> _queueCustomers = [];
  // bool _showQueueAnimation = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _getUserLocation();
    // Start automatic monitoring immediately
    _startAutomaticProximityMonitoring();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && userLocation != null) {
        _calculateInitialDistance();
      }
    });
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade600, Colors.grey.shade800],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    // Ensure slide-based widgets (e.g., Queue Position card) are visible on first build
    // by setting the controller to its completed state. We can still animate later by
    // resetting before forwarding.
    _slideController.value = 1.0;

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // Your existing utility methods remain the same...
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
          lat = (coords.latitude as num?)?.toDouble();
          lng = (coords.longitude as num?)?.toDouble();
        } catch (_) {
          final m = coords as Map<String, dynamic>;
          lat = (m['latitude'] as num?)?.toDouble();
          lng = (m['longitude'] as num?)?.toDouble();
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

    // Locked positions always come first and maintain their fixed position
    if (aLocked && bLocked) {
      final num aLockedPos =
          (a['lockedQueuePosition'] as num?) ?? double.maxFinite;
      final num bLockedPos =
          (b['lockedQueuePosition'] as num?) ?? double.maxFinite;
      return aLockedPos.compareTo(bLockedPos);
    }

    // Locked positions always come before unlocked positions
    if (aLocked != bLocked) return aLocked ? -1 : 1;

    // For unlocked positions, sort by creation time (first come, first served)
    // This ensures unlocked positions don't jump ahead of each other
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
      final double distanceMeters = (data['drivingKm'] != null)
          ? (data['drivingKm'] as num).toDouble() * 1000.0
          : _distanceToShopMeters(lat, lng);
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
        'lockedQueuePosition': data['lockedQueuePosition'] as num?,
      };
    }).toList();

    list.sort(_compareEntries);
    final idx = list.indexWhere((e) => e['id'] == widget.queueDocId);
    if (idx == -1) return null;

    // If this user's position is locked, return their locked position
    final userEntry = list[idx];
    if (userEntry['locked'] == true &&
        userEntry['lockedQueuePosition'] != null) {
      return (userEntry['lockedQueuePosition'] as num).toInt();
    }

    // For unlocked positions, return the current dynamic position
    return idx + 1;
  }

  // Automatic proximity monitoring methods
  void _startAutomaticProximityMonitoring() {
    if (_isAutoMonitoring) return;

    setState(() {
      _isAutoMonitoring = true;
    });

    _proximityTimer = Timer.periodic(_proximityCheckInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Only check if not already locked
      if (!_isLocationLocked) {
        _checkProximityAutomatically();
      }
    });
  }

  void _stopAutomaticProximityMonitoring() {
    _proximityTimer?.cancel();
    _proximityTimer = null;
    setState(() {
      _isAutoMonitoring = false;
    });
  }

  Future<void> _checkProximityAutomatically() async {
    if (_isLocationLocked) return;

    try {
      // Get fresh location
      await _getUserLocation();

      if (userLocation == null) return;

      // Calculate distance
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

      // If within threshold, automatically lock position
      if (distance <= _proximityThreshold) {
        await _lockPositionAutomatically(distance, distanceType);
      }
    } catch (e) {
      // Silently handle errors for automatic checking
      debugPrint('Automatic proximity check error: $e');
    }
  }

  Future<void> _lockPositionAutomatically(
      double distance, String distanceType) async {
    try {
      final lockPos = await _computeCurrentDynamicIndex();

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final ref = FirebaseFirestore.instance
            .collection('queue')
            .doc(widget.queueDocId);

        txn.update(ref, {
          'proximityConfirmed': true,
          'proximityConfirmedAt': FieldValue.serverTimestamp(),
          'proximityConfirmedLocation': {
            'latitude': userLocation!.latitude,
            'longitude': userLocation!.longitude,
          },
          'proximityDistance': distance,
          'proximityDistanceType': distanceType,
          'lockIndex': lockPos ?? 999999,
          'lockedQueuePosition':
              lockPos ?? 999999, // Store the fixed queue position
        });
      });

      // Stop automatic monitoring since position is now locked
      _stopAutomaticProximityMonitoring();

      setState(() {
        _isLocationLocked = true;
      });

      // Trigger success animation
      _slideController
        ..reset()
        ..forward();

      if (mounted) {
        _showSuccessSnackBar(
          'Position automatically locked! You\'re ${distance.toStringAsFixed(1)}m away.',
        );
      }

      NotificationService.showNotification(
        title: 'Position Auto-Locked!',
        body:
            'Your queue position has been automatically locked at #${lockPos ?? 999999}. You\'re within ${_proximityThreshold.toStringAsFixed(0)}m of the branch.',
      );
    } catch (e) {
      debugPrint('Error auto-locking position: $e');
    }
  }

  // Enhanced snackbar methods with custom styling
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Enhanced location methods (keeping your existing logic)
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

  Future<void> _handleServiceCompleted(
      BuildContext context, Map<String, dynamic> queueData) async {
    try {
      if (mounted) {
        _showSuccessSnackBar(
            'Service completed! Redirecting to transaction history...');
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
        _showErrorSnackBar('Error processing completion: $e');
      }
    }
  }

  // Enhanced UI build method
  @override
  Widget build(BuildContext context) {
    final queueRef =
        FirebaseFirestore.instance.collection('queue').doc(widget.queueDocId);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Track Your Queue"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey.shade100,
              Colors.grey.shade200,
            ],
          ),
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: queueRef.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading your queue status...'),
                  ],
                ),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pushReplacementNamed(
                  context,
                  transactionHistoryScreenRoute,
                );
              });
              return _buildCompletedScreen();
            }

            final String? branchId = (data['branchId'] as String?);
            if (branchId != null && branchLocation == null) {
              _loadBranchLocation(branchId);
            }
            if (_currentBranchId != branchId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _currentBranchId = branchId;
                });
              });
            }

            final status =
                (data['status'] ?? 'pending').toString().toLowerCase();
            final ticketNumber =
                '#Q${widget.queueDocId.substring(0, 4).toUpperCase()}';

            if (data['lockedLocation'] != null && !_isLocationLocked) {
              setState(() {
                _isLocationLocked = true;
              });
            }

            if (status == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleServiceCompleted(context, data);
              });
            }

            return Column(
              children: [
                // Enhanced Map Section
                Expanded(
                  flex: 4,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: userLocation == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Getting your location...'),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
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
                                        child: ScaleTransition(
                                          scale: _pulseAnimation,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade600,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.blue
                                                      .withOpacity(0.3),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.person,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Marker(
                                        point:
                                            branchLocation ?? supremoLocation,
                                        width: 40,
                                        height: 40,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade600,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color:
                                                    Colors.red.withOpacity(0.3),
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.store,
                                            size: 20,
                                            color: Colors.white,
                                          ),
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

                              // Distance chip overlay
                              if (_currentDistance != null)
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.blue.shade200),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _currentDistance! <=
                                                  _proximityThreshold
                                              ? Icons.check_circle
                                              : Icons.route,
                                          size: 16,
                                          color: _currentDistance! <=
                                                  _proximityThreshold
                                              ? Colors.green.shade700
                                              : Colors.blue.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${_currentDistance!.toStringAsFixed(1)}m • ${(_distanceType ?? 'distance')}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Floating control buttons
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Column(
                                  children: [
                                    _MapCircleButton(
                                      icon: Icons.my_location,
                                      tooltip: 'Recenter',
                                      onPressed: _recenterMap,
                                    ),
                                    const SizedBox(height: 8),
                                    _MapCircleButton(
                                      icon: Icons.gps_fixed,
                                      tooltip: 'Refresh location',
                                      onPressed: _recenterMap,
                                      showProgress: false,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // Enhanced Queue Information Section
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: ListView(
                      children: [
                        // Queue Position Card
                        _buildSectionHeader('Queue Position'),
                        _buildQueuePositionCard(),
                        const SizedBox(height: 4),

                        // Distance and Proximity Card
                        _buildSectionHeader('Proximity'),
                        _buildProximityCard(),
                        const SizedBox(height: 4),

                        // Live Queue List
                        _buildSectionHeader('Live Queue'),
                        _buildLiveQueueList(),
                        const SizedBox(height: 20),

                        // Main Queue Status Card
                        _buildMainStatusCard(ticketNumber, status),
                        const SizedBox(height: 16),

                        // Action Buttons
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQueueSummaryBar() {
    if (_currentBranchId == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading branch queue...'),
          ],
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('queue')
          .where('status', whereIn: ['pending', 'in_service'])
          .where('branchId', isEqualTo: _currentBranchId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Fetching your position...'),
              ],
            ),
          );
        }

        final entries = snapshot.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'distance': ((d['drivingKm'] as num?)?.toDouble() ?? 0) * 1000.0,
            'createdAt': d['createdAt'] as Timestamp?,
            'locked': (d['proximityConfirmed'] as bool?) ?? false,
            'lockIndex': d['lockIndex'] as num?,
            'lockTime': d['proximityConfirmedAt'] as Timestamp?,
            'lockedQueuePosition': d['lockedQueuePosition'] as num?,
          };
        }).toList();

        entries.sort(_compareEntries);
        final position =
            entries.indexWhere((e) => e['id'] == widget.queueDocId);
        final isLocked = position != -1
            ? ((entries[position]['locked'] as bool?) ?? false)
            : false;

        // Always use current position in the sorted queue
        final currentPosition = position == -1 ? null : position + 1;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey.shade100, Colors.grey.shade200],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade600, Colors.grey.shade800],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  currentPosition == 1
                      ? Icons.support_agent
                      : Icons.confirmation_number,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentPosition == null
                          ? 'Queue Status'
                          : 'Your Queue Position',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentPosition == null
                          ? 'We could not determine your position'
                          : (currentPosition == 1
                              ? 'You are being served now'
                              : 'You are #$currentPosition in line'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (currentPosition != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLocked
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLocked ? Icons.lock : Icons.lock_open,
                        size: 14,
                        color: isLocked
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLocked ? 'LOCKED' : 'UNLOCKED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isLocked
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _recenterMap() {
    if (userLocation != null) {
      _mapController.move(userLocation!, 15);
    }
  }

  Widget _buildCompletedScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.green.shade50, Colors.grey.shade100],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 80),
            SizedBox(height: 24),
            Text(
              'Service Completed!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Redirecting to transaction history...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatusCard(String ticketNumber, String status) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Ticket',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              _buildStatusChip(status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ticketNumber,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (status == 'completed') ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.green.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                children: [
                  Icon(Icons.celebration,
                      color: Colors.green.shade600, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Service Completed!',
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
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case 'pending':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        icon = Icons.access_time;
        break;
      case 'in_service':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        icon = Icons.content_cut;
        break;
      case 'completed':
        backgroundColor = Colors.grey.shade300;
        textColor = Colors.grey.shade900;
        icon = Icons.check_circle;
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProximityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proximity Check Required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Get within ${_proximityThreshold.toStringAsFixed(0)}m to lock position',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_currentDistance != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _currentDistance! <= _proximityThreshold
                    ? Colors.green.shade50
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _currentDistance! <= _proximityThreshold
                      ? Colors.green.shade300
                      : Colors.orange.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentDistance! <= _proximityThreshold
                        ? Icons.check_circle
                        : Icons.location_searching,
                    color: _currentDistance! <= _proximityThreshold
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_currentDistance!.toStringAsFixed(1)}m away',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _currentDistance! <= _proximityThreshold
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                        Text(
                          '${_distanceType ?? 'calculated'} distance',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_lastLocationUpdate != null)
                          Text(
                            'Updated ${_getTimeAgo(_lastLocationUpdate!)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Auto-monitoring status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isLocationLocked
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isLocationLocked
                    ? Colors.green.shade200
                    : Colors.blue.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isLocationLocked ? Icons.lock : Icons.radar,
                  size: 20,
                  color: _isLocationLocked
                      ? Colors.green.shade600
                      : Colors.blue.shade600,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLocationLocked
                            ? 'Position Locked!'
                            : 'Auto-Monitoring Active',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _isLocationLocked
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLocationLocked
                            ? 'Your queue position is secured within 50m of the branch'
                            : 'Your location is being monitored every 30s. Position will auto-lock when you\'re within 50m.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isLocationLocked
                              ? Colors.green.shade600
                              : Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuePositionCard() {
    if (_currentBranchId == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('queue')
          .where('status', isEqualTo: 'pending')
          .where('branchId', isEqualTo: _currentBranchId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final entries = snapshot.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final double lat = (d['userLat'] as num?)?.toDouble() ?? 0.0;
          final double lng = (d['userLng'] as num?)?.toDouble() ?? 0.0;
          final double distanceMeters = (d['drivingKm'] != null)
              ? (d['drivingKm'] as num).toDouble() * 1000.0
              : _distanceToShopMeters(lat, lng);

          return {
            'id': doc.id,
            'distance': distanceMeters,
            'createdAt': d['createdAt'] as Timestamp?,
            'locked': (d['proximityConfirmed'] as bool?) ?? false,
            'lockIndex': d['lockIndex'] as num?,
            'lockTime': d['proximityConfirmedAt'] as Timestamp?,
            'lockedQueuePosition': d['lockedQueuePosition'] as num?,
            'status': d['status'] ?? 'pending',
          };
        }).toList();

        entries.sort(_compareEntries);
        // If your doc is in_service, still compute position among all docs
        final position =
            entries.indexWhere((e) => e['id'] == widget.queueDocId);

        if (position != -1) {
          final isLocked = (entries[position]['locked'] as bool?) ?? false;

          // Always use current position in the sorted queue (position + 1)
          final currentPosition = position + 1;

          if (_lastQueuePosition != null &&
              currentPosition != _lastQueuePosition!) {
            String notificationTitle;
            String notificationBody;

            if (currentPosition < _lastQueuePosition!) {
              // Position improved - someone ahead was served or cancelled
              notificationTitle = 'Queue Update - Position Improved!';
              notificationBody =
                  'Your position moved from #${_lastQueuePosition} to #$currentPosition! Someone ahead was served or cancelled.';
            } else {
              // Position got worse (someone joined ahead)
              notificationTitle = 'Queue Update - Position Changed';
              notificationBody =
                  'Your position is now #$currentPosition (was #${_lastQueuePosition}). Someone joined ahead of you.';
            }

            NotificationService.showNotification(
              title: notificationTitle,
              body: notificationBody,
            );
          }
          _lastQueuePosition = currentPosition;

          return SlideTransition(
            position: _slideAnimation,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Queue Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Live',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '#$currentPosition',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: isLocked
                            ? Colors.green.shade600
                            : Colors.grey.shade800,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      isLocked
                          ? 'Your locked position'
                          : 'Your current position',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isLocked
                              ? Colors.green.shade300
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLocked ? Icons.lock : Icons.lock_open,
                            size: 14,
                            color: isLocked
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isLocked ? 'Locked' : 'Unlocked',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isLocked
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildQueueVisualization(currentPosition, entries.length),
                ],
              ),
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Text(
              'Unable to determine queue position.',
              style: TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        }
      },
    );
  }

  Widget _buildQueueVisualization(int position, int totalQueue) {
    final progress =
        totalQueue > 0 ? (totalQueue - position) / totalQueue : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$position people ahead',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              'Total: $totalQueue',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade700),
          minHeight: 8,
        ),
      ],
    );
  }

  Widget _buildLiveQueueList() {
    if (_currentBranchId == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Loading live queue...'),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('queue')
          .where('status', isEqualTo: 'pending')
          .where('branchId', isEqualTo: _currentBranchId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || userLocation == null) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Loading live queue...'),
                ],
              ),
            ),
          );
        }

        final entries = snapshot.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final double lat = (d['userLat'] as num?)?.toDouble() ?? 0.0;
          final double lng = (d['userLng'] as num?)?.toDouble() ?? 0.0;
          final double distanceMeters = (d['drivingKm'] != null)
              ? (d['drivingKm'] as num).toDouble() * 1000.0
              : _distanceToShopMeters(lat, lng);

          return {
            'id': doc.id,
            'distance': distanceMeters,
            'createdAt': d['createdAt'] as Timestamp?,
            'locked': (d['proximityConfirmed'] as bool?) ?? false,
            'lockIndex': d['lockIndex'] as num?,
            'lockTime': d['proximityConfirmedAt'] as Timestamp?,
            'lockedQueuePosition': d['lockedQueuePosition'] as num?,
            'status': d['status'] ?? 'pending',
          };
        }).toList();

        entries.sort(_compareEntries);

        // Generate anonymous ticket numbers
        final List<Map<String, dynamic>> queueTickets = [];
        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final isCurrentUser = entry['id'] == widget.queueDocId;
          final ticketNumber =
              '#Q${(entry['id'] as String).substring(0, 4).toUpperCase()}';
          final isLocked = entry['locked'] as bool;
          final status = entry['status'] as String;

          // Always use current position in the sorted queue
          final position = i + 1;

          queueTickets.add({
            'position': position,
            'ticket': ticketNumber,
            'isYou': isCurrentUser,
            'isLocked': isLocked,
            'status': status,
            'joinedTime': entry['createdAt'] as Timestamp?,
            'distance': entry['distance'] as double,
          });
        }

        // Queue tickets are already in the correct order from the sorted entries

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade100, Colors.grey.shade200],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey.shade600, Colors.grey.shade800],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.people,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Live Queue',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${queueTickets.length} in queue',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Queue List
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: queueTickets.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.queue_music,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No one in queue',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: queueTickets.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ticket = queueTickets[index];
                          final isYou = ticket['isYou'] as bool;
                          final isLocked = ticket['isLocked'] as bool;
                          final position = ticket['position'] as int;
                          final joinedTime = ticket['joinedTime'] as Timestamp?;
                          // final distance = ticket['distance'] as double;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: isYou
                                  ? LinearGradient(
                                      colors: [
                                        Colors.grey.shade100,
                                        Colors.grey.shade200
                                      ],
                                    )
                                  : null,
                              color: isYou ? null : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isYou
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade200,
                                width: isYou ? 2 : 1,
                              ),
                              boxShadow: isYou
                                  ? [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // Position Circle
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: isYou
                                        ? LinearGradient(
                                            colors: [
                                              Colors.blue.shade400,
                                              Colors.purple.shade400
                                            ],
                                          )
                                        : position == 1
                                            ? LinearGradient(
                                                colors: [
                                                  Colors.green.shade400,
                                                  Colors.green.shade600
                                                ],
                                              )
                                            : LinearGradient(
                                                colors: [
                                                  Colors.grey.shade400,
                                                  Colors.grey.shade500
                                                ],
                                              ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isYou ? Colors.blue : Colors.grey)
                                                .withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$position',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Ticket Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            isYou
                                                ? 'Your Position'
                                                : 'Position #$position',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: isYou
                                                  ? Colors.grey.shade800
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (position == 1) ...[
                                            Flexible(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.content_cut,
                                                      size: 12,
                                                      color:
                                                          Colors.green.shade600,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        'Being Served',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .green.shade600,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            if (joinedTime != null)
                                              Flexible(
                                                child: Text(
                                                  'Joined ${_formatTimeAgo(joinedTime.toDate())}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          if (isLocked) ...[
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.lock,
                                                      size: 10,
                                                      color:
                                                          Colors.green.shade600,
                                                    ),
                                                    const SizedBox(width: 2),
                                                    Flexible(
                                                      child: Text(
                                                        'Locked',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .green.shade600,
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Status Indicators
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (position == 1)
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      )
                                    else if (position == 2)
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.schedule,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.more_horiz,
                                          color: Colors.grey.shade600,
                                          size: 16,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      position == 1
                                          ? 'Now'
                                          : position == 2
                                              ? 'Next'
                                              : 'Waiting',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Footer with privacy note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.privacy_tip,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Queue is anonymous - only ticket numbers are shown',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text('Cancel Queue'),
                  content: const Text(
                    'Are you sure you want to cancel your queue? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Keep Queue'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cancel Queue'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await FirebaseFirestore.instance
                    .collection('queue')
                    .doc(widget.queueDocId)
                    .delete();
                widget.onQueueCancelled();
              }
            },
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel Queue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy Protected',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your location and queue details are secure and only visible to you.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Small circular map action button (top-level)
class _MapCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showProgress;

  const _MapCircleButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showProgress = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.15),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: showProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      icon,
                      color: onPressed == null
                          ? Colors.grey.shade400
                          : Colors.black87,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// Helper class for queue customer data
class QueueCustomer {
  final String id;
  final String displayName;
  final bool isYou;
  final bool isLocked;
  final double distance;
  final DateTime joinTime;
  final String status;

  QueueCustomer({
    required this.id,
    required this.displayName,
    required this.isYou,
    required this.isLocked,
    required this.distance,
    required this.joinTime,
    required this.status,
  });
}
