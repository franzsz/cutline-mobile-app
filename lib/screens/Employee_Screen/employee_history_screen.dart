import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ServiceLogPage extends StatelessWidget {
  const ServiceLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final barberId = FirebaseAuth.instance.currentUser?.uid;

    if (barberId == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Service History"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('barberId', isEqualTo: barberId)
            .where('status', isEqualTo: 'Completed')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load service logs.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!.docs;

          if (logs.isEmpty) {
            return const Center(child: Text("No service history found."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = logs[index].data() as Map<String, dynamic>;
              final customerName = data['customerName'] ?? 'Unknown';
              final createdAt = (data['createdAt'] as Timestamp).toDate();
              final formattedDate =
                  DateFormat.yMMMd().add_jm().format(createdAt);
              final queueNumber = data['queueNumber']?.toString() ?? '';
              final paymentMethod = data['paymentMethod'] ?? 'Unknown';

              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Queue #$queueNumber | $paymentMethod"),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                  leading:
                      const Icon(Icons.history, color: Colors.black, size: 28),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
