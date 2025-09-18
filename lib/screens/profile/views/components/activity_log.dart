import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActivityLogSection extends StatefulWidget {
  final String uid;
  const ActivityLogSection({super.key, required this.uid});

  @override
  State<ActivityLogSection> createState() => _ActivityLogSectionState();
}

class _ActivityLogSectionState extends State<ActivityLogSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text("Activity Logs"),
      initiallyExpanded: _expanded,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.uid)
              .collection('logs')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("Error loading activity logs"),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(),
              );
            }

            final logs = snapshot.data!.docs;

            if (logs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("No activity logs found."),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final data = logs[index].data() as Map<String, dynamic>;
                final type = data['type'] ?? 'unknown';
                final timestamp = (data['timestamp'] as Timestamp).toDate();
                final formattedTime =
                    DateFormat('MMM dd, yyyy – hh:mm a').format(timestamp);

                return ListTile(
                  leading: Icon(
                    type == 'login' ? Icons.login : Icons.logout,
                    color: type == 'login' ? Colors.green : Colors.red,
                  ),
                  title: Text(type == 'login' ? 'Logged In' : 'Logged Out'),
                  subtitle: Text(formattedTime),
                );
              },
            );
          },
        )
      ],
    );
  }
}
