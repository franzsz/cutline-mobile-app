import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class CashierTransactionHistoryScreen extends StatefulWidget {
  final String branchId;
  const CashierTransactionHistoryScreen({super.key, required this.branchId});

  @override
  State<CashierTransactionHistoryScreen> createState() =>
      _CashierTransactionHistoryScreenState();
}

class _CashierTransactionHistoryScreenState
    extends State<CashierTransactionHistoryScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _search = '';
  final Set<String> _statusFilters = {'Completed'};
  final Map<String, String> _uidToNameCache = {};
  final Map<String, String> _barberIdToNameCache = {};
  Timer? _searchDebounce;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    // Set default date range to last 30 days
    _endDate = DateTime.now();
    _startDate = DateTime.now().subtract(const Duration(days: 30));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _transactionStream() {
    // Ensure we have at least one status filter to avoid empty 'in' filter error
    if (_statusFilters.isEmpty) {
      return Stream.empty();
    }

    Query<Map<String, dynamic>> query = _db
        .collection('transactions')
        .where('branchId', isEqualTo: widget.branchId)
        .where('status', whereIn: _statusFilters.toList())
        .orderBy('completedAt', descending: true);

    // Add date range filter if specified
    if (_startDate != null) {
      query = query.where('completedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
    }
    if (_endDate != null) {
      final endOfDay =
          DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      query = query.where('completedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    return query.snapshots();
  }

  Future<String> _getUserName(String uid) async {
    if (uid == 'walk-in') return 'Walk-in';
    if (_uidToNameCache.containsKey(uid)) return _uidToNameCache[uid]!;

    try {
      final doc = await _db.collection('users').doc(uid).get();
      final name = doc.data()?['fullName'] ?? 'Unknown';
      _uidToNameCache[uid] = name;
      return name;
    } catch (_) {
      _uidToNameCache[uid] = 'Unknown';
      return 'Unknown';
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Transaction Details',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Transaction ID',
                              transaction['transactionId'] ?? 'N/A'),
                          _buildDetailRow(
                              'Customer', transaction['name'] ?? 'Walk-in'),
                          _buildDetailRow(
                              'Barber',
                              transaction['barberName'] ??
                                  _barberIdToNameCache[
                                      transaction['barberId']?.toString() ??
                                          ''] ??
                                  'Not Assigned'),
                          _buildDetailRow('Queue Number',
                              transaction['queueNumber']?.toString() ?? 'N/A'),
                          _buildDetailRow('Payment Method',
                              transaction['paymentMethod'] ?? 'N/A'),
                          _buildDetailRow('Amount',
                              '₱${(transaction['paymentAmount'] ?? 0).toStringAsFixed(2)}'),
                          _buildDetailRow(
                              'Status', transaction['status'] ?? 'N/A'),
                          if (transaction['service'] != null)
                            _buildDetailRow('Service', transaction['service']),
                          if (transaction['additionalServices'] != null &&
                              (transaction['additionalServices'] as List)
                                  .isNotEmpty)
                            _buildDetailRow(
                                'Additional Services',
                                (transaction['additionalServices'] as List)
                                    .join(', ')),
                          if (transaction['assignedSeatNumber'] != null)
                            _buildDetailRow('Seat Number',
                                transaction['assignedSeatNumber']),
                          if (transaction['completedAt'] != null)
                            _buildDetailRow(
                                'Completed At',
                                DateFormat.yMMMd().add_jm().format(
                                    transaction['completedAt'].toDate())),
                          if (transaction['createdAt'] != null)
                            _buildDetailRow(
                                'Created At',
                                DateFormat.yMMMd()
                                    .add_jm()
                                    .format(transaction['createdAt'].toDate())),
                          if (transaction['cashierId'] != null)
                            _buildDetailRow(
                                'Cashier ID', transaction['cashierId']),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hydrateNameCache(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final Set<String> neededUids = {};
    final Set<String> neededBarberIds = {};

    for (final d in docs) {
      final uid = (d.data()['uid'] ?? '').toString();
      if (uid.isNotEmpty &&
          uid != 'walk-in' &&
          !_uidToNameCache.containsKey(uid)) {
        neededUids.add(uid);
      }

      final barberId = (d.data()['barberId'] ?? '').toString();
      if (barberId.isNotEmpty &&
          barberId != 'walk-in' &&
          !_barberIdToNameCache.containsKey(barberId)) {
        neededBarberIds.add(barberId);
      }
    }

    // Cache customer names
    for (final uid in neededUids) {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        final name =
            (userDoc.data()?['fullName']?.toString() ?? 'Unknown').trim();
        _uidToNameCache[uid] = name.isEmpty ? 'Unknown' : name;
      } catch (_) {
        _uidToNameCache[uid] = 'Unknown';
      }
    }

    // Cache barber names
    for (final barberId in neededBarberIds) {
      try {
        final userDoc = await _db.collection('users').doc(barberId).get();
        final name =
            (userDoc.data()?['fullName']?.toString() ?? 'Unknown Barber')
                .trim();
        _barberIdToNameCache[barberId] = name.isEmpty ? 'Unknown Barber' : name;
      } catch (_) {
        _barberIdToNameCache[barberId] = 'Unknown Barber';
      }
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Date Range',
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText:
                    'Search customer name, barber name, transaction ID, or queue number...',
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

          // Date range display
          if (_startDate != null && _endDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat.yMMMd().format(_startDate!)} - ${DateFormat.yMMMd().format(_endDate!)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        // Reset to default range (last 30 days) instead of null
                        _endDate = DateTime.now();
                        _startDate =
                            DateTime.now().subtract(const Duration(days: 30));
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),

          // Status filters
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Completed'),
                  selected: _statusFilters.contains('Completed'),
                  onSelected: (sel) => setState(() {
                    if (sel)
                      _statusFilters.add('Completed');
                    else
                      _statusFilters.remove('Completed');
                  }),
                ),
              ],
            ),
          ),

          // Transaction list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _transactionStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child:
                          Text('Error loading transactions: ${snapshot.error}'),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data?.docs ?? [];

                // Warm the name cache for current snapshot so search by name works
                // ignore: unawaited_futures
                _hydrateNameCache(allDocs);

                // Apply client-side search filter only (status/date filtering is done server-side)
                final filtered = allDocs.where((d) {
                  final data = d.data();
                  if (_search.isEmpty) return true;

                  final transactionId =
                      (data['transactionId'] ?? '').toString().toLowerCase();
                  final queueNumber =
                      (data['queueNumber'] ?? '').toString().toLowerCase();
                  final customerName =
                      (data['name'] ?? '').toString().toLowerCase();
                  final uid = (data['uid'] ?? '').toString();
                  final displayName =
                      (_uidToNameCache[uid] ?? uid).toLowerCase();
                  final barberId = (data['barberId'] ?? '').toString();
                  final storedBarberName =
                      (data['barberName'] ?? '').toString().toLowerCase();
                  final cachedBarberName =
                      (_barberIdToNameCache[barberId] ?? 'not assigned')
                          .toLowerCase();
                  final barberName = storedBarberName.isNotEmpty
                      ? storedBarberName
                      : cachedBarberName;
                  final paymentMethod =
                      (data['paymentMethod'] ?? '').toString().toLowerCase();
                  final service =
                      (data['service'] ?? '').toString().toLowerCase();

                  return transactionId.contains(_search) ||
                      queueNumber.contains(_search) ||
                      customerName.contains(_search) ||
                      displayName.contains(_search) ||
                      barberName.contains(_search) ||
                      paymentMethod.contains(_search) ||
                      service.contains(_search);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No transactions found.'),
                        const SizedBox(height: 8),
                        Text('Branch: ${widget.branchId}',
                            style: const TextStyle(color: Colors.grey)),
                        if (_search.isNotEmpty)
                          Text('Search: "$_search"',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data();
                      final String status = data['status'] ?? 'Completed';
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
                            child: InkWell(
                              onTap: () => _showTransactionDetails(data),
                              borderRadius: BorderRadius.circular(12),
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
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '₱${(data['paymentAmount'] ?? 0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Chip(
                                          label: Text(status),
                                          backgroundColor: Colors.green[100],
                                        ),
                                        if (data['queueNumber'] != null)
                                          Chip(
                                            avatar: const Icon(Icons.queue,
                                                size: 16),
                                            label:
                                                Text('#${data['queueNumber']}'),
                                            backgroundColor: Colors.blue[100],
                                          ),
                                        if (data['assignedSeatNumber'] != null)
                                          Chip(
                                            avatar: const Icon(Icons.event_seat,
                                                size: 16),
                                            label: Text(
                                                'Seat ${data['assignedSeatNumber']}'),
                                            backgroundColor: Colors.orange[100],
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.payment,
                                            size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 4),
                                        Text(
                                          data['paymentMethod'] ?? 'N/A',
                                          style: TextStyle(
                                              color: Colors.grey[600]),
                                        ),
                                        const Spacer(),
                                        if (data['completedAt'] != null)
                                          Text(
                                            DateFormat.yMMMd().add_jm().format(
                                                data['completedAt'].toDate()),
                                            style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12),
                                          ),
                                      ],
                                    ),
                                    // Barber information
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person,
                                              size: 14,
                                              color: Colors.grey[600]),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Barber: ${data['barberName'] ?? _barberIdToNameCache[data['barberId']?.toString() ?? ''] ?? 'Not Assigned'}',
                                            style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (data['service'] != null ||
                                        (data['additionalServices'] != null &&
                                            (data['additionalServices'] as List)
                                                .isNotEmpty))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Services: ${data['service'] ?? ''}${data['additionalServices'] != null && (data['additionalServices'] as List).isNotEmpty ? ' + ${(data['additionalServices'] as List).join(', ')}' : ''}',
                                          style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                  ],
                                ),
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
      'login_employee',
      (route) => false,
    );
  }
}
