import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class QueueManagementPage extends StatefulWidget {
  const QueueManagementPage({super.key});

  @override
  State<QueueManagementPage> createState() => _QueueManagementPageState();
}

class _QueueManagementPageState extends State<QueueManagementPage> {
  final double shopLat = 14.657547;
  final double shopLng = 120.978101;

  Future<List<Map<String, dynamic>>> getSortedQueueByDistance() async {
    final currentBarberId = FirebaseAuth.instance.currentUser?.uid;
    if (currentBarberId == null) return [];

    final queueSnapshot = await FirebaseFirestore.instance
        .collection('queue')
        .where('barberId', isEqualTo: currentBarberId)
        .where('status', whereIn: ['pending', 'in_service']).get();

    List<Map<String, dynamic>> queueData = [];

    for (var doc in queueSnapshot.docs) {
      final data = doc.data();
      final userLat = data['userLat'] ?? 0.0;
      final userLng = data['userLng'] ?? 0.0;
      final createdAt = data['createdAt'];
      final id = doc.id;

      final distance = Geolocator.distanceBetween(
        userLat,
        userLng,
        shopLat,
        shopLng,
      );

      queueData.add({
        ...data,
        'id': id,
        'distance': distance,
        'createdAt': createdAt,
      });
    }

    queueData.sort((a, b) {
      final d1 = a['distance'] as double;
      final d2 = b['distance'] as double;
      if (d1 != d2) return d1.compareTo(d2);

      final t1 = a['createdAt'] as Timestamp?;
      final t2 = b['createdAt'] as Timestamp?;
      return (t1?.compareTo(t2 ?? t1) ?? 0);
    });

    return queueData;
  }

  Future<void> _startService(String docId) async {
    await FirebaseFirestore.instance.collection('queue').doc(docId).update({
      'status': 'in_service',
    });
  }

  Future<void> _completeService(String docId) async {
    final queueDoc =
        await FirebaseFirestore.instance.collection('queue').doc(docId).get();

    if (!queueDoc.exists) return;

    final data = queueDoc.data()!;
    final transactionData = {
      'uid': data['uid'],
      'barberId': data['barberId'],
      'barberName': data['barber'],
      'customerName': data['name'],
      'queueNumber': data['queueNumber'],
      'paymentMethod': data['paymentMethod'],
      'amount': 200, // Customize this based on the service or pricing logic
      'status': 'Completed',
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Add to transactions
    await FirebaseFirestore.instance
        .collection('transactions')
        .add(transactionData);

    // Remove from queue
    await FirebaseFirestore.instance.collection('queue').doc(docId).delete();
  }

  Future<void> _addWalkInCustomer(BuildContext context) async {
    final nameController = TextEditingController();
    final currentBarberId = FirebaseAuth.instance.currentUser?.uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Walk-in Customer"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: "Customer Name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty && currentBarberId != null) {
                await FirebaseFirestore.instance.collection('queue').add({
                  'barber': 'Walk-in',
                  'barberId': currentBarberId,
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                  'name': name,
                  'uid': 'walk-in',
                  'userLat': shopLat,
                  'userLng': shopLng,
                });
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<String> _getUserName(String uid) async {
    if (uid == 'walk-in') return 'Walk-in';
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return userDoc.data()?['fullName'] ?? 'Unknown';
  }

  Widget _buildCustomerCard(String title, Map<String, dynamic>? customer) {
    return FutureBuilder<String>(
      future: customer?['uid'] != null
          ? _getUserName(customer!['uid'])
          : Future.value('None'),
      builder: (context, snapshot) {
        final name = snapshot.data ?? 'Loading...';
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.person, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(name, style: const TextStyle(fontSize: 16)),
                      if (customer?['status'] != null)
                        Text(
                          "Status: ${customer!['status']}",
                          style: TextStyle(
                            fontSize: 13,
                            color: customer['status'] == 'in_service'
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(
    Map<String, dynamic>? current,
    String? currentId,
    VoidCallback onDone,
    VoidCallback onStart,
  ) {
    final isWaiting = current?['status'] == 'pending';

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isWaiting ? onStart : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start Service"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color.fromARGB(255, 206, 148, 73),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade400,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: currentId != null ? onDone : null,
            icon: const Icon(Icons.check),
            label: const Text("Done"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color.fromARGB(255, 0, 0, 0),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Queue Management"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('queue')
            .where('barberId',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .where('status', whereIn: ['pending', 'in_service']).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          List<Map<String, dynamic>> queue = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final userLat = data['userLat'] ?? 0.0;
            final userLng = data['userLng'] ?? 0.0;
            final distance =
                Geolocator.distanceBetween(userLat, userLng, shopLat, shopLng);
            return {
              ...data,
              'id': doc.id,
              'distance': distance,
            };
          }).toList();

          queue.sort((a, b) {
            final d1 = a['distance'] as double;
            final d2 = b['distance'] as double;
            if (d1 != d2) return d1.compareTo(d2);
            final t1 = a['createdAt'] as Timestamp?;
            final t2 = b['createdAt'] as Timestamp?;
            return (t1?.compareTo(t2 ?? t1) ?? 0);
          });

          final current = queue.isNotEmpty ? queue[0] : null;
          final next = queue.length > 1 ? queue[1] : null;
          final currentId = current?['id'];

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildCustomerCard("Current Customer", current),
                const SizedBox(height: 12),
                _buildCustomerCard("Next in Queue", next),
                const SizedBox(height: 24),
                _buildActionButtons(
                  current,
                  currentId,
                  () => _completeService(currentId!),
                  () => _startService(currentId!),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "📝 Full Queue",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final data = queue[index];
                      final uid = data['uid'] ?? 'walk-in';
                      final queueNumber = index + 1;

                      return FutureBuilder<String>(
                        future: _getUserName(uid),
                        builder: (context, nameSnapshot) {
                          final name = nameSnapshot.data ?? 'Loading...';
                          return ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(name),
                            subtitle: Text(
                              "Queue #: $queueNumber | Status: ${data['status'] ?? 'pending'}",
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWalkInCustomer(context),
        icon: const Icon(Icons.person_add),
        label: const Text("Add Walk-in"),
        backgroundColor: const Color.fromARGB(255, 206, 148, 73),
        foregroundColor: Colors.white,
      ),
    );
  }
}
