import 'package:flutter/material.dart';
import 'package:shop/components/network_image_with_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shop/components/product/branch_card.dart';
import 'package:shop/models/branch_model.dart';
import 'package:shop/services/queue_service.dart';
import 'package:shop/services/rating_service.dart';
import '../../../../constants.dart';

class PopularProducts extends StatefulWidget {
  final String searchQuery;
  const PopularProducts({super.key, this.searchQuery = ''});

  @override
  State<PopularProducts> createState() => _PopularProductsState();
}

class _PopularProductsState extends State<PopularProducts> {
  // Safe converter from Firestore doc -> BranchModel (handles missing fields)
  BranchModel _branchFromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final map = <String, dynamic>{...data, 'id': doc.id};

    // If status is missing but isActive exists, derive it
    if (map['status'] == null && map['isActive'] != null) {
      map['status'] = map['isActive'] == true ? 'Open' : 'Closed';
    }

    // Ensure optional shapes are consistent
    map['operatingHours'] =
        (map['operatingHours'] as Map?)?.cast<String, dynamic>() ?? {};
    // Normalize `services` to a List<String> even if Firestore stores a string
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
    // coordinates can be a map or GeoPoint; BranchModel.fromMap tolerates map
    // (If you store GeoPoint, you can extend the model later.)

    // Numeric coercions
    final rating = map['rating'];
    if (rating is int) map['rating'] = rating.toDouble();

    return BranchModel.fromMap(map);
  }

  String _formatWaitTime(int minutes) {
    if (minutes == 0) return 'No wait';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: defaultPadding / 2),
        const Padding(
          padding: EdgeInsets.all(defaultPadding),
          child: Text("Our Branches"),
        ),
        // 🔥 Live branches from Firestore
        SizedBox(
          height: 280,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('branches')
                .orderBy('name') // remove if you don't have 'name' on all docs
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }

              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Center(child: Text('No branches found.'));
              }

              List<BranchModel> branches = docs.map(_branchFromDoc).toList();
              final q = widget.searchQuery.trim().toLowerCase();
              if (q.isNotEmpty) {
                branches = branches.where((b) {
                  final inName = b.name.toLowerCase().contains(q);
                  final inLoc = b.location.toLowerCase().contains(q) ||
                      b.address.toLowerCase().contains(q);
                  final inServices =
                      b.services.any((s) => s.toLowerCase().contains(q));
                  return inName || inLoc || inServices;
                }).toList();
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: branches.length,
                itemBuilder: (context, index) {
                  final branch = branches[index];

                  // Reuse your existing real-time queue stream per branch
                  return StreamBuilder<Map<String, dynamic>>(
                    stream: QueueService.getQueueStream(branch.id),
                    builder: (context, qSnap) {
                      final queueInfo = qSnap.data ??
                          const {
                            'currentQueueCount': 0,
                            'estimatedWaitTime': 0,
                          };

                      return BranchCard(
                        image: branch.image, // supports http or assets
                        name: branch.name.isNotEmpty
                            ? branch.name
                            : 'Unnamed Branch',
                        location: branch.location.isNotEmpty
                            ? branch.location
                            : (branch.address.isNotEmpty
                                ? branch.address
                                : 'Philippines'),
                        status:
                            branch.status.isNotEmpty ? branch.status : 'Closed',
                        currentQueueCount:
                            (queueInfo['currentQueueCount'] ?? 0) as int,
                        estimatedWaitTime:
                            (queueInfo['estimatedWaitTime'] ?? 0) as int,
                        onTap: () {
                          _showBranchDetails(context, branch, queueInfo);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showBranchDetails(
    BuildContext context,
    BranchModel branch,
    Map<String, dynamic> queueInfo,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Branch header
            Container(
              height: 200,
              width: double.infinity,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Branch image
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: _buildBranchImage(branch.image),
                  ),
                  // Status indicator
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(branch.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        branch.status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Branch details
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Branch name
                    Text(
                      branch.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A0F0A),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Location
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFD4AF37),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            branch.address,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF8B4513),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Real-time Rating
                    StreamBuilder<Map<String, dynamic>>(
                      stream: RatingService.getBranchRatingStream(branch.id),
                      builder: (context, snapshot) {
                        final ratingData = snapshot.data ??
                            {
                              'averageRating': 0.0,
                              'totalReviews': 0,
                            };

                        final averageRating =
                            ratingData['averageRating'] as double;
                        final totalReviews = ratingData['totalReviews'] as int;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Color(0xFFD4AF37),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${averageRating.toStringAsFixed(1)} ($totalReviews reviews)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (totalReviews > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: List.generate(5, (index) {
                                  final starRating = index + 1;
                                  final isFilled = starRating <= averageRating;
                                  final isHalfFilled =
                                      starRating - averageRating < 1 &&
                                          starRating - averageRating > 0;

                                  return Icon(
                                    isFilled
                                        ? Icons.star
                                        : isHalfFilled
                                            ? Icons.star_half
                                            : Icons.star_border,
                                    color: const Color(0xFFD4AF37),
                                    size: 16,
                                  );
                                }),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Queue Information
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD4AF37),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Queue Status',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A0F0A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                queueInfo['currentQueueCount'] > 0
                                    ? Icons.people
                                    : Icons.check_circle,
                                color: queueInfo['currentQueueCount'] > 0
                                    ? const Color(0xFFFFBE21)
                                    : const Color(0xFF2ED573),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      queueInfo['currentQueueCount'] > 0
                                          ? '${queueInfo['currentQueueCount']} people waiting'
                                          : 'No queue - Ready!',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A0F0A),
                                      ),
                                    ),
                                    if (queueInfo['currentQueueCount'] > 0) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Estimated wait: ${_formatWaitTime(queueInfo['estimatedWaitTime'])}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF8B4513),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Recent Reviews Section
                    const Text(
                      'Recent Reviews',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A0F0A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future:
                          RatingService.getBranchReviews(branch.id, limit: 3),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final reviews = snapshot.data ?? [];

                        if (reviews.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'No reviews yet. Be the first to review!',
                              style: TextStyle(
                                color: Color(0xFF8B4513),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: reviews.map((review) {
                            final rating = review['rating'] as num;
                            final reviewText = review['review'] as String;
                            final customerName =
                                review['customerName'] as String;
                            final service = review['service'] as String;
                            // final createdAt = review['createdAt'] as Timestamp?;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      const Color(0xFFD4AF37).withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Star rating
                                      ...List.generate(5, (index) {
                                        return Icon(
                                          index < rating
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: const Color(0xFFD4AF37),
                                          size: 16,
                                        );
                                      }),
                                      const SizedBox(width: 8),
                                      Text(
                                        'by $customerName',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8B4513),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (service.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Service: $service',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFD4AF37),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (reviewText.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      reviewText,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF1A0F0A),
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Contact information
                    const Text(
                      'Contact Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A0F0A),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        const Icon(Icons.phone, color: Color(0xFFD4AF37)),
                        const SizedBox(width: 12),
                        Text(
                          branch.phone,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(Icons.email, color: Color(0xFFD4AF37)),
                        const SizedBox(width: 12),
                        Text(
                          branch.email,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Services
                    const Text(
                      'Services',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A0F0A),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: branch.services
                          .map((service) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFD4AF37).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  service,
                                  style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),

                    const SizedBox(height: 20),

                    // Operating hours
                    const Text(
                      'Operating Hours',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A0F0A),
                      ),
                    ),

                    const SizedBox(height: 12),

                    ...branch.operatingHours.entries.map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                entry.value,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF8B4513),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchImage(String imagePath) {
    // Check if it's a local asset or network image
    if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderImage();
        },
      );
    } else if (imagePath.startsWith('http')) {
      return SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: NetworkImageWithLoader(
          imagePath,
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
          size: 60,
          color: Color(0xFFD4AF37),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
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
}
