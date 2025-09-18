import 'package:flutter/material.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  // Sample notifications data
  final List<Map<String, dynamic>> _notifications = [
    {
      'type': 'new_customer',
      'message': 'A new customer has been queued under you: Franz Jarcia',
      'timestamp': DateTime.now().subtract(const Duration(minutes: 3)),
    },
    {
      'type': 'cancellation',
      'message': 'Customer Ffiona Sayson cancelled her appointment',
      'timestamp': DateTime.now().subtract(const Duration(minutes: 10)),
    },
    {
      'type': 'idle_reminder',
      'message':
          'You’ve been idle for 30 minutes. Ready to take a new customer?',
      'timestamp': DateTime.now().subtract(const Duration(hours: 1)),
    },
  ];

  Icon _getIcon(String type) {
    switch (type) {
      case 'new_customer':
        return const Icon(Icons.person_add, color: Colors.green);
      case 'cancellation':
        return const Icon(Icons.cancel, color: Colors.redAccent);
      case 'idle_reminder':
        return const Icon(Icons.timer, color: Colors.orange);
      default:
        return const Icon(Icons.notifications);
    }
  }

  Color _getBackgroundColor(String type) {
    switch (type) {
      case 'new_customer':
        return Colors.green.shade50;
      case 'cancellation':
        return Colors.red.shade50;
      case 'idle_reminder':
        return Colors.orange.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";
    return "${difference.inDays}d ago";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        centerTitle: true,
      ),
      body: _notifications.isEmpty
          ? const Center(child: Text("No notifications yet"))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return Container(
                  decoration: BoxDecoration(
                    color: _getBackgroundColor(notif['type']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getIcon(notif['type']),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notif['message'],
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatTime(notif['timestamp']),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }
}
