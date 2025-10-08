import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shop/route/route_constants.dart';

class CashierQueueScreen extends StatefulWidget {
  final String branchId;
  const CashierQueueScreen({super.key, required this.branchId});

  @override
  State<CashierQueueScreen> createState() => _CashierQueueScreenState();
}

class _CashierQueueScreenState extends State<CashierQueueScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _search = '';
  final Set<String> _statusFilters = {'pending', 'in_service'};
  final Map<String, String> _uidToNameCache = {};
  Timer? _searchDebounce;
  double? _branchLat;
  double? _branchLng;

  int? _parseSeatFromNote(String? note) {
    if (note == null) return null;
    final s = note.toLowerCase();
    final RegExp re = RegExp(r"(seat\s*)?(\d+)");
    final m = re.firstMatch(s);
    if (m != null) {
      final numStr = m.groupCount >= 2 ? m.group(2) : m.group(0);
      if (numStr != null) return int.tryParse(numStr);
    }
    return null;
  }

  Future<bool> _assignSpecificSeat({
    required String queueId,
    required int seatNumber,
  }) async {
    // Verify seat not occupied for this branch by an in-service queue
    final qDoc = await _db.collection('queue').doc(queueId).get();
    final qData = qDoc.data() ?? {};
    final String branchId = qData['branchId'] ?? widget.branchId;

    final inService = await _db
        .collection('queue')
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'in_service')
        .get();
    for (final d in inService.docs) {
      final s = d.data()['assignedSeatNumber'];
      final sInt = s is int ? s : (s is String ? int.tryParse(s) : null);
      if (sInt == seatNumber) {
        return false;
      }
    }
    await _db.collection('queue').doc(queueId).update({
      'assignedSeatNumber': seatNumber.toString(),
      'assignedSeatAvailable': true,
    });
    return true;
  }

  Future<void> _autoAssignSeat(String queueId) async {
    final qSnap = await _db.collection('queue').doc(queueId).get();
    final qData = qSnap.data() ?? {};
    if (qData['assignedSeatNumber'] != null &&
        qData['assignedSeatNumber'].toString().isNotEmpty) return;
    final String branchId = qData['branchId'] ?? widget.branchId;

    final inService = await _db
        .collection('queue')
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'in_service')
        .get();
    final Set<int> occupied = {};
    for (final d in inService.docs) {
      final s = d.data()['assignedSeatNumber'];
      if (s is String) {
        final v = int.tryParse(s);
        if (v != null) occupied.add(v);
      } else if (s is int) {
        occupied.add(s);
      }
    }
    int chosen = 1;
    while (occupied.contains(chosen) && chosen <= 5) {
      chosen++;
    }
    await _db.collection('queue').doc(queueId).update({
      'assignedSeatNumber': chosen.toString(),
      'assignedSeatAvailable': true,
    });
  }

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('[CashierQueue] listening for branchId=${widget.branchId}');
    _loadBranchLocation();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _queueStream() {
    return _db
        .collection('queue')
        .where('branchId', isEqualTo: widget.branchId)
        .where('status', whereIn: ['pending', 'in_service'])
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> _loadBranchLocation() async {
    try {
      final doc = await _db.collection('branches').doc(widget.branchId).get();
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
      if (!mounted) return;
      setState(() {
        _branchLat = lat;
        _branchLng = lng;
      });
    } catch (_) {}
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // meters
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLon = (lon2 - lon1) * math.pi / 180.0;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  // Barber list is not used in this simplified seat assignment flow

  Future<void> _assignBarber(String queueId) async {
    if (!mounted) return;
    final qDoc = await _db.collection('queue').doc(queueId).get();
    final qData = qDoc.data() ?? {};
    final TextEditingController seatController = TextEditingController(
      text: (qData['assignedSeatNumber']?.toString() ?? ''),
    );
    bool seatAvailable = qData['assignedSeatAvailable'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Assign Seat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: seatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seat number',
                  hintText: 'e.g. 1, 2, 3...',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Seat available'),
                  const Spacer(),
                  StatefulBuilder(
                    builder: (context, setStateSB) {
                      return Switch(
                        value: seatAvailable,
                        onChanged: (v) => setStateSB(() => seatAvailable = v),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final String? seatValue = seatController.text.trim().isEmpty
          ? null
          : seatController.text.trim();
      // If seat is specified, ensure exclusivity within branch among in_service
      if (seatValue != null && seatValue.isNotEmpty) {
        final qDoc = await _db.collection('queue').doc(queueId).get();
        final qData = qDoc.data() ?? {};
        final String branchId = qData['branchId'] ?? widget.branchId;
        final inService = await _db
            .collection('queue')
            .where('branchId', isEqualTo: branchId)
            .where('status', isEqualTo: 'in_service')
            .where('assignedSeatNumber', isEqualTo: seatValue)
            .get();
        if (inService.docs.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Seat $seatValue is currently occupied')),
            );
          }
          return;
        }
      }
      await _db.collection('queue').doc(queueId).update({
        'assignedSeatNumber': seatValue,
        'assignedSeatAvailable': seatAvailable,
      });
    }
  }

  // Reassign is same as assign in this UI

  Future<void> _startService(String queueId) async {
    // Auto-assign first available seat if customer prefers any barber and no seat assigned yet
    final qSnap = await _db.collection('queue').doc(queueId).get();
    final qData = qSnap.data() ?? {};
    String? seat = (qData['assignedSeatNumber'] as String?);
    final bool prefersAny = qData['preferAnyBarber'] == true ||
        (qData['requestedBarberId'] == null);
    final String branchId = qData['branchId'] ?? widget.branchId;

    if (seat == null && prefersAny) {
      // Collect seats currently in use (in_service) for this branch
      final inService = await _db
          .collection('queue')
          .where('branchId', isEqualTo: branchId)
          .where('status', isEqualTo: 'in_service')
          .get();
      final Set<int> occupied = {};
      for (final d in inService.docs) {
        final s = d.data()['assignedSeatNumber'];
        if (s is String) {
          final v = int.tryParse(s);
          if (v != null) occupied.add(v);
        } else if (s is int) {
          occupied.add(s);
        }
      }
      // Pick the smallest available seat number from 1..50
      int chosen = 1;
      while (occupied.contains(chosen) && chosen <= 50) {
        chosen++;
      }
      seat = chosen.toString();
      await _db.collection('queue').doc(queueId).update({
        'assignedSeatNumber': seat,
        'assignedSeatAvailable': true,
      });
    }
    // If a seat is set, ensure exclusivity before starting
    if (seat != null && seat.isNotEmpty) {
      final inServiceSameSeat = await _db
          .collection('queue')
          .where('branchId', isEqualTo: branchId)
          .where('status', isEqualTo: 'in_service')
          .where('assignedSeatNumber', isEqualTo: seat)
          .get();
      if (inServiceSameSeat.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Seat $seat is occupied. Choose another.')),
          );
        }
        return;
      }
    }

    await _db.collection('queue').doc(queueId).update({
      'status': 'in_service',
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _finishService(String queueId) async {
    // Show payment input dialog first
    final paymentData = await _showPaymentDialog();
    if (paymentData == null) return; // User cancelled

    final paymentAmount = paymentData['amount'] as double;
    final paymentMethod = paymentData['method'] as String;

    // Get the queue document data before deleting
    final queueDoc = await _db.collection('queue').doc(queueId).get();
    if (!queueDoc.exists) return;

    final queueData = queueDoc.data()!;

    // Create transaction record with queue data and payment amount
    final String? cashierUid = FirebaseAuth.instance.currentUser?.uid;
    final String? customerUid =
        (queueData['uid'] as String?)?.isNotEmpty == true
            ? queueData['uid'] as String
            : (queueData['customerId'] as String?);
    final transactionData = {
      ...queueData,
      // Normalize to capitalized to align with history filters
      'status': 'Completed',
      'completedAt': FieldValue.serverTimestamp(),
      'transactionId': queueId, // Keep original queue ID as transaction ID
      'createdAt': queueData['createdAt'] ?? FieldValue.serverTimestamp(),
      'paymentAmount': paymentAmount,
      'paymentMethod': paymentMethod,
      // Fields required by Firestore rules and history queries
      // `uid` should be the customer for customer transaction history
      'uid': customerUid,
      'cashierId': cashierUid,
      'customerId': customerUid,
      'barberId': queueData['barberId'] ?? queueData['requestedBarberId'],
    };

    // Add to transactions collection
    await _db.collection('transactions').doc(queueId).set(transactionData);

    // Delete from queue collection
    await _db.collection('queue').doc(queueId).delete();

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Service completed! Payment: ₱${paymentAmount.toStringAsFixed(2)} via $paymentMethod'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _cancelQueue(String queueId) async {
    // Delete the queue document completely when cancelled
    await _db.collection('queue').doc(queueId).delete();
  }

  Future<void> _togglePriority(String queueId, bool current) async {
    await _db.collection('queue').doc(queueId).update({
      'priority': !current,
      'priorityAt': !current ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<String> _getUserName(String uid) async {
    if (uid == 'walk-in') return 'Walk-in';
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['fullName'] ?? 'Unknown';
  }

  String _formatEta(dynamic etaMeters) {
    if (etaMeters == null) return '';
    final meters = etaMeters is num
        ? etaMeters.toDouble()
        : (etaMeters is String ? double.tryParse(etaMeters) : null);
    if (meters == null) return '';

    if (meters < 1000) {
      return '${meters.round()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    final TextEditingController amountController = TextEditingController();
    String? selectedPaymentMethod = 'Cash';

    return await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Complete Service'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter payment amount:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      prefixText: '₱',
                      labelText: 'Amount',
                      hintText: '0.00',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      // Format the input to show currency
                      final cleanValue =
                          value.replaceAll(RegExp(r'[^\d.]'), '');
                      if (cleanValue != value) {
                        amountController.value =
                            amountController.value.copyWith(
                          text: cleanValue,
                          selection: TextSelection.collapsed(
                              offset: cleanValue.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Payment Method:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedPaymentMethod,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'Card', child: Text('Card')),
                      DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                      DropdownMenuItem(
                          value: 'PayMaya', child: Text('PayMaya')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedPaymentMethod = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amountText = amountController.text.trim();
                    if (amountText.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a payment amount'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final amount = double.tryParse(amountText);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context, {
                      'amount': amount,
                      'method': selectedPaymentMethod!,
                    });
                  },
                  child: const Text('Complete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _hydrateNameCache(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final Set<String> needed = {};
    for (final d in docs) {
      final uid = (d.data()['uid'] ?? '').toString();
      if (uid.isEmpty || uid == 'walk-in') continue;
      if (!_uidToNameCache.containsKey(uid)) needed.add(uid);
    }
    if (needed.isEmpty) return;
    for (final uid in needed) {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        final name =
            (userDoc.data()?['fullName']?.toString() ?? 'Unknown').trim();
        _uidToNameCache[uid] = name.isEmpty ? 'Unknown' : name;
      } catch (_) {
        _uidToNameCache[uid] = 'Unknown';
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Queue'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search customer name or seat...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                  if (!mounted) return;
                  setState(() => _search = v.trim().toLowerCase());
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Pending'),
                  selected: _statusFilters.contains('pending'),
                  onSelected: (sel) => setState(() {
                    if (sel)
                      _statusFilters.add('pending');
                    else
                      _statusFilters.remove('pending');
                  }),
                ),
                FilterChip(
                  label: const Text('In Service'),
                  selected: _statusFilters.contains('in_service'),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _statusFilters.add('in_service');
                    } else {
                      _statusFilters.remove('in_service');
                    }
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _queueStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error loading queue: ${snapshot.error}'),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Get docs (already filtered server-side) and sort client-side as needed
                final allDocs = snapshot.data?.docs ?? [];
                print('[CashierQueue] Total docs received: ${allDocs.length}');

                // Debug: Print all documents
                for (int i = 0; i < allDocs.length; i++) {
                  final doc = allDocs[i];
                  final data = doc.data();
                  print(
                      '[CashierQueue] Doc $i: id=${doc.id}, branchId=${data['branchId']}, status=${data['status']}, uid=${data['uid']}');
                }

                final docs = allDocs.toList();

                // Warm the name cache for current snapshot so search by name works
                // ignore: unawaited_futures
                _hydrateNameCache(docs);

                print(
                    '[CashierQueue] Filtered docs (pending/in_service): ${docs.length}');

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No customers in queue.'),
                        const SizedBox(height: 8),
                        Text('Branch: ${widget.branchId}',
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('Total docs: ${allDocs.length}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  );
                }

                // Align sorting with customer screen: locked first, then by lockedQueuePosition,
                // then by distance (etaMeters/drivingKm) and finally createdAt.
                int compareEntries(
                    QueryDocumentSnapshot<Map<String, dynamic>> a,
                    QueryDocumentSnapshot<Map<String, dynamic>> b) {
                  final da = a.data();
                  final db = b.data();

                  final bool aLocked =
                      (da['proximityConfirmed'] as bool?) ?? false;
                  final bool bLocked =
                      (db['proximityConfirmed'] as bool?) ?? false;

                  // Locked positions always come first and maintain their fixed position
                  if (aLocked && bLocked) {
                    final num aLockedPos =
                        (da['lockedQueuePosition'] as num?) ?? double.maxFinite;
                    final num bLockedPos =
                        (db['lockedQueuePosition'] as num?) ?? double.maxFinite;
                    return aLockedPos.compareTo(bLockedPos);
                  }

                  if (aLocked != bLocked) return aLocked ? -1 : 1;

                  double distanceOf(Map<String, dynamic> d) {
                    final eta = d['etaMeters'];
                    final drivingKm = d['drivingKm'];
                    if (eta is num) return eta.toDouble();
                    if (eta is String) {
                      final v = double.tryParse(eta);
                      if (v != null) return v;
                    }
                    if (drivingKm is num) return drivingKm.toDouble() * 1000.0;
                    if (drivingKm is String) {
                      final v = double.tryParse(drivingKm);
                      if (v != null) return v * 1000.0;
                    }
                    final lat = (d['userLat'] as num?)?.toDouble();
                    final lng = (d['userLng'] as num?)?.toDouble();
                    if (lat != null &&
                        lng != null &&
                        _branchLat != null &&
                        _branchLng != null) {
                      return _haversineMeters(
                          lat, lng, _branchLat!, _branchLng!);
                    }
                    return double.maxFinite;
                  }

                  // For unlocked positions, sort by creation time (first come, first served)
                  // This ensures unlocked positions don't jump ahead of each other
                  final ta = da['createdAt'];
                  final tb = db['createdAt'];
                  if (ta is Timestamp && tb is Timestamp)
                    return ta.compareTo(tb);
                  return 0;
                }

                docs.sort(compareEntries);

                // Build occupied seat set for the seat board (from in_service docs)
                final Set<int> occupiedSeats = {
                  for (final d in docs)
                    ...(() {
                      final s = d.data()['status'];
                      if (s != 'in_service') return <int>{};
                      final v = d.data()['assignedSeatNumber'];
                      int? seat;
                      if (v is int) seat = v;
                      if (v is String) seat = int.tryParse(v);
                      return seat != null ? {seat} : <int>{};
                    })()
                };

                // Apply client-side search and status filters
                final filtered = docs.where((d) {
                  final data = d.data();
                  final status = (data['status'] ?? '').toString();
                  if (!_statusFilters.contains(status)) return false;
                  if (_search.isEmpty) return true;
                  final seat = (data['assignedSeatNumber'] ?? '').toString();
                  final uid = (data['uid'] ?? '').toString();
                  final queueNumber = (data['queueNumber'] ?? '').toString();
                  final note = (data['requestedBarberNote'] ?? '').toString();
                  final displayName =
                      (_uidToNameCache[uid] ?? uid).toLowerCase();
                  final nameMatch = displayName.contains(_search);
                  final seatMatch = seat.toLowerCase().contains(_search);
                  final queueMatch =
                      queueNumber.toLowerCase().contains(_search);
                  final statusMatch = status.toLowerCase().contains(_search);
                  final noteMatch = note.toLowerCase().contains(_search);
                  return nameMatch ||
                      seatMatch ||
                      queueMatch ||
                      statusMatch ||
                      noteMatch;
                }).toList();

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data();
                      final String status = data['status'] ?? 'pending';
                      final bool isPriority = data['priority'] == true;
                      final String uid = data['uid'] ?? 'walk-in';

                      return FutureBuilder<String>(
                        future: uid == 'walk-in'
                            ? Future.value(
                                ((data['name'] as String?)?.trim().isNotEmpty ==
                                        true)
                                    ? (data['name'] as String)
                                    : 'Walk-in')
                            : _getUserName(uid),
                        builder: (context, snap) {
                          final name = snap.data ?? 'Customer';
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (isPriority)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Icon(Icons.star,
                                              color: Colors.amber),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (index == 0)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: List.generate(5, (i) {
                                          final seatNo = i + 1;
                                          final busy =
                                              occupiedSeats.contains(seatNo);
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.event_seat,
                                                color: busy
                                                    ? Colors.red
                                                    : Colors.green,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Seat $seatNo',
                                                style: TextStyle(
                                                  color: busy
                                                      ? Colors.red
                                                      : Colors.green,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ActionChip(
                                        avatar: const Icon(Icons.event_seat,
                                            size: 18),
                                        label: Text(
                                          (data['assignedSeatNumber'] == null ||
                                                  (data['assignedSeatNumber']
                                                      .toString()
                                                      .isEmpty))
                                              ? 'Assign seat'
                                              : 'Update seat',
                                        ),
                                        onPressed: () => _assignBarber(doc.id),
                                      ),
                                      if ((data['preferAnyBarber'] == true ||
                                              data['requestedBarberId'] ==
                                                  null) &&
                                          (data['assignedSeatNumber'] == null ||
                                              data['assignedSeatNumber']
                                                  .toString()
                                                  .isEmpty))
                                        ActionChip(
                                          avatar: const Icon(Icons.auto_awesome,
                                              size: 18),
                                          label: const Text('Auto-assign seat'),
                                          onPressed: () =>
                                              _autoAssignSeat(doc.id),
                                        ),
                                      if (status == 'pending')
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _startService(doc.id),
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text('Start'),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 36),
                                          ),
                                        ),
                                      if (status == 'in_service')
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _finishService(doc.id),
                                          icon: const Icon(Icons.check),
                                          label: const Text('Finish'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 36),
                                          ),
                                        ),
                                      TextButton.icon(
                                        onPressed: () => _cancelQueue(doc.id),
                                        icon: const Icon(Icons.close,
                                            color: Colors.red),
                                        label: const Text('Cancel',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Chip(
                                        label: Text(status.toUpperCase()),
                                        backgroundColor: status == 'pending'
                                            ? Colors.orange[100]
                                            : Colors.green[100],
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onLongPress: () =>
                                            _togglePriority(doc.id, isPriority),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isPriority
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.amber,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text('Priority'),
                                          ],
                                        ),
                                      ),
                                      // Show ETA if available
                                      if (data['etaMeters'] != null) ...[
                                        const SizedBox(width: 8),
                                        Chip(
                                          avatar: const Icon(Icons.location_on,
                                              size: 16),
                                          label: Text(
                                              _formatEta(data['etaMeters'])),
                                          backgroundColor: Colors.blue[100],
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (data['requestedBarberNote'] != null &&
                                      (data['requestedBarberNote'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Request: ${data['requestedBarberNote']}',
                                        style: const TextStyle(
                                            color: Colors.brown),
                                      ),
                                    ),
                                  Builder(builder: (context) {
                                    final note =
                                        data['requestedBarberNote'] as String?;
                                    int? reqSeat;
                                    try {
                                      reqSeat = _parseSeatFromNote(note);
                                    } catch (_) {}
                                    if (reqSeat != null &&
                                        (data['assignedSeatNumber'] == null ||
                                            data['assignedSeatNumber']
                                                .toString()
                                                .isEmpty)) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            final ok =
                                                await _assignSpecificSeat(
                                              queueId: doc.id,
                                              seatNumber: reqSeat!,
                                            );
                                            if (ok && mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Assigned seat $reqSeat')),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Seat $reqSeat is occupied')),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.event_seat),
                                          label: Text('Assign seat $reqSeat'),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 36),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }),
                                  if (data['assignedSeatNumber'] != null)
                                    Text('Seat: ${data['assignedSeatNumber']}'),
                                  if (data['assignedSeatAvailable'] != null)
                                    Text('Seat Availability: '
                                        '${data['assignedSeatAvailable'] == true ? 'Available' : 'Busy'}'),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWalkIn,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Walk-in'),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('logs')
              .add({
            'type': 'logout',
            'timestamp': Timestamp.now(),
          });
        } catch (_) {
          // best-effort logging; ignore failures
        }
      }
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      LoginEmployeeScreenRoute,
      (route) => false,
    );
  }

  Future<void> _addWalkIn() async {
    final TextEditingController nameController = TextEditingController();
    String? selectedService;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text('Add Walk-in Customer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer name (required)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedService,
                  decoration: const InputDecoration(
                    labelText: 'Service (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Haircut', child: Text('Haircut')),
                    DropdownMenuItem(value: 'Shave', child: Text('Shave')),
                    DropdownMenuItem(
                        value: 'Haircut + Shave',
                        child: Text('Haircut + Shave')),
                    DropdownMenuItem(value: 'Color', child: Text('Color')),
                  ],
                  onChanged: (v) => setStateSB(() => selectedService = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter customer name')),
                      );
                      return;
                    }
                    // Compute next queue number for this branch (pending only)
                    final qSnap = await _db
                        .collection('queue')
                        .where('branchId', isEqualTo: widget.branchId)
                        .where('status', isEqualTo: 'pending')
                        .get();
                    int nextQueueNumber = 1;
                    int nextLockIndex = 1;
                    for (final d in qSnap.docs) {
                      final v = d.data()['queueNumber'];
                      if (v is int && v >= nextQueueNumber) {
                        nextQueueNumber = v + 1;
                      }
                      final li = d.data()['lockIndex'];
                      if (li is num && li.toInt() >= nextLockIndex) {
                        nextLockIndex = li.toInt() + 1;
                      }
                    }

                    final Map<String, dynamic> payload = {
                      'branchId': widget.branchId,
                      'status': 'pending',
                      'uid': 'walk-in',
                      'preferAnyBarber': true,
                      'createdAt': FieldValue.serverTimestamp(),
                      'queueNumber': nextQueueNumber,
                      'proximityConfirmed': true,
                      'proximityConfirmedAt': FieldValue.serverTimestamp(),
                      'lockIndex': nextLockIndex,
                      'lockedQueuePosition':
                          nextLockIndex, // Store the fixed queue position
                    };
                    payload['name'] = name;
                    if (selectedService != null)
                      payload['service'] = selectedService;

                    await _db.collection('queue').add(payload);
                    if (!mounted) return;
                    Navigator.pop(context, {'ok': true});
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.pop(context, {'error': e.toString()});
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );

    if (data == null) return;
    if (data['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add walk-in: ${data['error']}')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Walk-in added to queue')),
    );
  }
}
