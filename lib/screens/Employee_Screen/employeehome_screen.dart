import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool isClockedIn = false;
  List<String> attendanceHistory = [];

  @override
  void initState() {
    super.initState();
    _loadAvailabilityStatus(); // 🔥 fetch from Firestore when screen loads
    _loadAllAttendanceLogs(); // ✅ fetch full attendance history
  }

  Future<void> _loadAvailabilityStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (doc.exists && doc.data()?['isAvailable'] != null) {
      setState(() {
        isClockedIn = doc.data()!['isAvailable'] as bool;
      });
    }
  }

  void _toggleClockStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();

    final newClockedInStatus = !isClockedIn;

    // 🔥 Update availability
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isAvailable': newClockedInStatus,
      'lastSeen': Timestamp.now(),
    });

    // 📝 Log the event to subcollection `attendanceLogs`
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attendanceLogs')
        .add({
      'type': newClockedInStatus ? 'clock_in' : 'clock_out',
      'timestamp': Timestamp.now(),
    });

    // ✅ Update local state and refresh history
    setState(() {
      isClockedIn = newClockedInStatus;
    });

    await _loadAllAttendanceLogs(); // 🔄 Load after state updates
  }

  Future<void> _loadAllAttendanceLogs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attendanceLogs')
        .orderBy('timestamp', descending: true)
        .get();

    setState(() {
      attendanceHistory = snapshot.docs.map((doc) {
        final data = doc.data();
        final type = data['type'] ?? 'unknown';
        final timestamp = (data['timestamp'] as Timestamp).toDate();
        final timeStr = DateFormat('MMM d, yyyy – hh:mm a').format(timestamp);
        return '${type == 'clock_in' ? 'Clocked in' : 'Clocked out'} at $timeStr';
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final availabilityText = isClockedIn ? "Available" : "Not Available";
    final availabilityColor = isClockedIn ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Module"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Status: $availabilityText",
              style: TextStyle(
                fontSize: 20,
                color: availabilityColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _toggleClockStatus,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                backgroundColor: isClockedIn ? Colors.red : Colors.green,
              ),
              child: Text(
                isClockedIn ? "Clock Out" : "Clock In",
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Attendance History:",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: attendanceHistory.isEmpty
                  ? const Center(child: Text("No attendance yet."))
                  : ListView.builder(
                      itemCount: attendanceHistory.length,
                      itemBuilder: (context, index) => ListTile(
                        leading: const Icon(Icons.access_time),
                        title: Text(attendanceHistory[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
