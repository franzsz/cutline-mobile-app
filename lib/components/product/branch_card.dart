import 'package:flutter/material.dart';
import 'package:shop/components/network_image_with_loader.dart';
// constants.dart not needed in this file

class BranchCard extends StatelessWidget {
  final String image;
  final String name;
  final String location;
  final String status; // "Open", "Closed", "Busy"
  final int currentQueueCount; // Number of people in queue
  final int estimatedWaitTime; // Estimated wait time in minutes
  final VoidCallback onTap;
  final String? phone;
  final Map<String, double>? coordinates;

  const BranchCard({
    super.key,
    required this.image,
    required this.name,
    required this.location,
    required this.status,
    this.currentQueueCount = 0,
    this.estimatedWaitTime = 0,
    required this.onTap,
    this.phone,
    this.coordinates,
  });

  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFF2ED573); // Green
      case 'closed':
        return const Color(0xFFEA5B5B); // Red
      case 'busy':
        return const Color(0xFFFFBE21); // Yellow/Orange
      default:
        return const Color(0xFF2ED573); // Default to green
    }
  }

  String _formatWaitTime(int minutes) {
    if (minutes == 0) return 'No wait';
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }

  String _getQueueStatusText() {
    if (currentQueueCount == 0) {
      return 'No queue';
    } else if (currentQueueCount == 1) {
      return '1 person waiting';
    } else {
      return '$currentQueueCount people waiting';
    }
  }

  Color _getQueueStatusColor() {
    if (currentQueueCount == 0) {
      return const Color(0xFF2ED573); // Green - no queue
    } else if (currentQueueCount <= 3) {
      return const Color(0xFF2ED573); // Green - short queue
    } else if (currentQueueCount <= 6) {
      return const Color(0xFFFFBE21); // Yellow - medium queue
    } else {
      return const Color(0xFFEA5B5B); // Red - long queue
    }
  }

  String _waitBadgeText() {
    if (currentQueueCount == 0) return 'Ready';
    if (estimatedWaitTime == 0) return '$currentQueueCount in queue';
    if (estimatedWaitTime <= 10) return '${estimatedWaitTime}m wait';
    if (estimatedWaitTime <= 30) return '${estimatedWaitTime}m wait';
    return '30m+';
  }

  Widget _buildImage() {
    // Check if it's a local asset or network image
    if (image.startsWith('assets/')) {
      return Image.asset(
        image,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderImage();
        },
      );
    } else if (image.startsWith('http')) {
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: NetworkImageWithLoader(
          image,
          fit: BoxFit.cover,
          radius: 0,
        ),
      );
    } else {
      return _buildPlaceholderImage();
    }
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C1810),
            Color(0xFF4A2C1A),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.content_cut,
          size: 40,
          color: Color(0xFFD4AF37),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Branch Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
                height: 112,
                width: double.infinity,
                child: Stack(
                  children: [
                    // Background image
                    _buildImage(),
                    // Status indicator
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Queue status indicator
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getQueueStatusColor().withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              currentQueueCount == 0
                                  ? Icons.check_circle
                                  : Icons.people,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _waitBadgeText(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Branch Information
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Branch Name
                      Tooltip(
                        message: name,
                        preferBelow: false,
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A0F0A),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),

                      const SizedBox(height: 3),

                      // Location
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 12,
                            color: Color(0xFFD4AF37),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              location,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8B4513),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Queue Information
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getQueueStatusColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _getQueueStatusColor().withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Queue status
                            Row(
                              children: [
                                Icon(
                                  currentQueueCount == 0
                                      ? Icons.check_circle
                                      : Icons.schedule,
                                  size: 12,
                                  color: _getQueueStatusColor(),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _getQueueStatusText(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getQueueStatusColor(),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Wait time
                            if (currentQueueCount > 0) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 10,
                                    color: Color(0xFFD4AF37),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Wait: ${_formatWaitTime(estimatedWaitTime)}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF8B4513),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),

                      // View Details Button
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AF37),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                "View Details",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF1A0F0A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if ((phone ?? '').isNotEmpty)
                            _IconAction(
                              icon: Icons.call,
                              tooltip: 'Call',
                              onTap: () {
                                // Caller handled by parent via onTap or using a service
                                onTap();
                              },
                            ),
                          const SizedBox(width: 6),
                          if ((coordinates ?? {}).isNotEmpty)
                            _IconAction(
                              icon: Icons.directions,
                              tooltip: 'Directions',
                              onTap: onTap,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37).withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: const Color(0xFFD4AF37),
          ),
        ),
      ),
    );
  }
}
