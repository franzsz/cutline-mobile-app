import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shop/route/route_constants.dart';
import 'package:shop/notifications.dart';
import 'package:shop/models/branch_model.dart';
import 'package:shop/services/osrm_service.dart';

class DiscoverScreen extends StatefulWidget {
  final void Function(String queueDocId) onQueueConfirmed;

  const DiscoverScreen({super.key, required this.onQueueConfirmed});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String? selectedBranchId;
  String? selectedService;
  String? selectedPaymentMethod;
  // Barber preference
  String _barberPreference = 'Any available barber';
  String? _requestedBarberId;
  String? _requestedBarberNote;
  String queueNumber = '...';
  bool isPaymentAlert = false;
  bool _autoPrefilled = false;

  Position? _userPosition;
  double? _selectedDistanceKm; // distance to selected branch in KM
  int? _peopleAhead;
  int? _estimatedWaitMin;
  int? _drivingMinutes; // driving ETA if available
  double? _drivingKm; // driving distance if available
  // Live branches loaded from Firestore to align with Home page
  List<BranchModel> _branches = [];

  List<String> paymentMethods = ['Over the Counter', 'Online'];
  final List<String> _preferenceOptions = const [
    'Any available barber',
    'Request a specific barber',
  ];

  @override
  void initState() {
    super.initState();
    _initializeQueueing();
  }

  // Enhanced loading dialog methods
  void _showRecommendationLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent closing with back button
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Enhanced loading animation with gradient
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFD4AF37),
                            Color(0xFFB8941F),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Enhanced title with icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.explore,
                            color: Color(0xFFD4AF37),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Finding Best Options',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A0F0A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Enhanced description
                    const Text(
                      'Analyzing your location and preferences to recommend the perfect barbershop experience',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Progress indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LoadingDot(delay: 0),
                        const SizedBox(width: 8),
                        _LoadingDot(delay: 200),
                        const SizedBox(width: 8),
                        _LoadingDot(delay: 400),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _hideRecommendationLoadingDialog() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  int _getPerPersonMinutes(String? service) {
    final serviceTimes = <String, int>{
      'Haircut': 20,
      'Beard Trim': 15,
      'Hair Coloring': 60,
      'Shaving': 15,
      'Kids Haircut': 25,
      'Hair Styling': 30,
      'Facial Treatment': 45,
      'Massage': 45,
      'Hair Treatment': 45,
    };
    return service != null ? (serviceTimes[service] ?? 25) : 25;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Branch loading (align with Home page) ---
  BranchModel _branchFromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final map = <String, dynamic>{...data, 'id': doc.id};

    if (map['status'] == null && map['isActive'] != null) {
      map['status'] = map['isActive'] == true ? 'Open' : 'Closed';
    }

    map['operatingHours'] =
        (map['operatingHours'] as Map?)?.cast<String, dynamic>() ?? {};

    final rawServices = map['services'];
    if (rawServices is List) {
      map['services'] = rawServices.map((e) => e.toString()).toList();
    } else if (rawServices is String) {
      map['services'] = rawServices
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      map['services'] = <String>[];
    }

    final rating = map['rating'];
    if (rating is int) map['rating'] = rating.toDouble();

    return BranchModel.fromMap(map);
  }

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name')
          .get();
      final list = snap.docs.map(_branchFromDoc).toList();
      if (mounted) {
        setState(() {
          _branches = list;
        });
      }
    } catch (e) {
      // Fallback to empty list; UI will handle gracefully
      if (mounted) setState(() => _branches = []);
      debugPrint('Failed to load branches: $e');
    }
  }

  Future<bool> _checkIfUserAlreadyQueued() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final query = await FirebaseFirestore.instance
        .collection('queue')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final docId = query.docs.first.id;
      Navigator.pushNamed(context, queueMapTrackingRoute, arguments: docId);
      return true; // User already has a queue
    }
    return false; // No existing queue
  }

  Future<void> _initializeQueueing() async {
    await Firebase.initializeApp();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Location permission is required');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(
          'Location permission permanently denied. Enable it in settings.');
    }

    // Check if user already has a queue - if so, navigate away and don't continue
    final hasExistingQueue = await _checkIfUserAlreadyQueued();
    if (hasExistingQueue) {
      return; // Exit early, user is being navigated to queue tracking screen
    }

    await _loadBranches();
    await _autoSelectNearestBranchAndService();

    if (mounted) {
      setState(() {
        isPaymentAlert = true;
        selectedPaymentMethod ??= paymentMethods.first;
      });
    }
  }

  Future<Position> _getPrecisePosition() async {
    try {
      // Try high-accuracy first
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
    } catch (_) {
      // Fallback to high accuracy
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (_) {
        // Fallback to last known position
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
        // Final fallback: medium accuracy
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
      }
    }
  }

  Future<double> _computeDistanceKm(
      Position position, BranchModel branch) async {
    final lat = (branch.coordinates['latitude'] ?? 0.0).toDouble();
    final lng = (branch.coordinates['longitude'] ?? 0.0).toDouble();
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lng,
    );
    return meters / 1000.0;
  }

  String _formatDistance(double? km) {
    if (km == null) return 'N/A';
    if (km < 1) {
      final meters = (km * 1000).round();
      return '$meters m';
    }
    return '${km.toStringAsFixed(2)} km';
  }

  String _formatWait(int? minutes) {
    if (minutes == null) return 'N/A';
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      if (m == 0) return '${h}h';
      return '${h}h ${m}m';
    }
    return '$minutes mins';
  }

  Future<Map<String, dynamic>?> _getDrivingDistanceAndTime(
      Position position, BranchModel branch) async {
    final lat = (branch.coordinates['latitude'] ?? 0.0).toDouble();
    final lng = (branch.coordinates['longitude'] ?? 0.0).toDouble();

    return await OSRMService.getDrivingDistanceAndTime(
      startLatitude: position.latitude,
      startLongitude: position.longitude,
      endLatitude: lat,
      endLongitude: lng,
    );
  }

  String _formatDistancePref(double? directKm, double? drivingKm) {
    final km = drivingKm ?? directKm;
    return _formatDistance(km);
  }

  String _formatWaitPref(int? estimated, int? driving) {
    final minutes = estimated; // keep queue-based estimate dominant
    return _formatWait(minutes);
  }

  // Removed: direct barber listing (now using a note-based request to avoid broader reads)

  Future<void> _autoSelectNearestBranchAndService() async {
    // Show loading dialog
    _showRecommendationLoadingDialog();

    try {
      final position = await _getPrecisePosition();
      _userPosition = position;

      // Convert live branches to the format expected by OSRM service
      List<Map<String, dynamic>> branchesData = _branches
          .map((branch) => {
                'id': branch.id,
                'name': branch.name,
                'location': branch.location,
                'address': branch.address,
                'status': branch.status,
                'image': branch.image,
                'phone': branch.phone,
                'email': branch.email,
                'operatingHours': branch.operatingHours,
                'services': branch.services,
                'rating': branch.rating,
                'reviewCount': branch.reviewCount,
                'coordinates': branch.coordinates,
                'currentQueueCount': branch.currentQueueCount,
                'estimatedWaitTime': branch.estimatedWaitTime,
              })
          .toList();

      // Find nearest branch using OSRM driving distance
      final nearestResult =
          await OSRMService.findNearestBranchByDrivingDistance(
        userPosition: position,
        branches: branchesData,
      );

      if (nearestResult != null) {
        final nearest = nearestResult['branch'] as Map<String, dynamic>;
        final drivingData =
            nearestResult['drivingDistance'] as Map<String, dynamic>?;

        // Create BranchModel from the nearest branch data
        final nearestBranch = BranchModel.fromMap(nearest);

        // Get straight-line distance as fallback
        final straightLineKm =
            await _computeDistanceKm(position, nearestBranch);

        // Use driving distance if available, otherwise fallback to straight-line
        final distanceKm = drivingData?['km'] as double? ?? straightLineKm;

        final uid = FirebaseAuth.instance.currentUser?.uid;
        String? preferredService;
        if (uid != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          preferredService = userDoc.data()?['preferredService'] as String?;
        }

        final services = nearestBranch.services;
        String? initialService;
        if (preferredService != null && services.contains(preferredService)) {
          initialService = preferredService;
        } else {
          initialService = services.isNotEmpty ? services.first : null;
        }

        final aheadSnapshot = await FirebaseFirestore.instance
            .collection('queue')
            .where('branchId', isEqualTo: nearestBranch.id)
            .where('status', isEqualTo: 'pending')
            .get();
        final peopleAhead = aheadSnapshot.size;
        final perPerson = _getPerPersonMinutes(initialService);

        // Use driving time if available, otherwise estimate based on distance
        final drivingTime = drivingData?['minutes'] as int?;
        final waitMin = drivingTime != null
            ? ((peopleAhead * perPerson) + max(5, drivingTime)).toInt()
            : ((peopleAhead * perPerson) + max(5, distanceKm)).toInt();

        if (mounted) {
          setState(() {
            selectedBranchId = nearestBranch.id;
            selectedService = initialService;
            _autoPrefilled = true;
            _selectedDistanceKm = distanceKm;
            _peopleAhead = peopleAhead;
            _estimatedWaitMin = waitMin;
            _drivingKm = drivingData?['km'] as double?;
            _drivingMinutes = drivingData?['minutes'] as int?;
          });
        }
      }
    } catch (e) {
      print('Auto-select error: $e');
      // Fallback to straight-line distance if OSRM fails
      try {
        final position = await _getPrecisePosition();
        _userPosition = position;

        BranchModel? nearest;
        double? nearestDistanceKm;

        for (final b in _branches) {
          final km = await _computeDistanceKm(position, b);
          if (nearest == null || km < (nearestDistanceKm ?? double.infinity)) {
            nearest = b;
            nearestDistanceKm = km;
          }
        }

        if (nearest != null) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          String? preferredService;
          if (uid != null) {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            preferredService = userDoc.data()?['preferredService'] as String?;
          }

          final services = nearest.services;
          String? initialService;
          if (preferredService != null && services.contains(preferredService)) {
            initialService = preferredService;
          } else {
            initialService = services.isNotEmpty ? services.first : null;
          }

          final aheadSnapshot = await FirebaseFirestore.instance
              .collection('queue')
              .where('branchId', isEqualTo: nearest.id)
              .where('status', isEqualTo: 'pending')
              .get();
          final peopleAhead = aheadSnapshot.size;
          final perPerson = _getPerPersonMinutes(initialService);
          final waitMin =
              ((peopleAhead * perPerson) + max(5, (nearestDistanceKm!)))
                  .toInt();

          if (mounted) {
            setState(() {
              selectedBranchId = nearest!.id;
              selectedService = initialService;
              _autoPrefilled = true;
              _selectedDistanceKm = nearestDistanceKm;
              _peopleAhead = peopleAhead;
              _estimatedWaitMin = waitMin;
              _drivingKm = null; // No driving data available
              _drivingMinutes = null;
            });
          }
        }
      } catch (fallbackError) {
        print('Fallback auto-select error: $fallbackError');
      }
    } finally {
      // Hide loading dialog
      _hideRecommendationLoadingDialog();
    }
  }

  BranchModel? _getSelectedBranch() {
    if (selectedBranchId == null) return null;
    try {
      return _branches.firstWhere((b) => b.id == selectedBranchId);
    } catch (_) {
      return null;
    }
  }

  Future<void> confirmPayment() async {
    final branch = _getSelectedBranch();
    if (branch == null) {
      _showSnackBar('Please select a branch.');
      return;
    }

    if (selectedService == null || selectedService!.isEmpty) {
      _showSnackBar('Please select a service.');
      return;
    }

    if (selectedPaymentMethod == null) {
      _showSnackBar('Please select a payment method.');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;

      if (uid == null) {
        _showSnackBar('You must be signed in to join the queue.');
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = userDoc.data()?['fullName'] ?? 'Anonymous';

      // Check existing queue for user
      final existing = await FirebaseFirestore.instance
          .collection('queue')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        _showSnackBar('You already have an active queue.');
        return;
      }

      // Get next queue number per branch without requiring composite index
      final qSnap = await FirebaseFirestore.instance
          .collection('queue')
          .where('branchId', isEqualTo: branch.id)
          .where('status', isEqualTo: 'pending')
          .get();

      int nextQueueNumber = 1;
      if (qSnap.docs.isNotEmpty) {
        int maxQ = 0;
        for (final d in qSnap.docs) {
          final v = d.data()['queueNumber'];
          if (v is int && v > maxQ) maxQ = v;
        }
        nextQueueNumber = maxQ + 1;
      }

      // Compute real distance to selected branch
      final pos = _userPosition ?? await _getPrecisePosition();
      _userPosition = pos;
      final distKm = await _computeDistanceKm(pos, branch);
      Map<String, dynamic>? driving;
      try {
        driving = await _getDrivingDistanceAndTime(pos, branch);
      } catch (_) {}

      // Estimate wait time
      final perPerson = _getPerPersonMinutes(selectedService);
      final aheadSnapshot = await FirebaseFirestore.instance
          .collection('queue')
          .where('branchId', isEqualTo: branch.id)
          .where('status', isEqualTo: 'pending')
          .get();
      final peopleAhead = aheadSnapshot.size;
      final int waitTime = ((peopleAhead * perPerson) + max(5, distKm)).toInt();

      final doc = await FirebaseFirestore.instance.collection('queue').add({
        'uid': uid,
        'name': name,
        'branchName': branch.name,
        'branchId': branch.id,
        'queueNumber': nextQueueNumber,
        'service': selectedService,
        'requestedBarberId': _requestedBarberId,
        'requestedBarberNote': _requestedBarberNote,
        'preferAnyBarber': _requestedBarberId == null,
        'distanceKm': distKm,
        'drivingKm': driving?['km'],
        'timestamp': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'waitTimeMin': waitTime,
        'drivingMinutes': driving?['minutes'],
        'paymentMethod': selectedPaymentMethod,
        'userLat': pos.latitude,
        'userLng': pos.longitude,
      });

      // Save preferred service for next time (automation)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'preferredService': selectedService}, SetOptions(merge: true));

      NotificationService.showNotification(
        title: "You're now in the queue!",
        body: "Branch: ${branch.name} — Service: $selectedService",
      );

      final docId = doc.id;

      if (selectedPaymentMethod == 'Online') {
        final success = await Navigator.pushNamed(
          context,
          onlinePaymentRoute,
          arguments: docId,
        );

        if (success == true) {
          widget.onQueueConfirmed(docId);
          if (mounted) {
            setState(() {
              isPaymentAlert = false;
              queueNumber = '#Q$nextQueueNumber';
            });
          }
          _showSnackBar('Online payment confirmed and queue registered.');
          // Navigate to live queue tracking after queue is created
          if (mounted) {
            Navigator.pushNamed(
              context,
              queueMapTrackingRoute,
              arguments: docId,
            );
          }
        } else {
          await FirebaseFirestore.instance
              .collection('queue')
              .doc(docId)
              .delete();
          _showSnackBar('Payment cancelled. Queue not created.');
        }
        return;
      }

      // Over the counter
      widget.onQueueConfirmed(docId);
      if (mounted) {
        setState(() {
          isPaymentAlert = false;
          queueNumber = '#Q$nextQueueNumber';
        });
      }
      _showSnackBar('Queue confirmed and payment acknowledged.');
      // Navigate to live queue tracking after queue is created
      if (mounted) {
        Navigator.pushNamed(
          context,
          queueMapTrackingRoute,
          arguments: docId,
        );
      }
    } catch (e) {
      _showSnackBar('Something went wrong while confirming the queue.');
    }
  }

  void _showWhyBranchDialog(BranchModel branch) {
    final distance = _selectedDistanceKm;
    final eta = _estimatedWaitMin;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Why this branch?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• Nearest to your current location.'),
              if (distance != null)
                Text('• Approx. distance: ${_formatDistance(distance)}'),
              if (_peopleAhead != null)
                Text('• People ahead in queue: $_peopleAhead'),
              if (eta != null)
                Text('• Estimated wait time: ~${_formatWait(eta)}'),
              if (selectedService != null)
                Text("• Matches your preferred service: $selectedService"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final branches = _branches;
    final selectedBranch = _getSelectedBranch();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Quick refresh/reload functionality
          _initializeQueueing();
        },
        backgroundColor: const Color(0xFFD4AF37),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Modern Header with Gradient
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFD4AF37),
                      Color(0xFFB8941F),
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.explore,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Join a Queue',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Find the best barbershop near you',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
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
              ),

              // Content with padding
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selected branch summary card with enhanced design
                    if (selectedBranch != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Header with branch info
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                color: Color(0xFFD4AF37),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.store,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedBranch.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          selectedBranch.location,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _showWhyBranchDialog(selectedBranch),
                                    icon: const Icon(
                                      Icons.info_outline,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'Why this branch?',
                                  ),
                                ],
                              ),
                            ),

                            // Info chips section
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _EnhancedInfoChip(
                                    icon: Icons.near_me,
                                    label: _formatDistancePref(
                                        _selectedDistanceKm, _drivingKm),
                                    color: const Color(0xFF4CAF50),
                                  ),
                                  if (_peopleAhead != null)
                                    _EnhancedInfoChip(
                                      icon: Icons.people,
                                      label: 'Ahead: $_peopleAhead',
                                      color: const Color(0xFF2196F3),
                                    ),
                                  _EnhancedInfoChip(
                                    icon: Icons.timelapse,
                                    label: _formatWaitPref(
                                        _estimatedWaitMin, _drivingMinutes),
                                    color: const Color(0xFFFF9800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Enhanced Branch Selection
                    _CustomDropdownField(
                      label: 'Select Branch',
                      icon: Icons.store,
                      value: selectedBranchId,
                      onChanged: (value) async {
                        setState(() {
                          selectedBranchId = value;
                          selectedService = null;
                          _selectedDistanceKm = null;
                          _peopleAhead = null;
                          _estimatedWaitMin = null;
                          _drivingKm = null;
                          _drivingMinutes = null;
                        });

                        final branch = _getSelectedBranch();
                        if (branch != null) {
                          try {
                            final pos =
                                _userPosition ?? await _getPrecisePosition();
                            _userPosition = pos;

                            // Get both straight-line and driving distances
                            final straightLineDist =
                                await _computeDistanceKm(pos, branch);
                            final drivingData =
                                await _getDrivingDistanceAndTime(pos, branch);

                            // Use driving distance if available, otherwise fallback to straight-line
                            final distanceKm = drivingData?['km'] as double? ??
                                straightLineDist;

                            final aheadSnapshot = await FirebaseFirestore
                                .instance
                                .collection('queue')
                                .where('branchId', isEqualTo: branch.id)
                                .where('status', isEqualTo: 'pending')
                                .get();
                            final peopleAhead = aheadSnapshot.size;
                            final perPerson =
                                _getPerPersonMinutes(selectedService);

                            // Use driving time if available for more accurate wait estimation
                            final drivingTime = drivingData?['minutes'] as int?;
                            final waitMin = drivingTime != null
                                ? ((peopleAhead * perPerson) +
                                        max(5, drivingTime))
                                    .toInt()
                                : ((peopleAhead * perPerson) +
                                        max(5, distanceKm))
                                    .toInt();

                            setState(() {
                              _selectedDistanceKm = distanceKm;
                              _peopleAhead = peopleAhead;
                              _estimatedWaitMin = waitMin;
                              _drivingKm = drivingData?['km'] as double?;
                              _drivingMinutes = drivingData?['minutes'] as int?;
                            });
                          } catch (e) {
                            print(
                                'Error calculating distance for selected branch: $e');
                          }
                        }
                      },
                      items: branches
                          .map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text(
                                  '${b.name} • ${b.location}',
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ))
                          .toList(),
                    ),

                    const SizedBox(height: 20),

                    // Enhanced Service Selection
                    _CustomDropdownField(
                      label: 'Select Service',
                      icon: Icons.content_cut,
                      value: selectedService,
                      onChanged: (value) async {
                        setState(() => selectedService = value);
                        // Update ETA when service changes
                        final branch = _getSelectedBranch();
                        if (branch != null && _selectedDistanceKm != null) {
                          final aheadSnapshot = await FirebaseFirestore.instance
                              .collection('queue')
                              .where('branchId', isEqualTo: branch.id)
                              .where('status', isEqualTo: 'pending')
                              .get();
                          final peopleAhead = aheadSnapshot.size;
                          final perPerson =
                              _getPerPersonMinutes(selectedService);
                          setState(() {
                            _peopleAhead = peopleAhead;
                            _estimatedWaitMin = ((peopleAhead * perPerson) +
                                    max(5, _selectedDistanceKm!))
                                .toInt();
                          });
                        }
                      },
                      items: (selectedBranch?.services ?? [])
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),

                    // Enhanced Payment Section
                    if (isPaymentAlert)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFD4AF37).withOpacity(0.1),
                              const Color(0xFFB8941F).withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFD4AF37).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4AF37)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.payment,
                                      color: Color(0xFFD4AF37),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _autoPrefilled
                                          ? 'Review & Confirm Queue'
                                          : 'Complete Your Queue',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A0F0A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _autoPrefilled
                                    ? 'We\'ve found the best option for you. Review and confirm your Queue.'
                                    : 'Please complete your booking details below.',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Payment Method Selection
                              _CustomDropdownField(
                                label: 'Payment Method',
                                icon: Icons.credit_card,
                                value: selectedPaymentMethod,
                                onChanged: (value) => setState(
                                    () => selectedPaymentMethod = value),
                                items: paymentMethods
                                    .map((method) => DropdownMenuItem(
                                          value: method,
                                          child: Text(
                                            method,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ))
                                    .toList(),
                              ),

                              const SizedBox(height: 20),

                              // Barber Preference Selection
                              _CustomDropdownField(
                                label: 'Barber Preference',
                                icon: Icons.person,
                                value: _barberPreference,
                                onChanged: (value) async {
                                  if (value == null) return;
                                  setState(() {
                                    _barberPreference = value;
                                  });
                                  if (value == 'Request a specific barber') {
                                    // Ask for a note (barber name or seat #) without querying users
                                    final controller = TextEditingController(
                                        text: _requestedBarberNote ?? '');
                                    final note = await showDialog<String>(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          title: const Text(
                                              'Request a specific barber'),
                                          content: TextField(
                                            controller: controller,
                                            maxLength: 50,
                                            decoration: const InputDecoration(
                                              hintText:
                                                  'Enter barber name or seat #',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(
                                                  context,
                                                  controller.text.trim()),
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (!mounted) return;
                                    if (note == null || note.isEmpty) {
                                      setState(() {
                                        _barberPreference =
                                            'Any available barber';
                                        _requestedBarberId = null;
                                        _requestedBarberNote = null;
                                      });
                                    } else {
                                      setState(() {
                                        _requestedBarberId =
                                            null; // not used in this mode
                                        _requestedBarberNote =
                                            note; // save note
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _requestedBarberId = null;
                                      _requestedBarberNote = null;
                                    });
                                  }
                                },
                                items: _preferenceOptions
                                    .map((o) => DropdownMenuItem(
                                          value: o,
                                          child: Text(
                                            o,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ))
                                    .toList(),
                              ),

                              const SizedBox(height: 24),

                              // Enhanced Action Button
                              Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFD4AF37),
                                      Color(0xFFB8941F),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD4AF37)
                                          .withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: confirmPayment,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.flash_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Join Queue Now',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Enhanced Info Chip with better styling
class _EnhancedInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EnhancedInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Dropdown Field with enhanced styling
class _CustomDropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final List<DropdownMenuItem<String>> items;

  const _CustomDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFFD4AF37)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: const TextStyle(
            color: Color(0xFF1A0F0A),
            fontWeight: FontWeight.w500,
          ),
        ),
        value: value,
        onChanged: onChanged,
        items: items,
        dropdownColor: Colors.white,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF1A0F0A),
        ),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Color(0xFFD4AF37),
        ),
      ),
    );
  }
}

// Loading Dot Animation
class _LoadingDot extends StatefulWidget {
  final int delay;

  const _LoadingDot({required this.delay});

  @override
  State<_LoadingDot> createState() => _LoadingDotState();
}

class _LoadingDotState extends State<_LoadingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37)
                .withOpacity(0.3 + (_animation.value * 0.7)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
