import 'package:cloud_firestore/cloud_firestore.dart';

class QueueService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current queue count for a specific branch
  static Future<int> getCurrentQueueCount(String branchId) async {
    try {
      final snapshot = await _firestore
          .collection('queue')
          .where('branchId', isEqualTo: branchId)
          .where('status', isEqualTo: 'pending')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('Error getting queue count: $e');
      return 0;
    }
  }

  // Get estimated wait time for a specific branch
  static Future<int> getEstimatedWaitTime(
      String branchId, String service) async {
    try {
      final snapshot = await _firestore
          .collection('queue')
          .where('branchId', isEqualTo: branchId)
          .where('status', isEqualTo: 'pending')
          .get();

      final peopleAhead = snapshot.docs.length;
      final perPersonMinutes = _getServiceTimeMinutes(service);
      final estimatedWait = peopleAhead * perPersonMinutes;

      return estimatedWait;
    } catch (e) {
      print('Error getting estimated wait time: $e');
      return 0;
    }
  }

  // Get branches with real-time queue information
  static Future<List<Map<String, dynamic>>> getBranchesWithQueueInfo() async {
    try {
      // Get all pending queues grouped by branch
      final queueSnapshot = await _firestore
          .collection('queue')
          .where('status', isEqualTo: 'pending')
          .get();

      // Group queues by branchId
      final Map<String, List<Map<String, dynamic>>> branchQueues = {};

      for (final doc in queueSnapshot.docs) {
        final data = doc.data();
        final branchId = data['branchId'] as String?;
        if (branchId != null) {
          if (!branchQueues.containsKey(branchId)) {
            branchQueues[branchId] = [];
          }
          branchQueues[branchId]!.add(data);
        }
      }

      // Calculate queue info for each branch
      final List<Map<String, dynamic>> branchesWithQueue = [];

      for (final entry in branchQueues.entries) {
        final branchId = entry.key;
        final queues = entry.value;

        // Calculate average service time
        int totalServiceTime = 0;
        int serviceCount = 0;

        for (final queue in queues) {
          final service = queue['service'] as String?;
          if (service != null) {
            totalServiceTime += _getServiceTimeMinutes(service);
            serviceCount++;
          }
        }

        final avgServiceTime =
            serviceCount > 0 ? totalServiceTime ~/ serviceCount : 25;
        final estimatedWaitTime = queues.length * avgServiceTime;

        branchesWithQueue.add({
          'branchId': branchId,
          'currentQueueCount': queues.length,
          'estimatedWaitTime': estimatedWaitTime,
        });
      }

      return branchesWithQueue;
    } catch (e) {
      print('Error getting branches with queue info: $e');
      return [];
    }
  }

  // Get real-time stream of queue data for a specific branch
  static Stream<Map<String, dynamic>> getQueueStream(String branchId) {
    return _firestore
        .collection('queue')
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final queues = snapshot.docs;
      final queueCount = queues.length;

      // Calculate average service time
      int totalServiceTime = 0;
      int serviceCount = 0;

      for (final doc in queues) {
        final data = doc.data();
        final service = data['service'] as String?;
        if (service != null) {
          totalServiceTime += _getServiceTimeMinutes(service);
          serviceCount++;
        }
      }

      final avgServiceTime =
          serviceCount > 0 ? totalServiceTime ~/ serviceCount : 25;
      final estimatedWaitTime = queueCount * avgServiceTime;

      return {
        'currentQueueCount': queueCount,
        'estimatedWaitTime': estimatedWaitTime,
      };
    });
  }

  // Helper method to get service time in minutes
  static int _getServiceTimeMinutes(String service) {
    final serviceTimes = <String, int>{
      'Haircut': 25,
      'Beard Trim': 15,
      'Hair Coloring': 60,
      'Shaving': 15,
      'Kids Haircut': 25,
      'Hair Styling': 30,
      'Facial Treatment': 45,
      'Massage': 45,
      'Hair Treatment': 45,
    };

    return serviceTimes[service] ?? 25; // Default 25 minutes
  }
}
