import 'package:cloud_firestore/cloud_firestore.dart';

class RatingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get average rating for a specific branch
  static Future<Map<String, dynamic>> getBranchRating(String branchId) async {
    try {
      final snapshot = await _firestore
          .collection('ratings')
          .where('branchId', isEqualTo: branchId)
          .get();

      if (snapshot.docs.isEmpty) {
        return {
          'averageRating': 0.0,
          'totalReviews': 0,
          'ratingDistribution': {
            '5': 0,
            '4': 0,
            '3': 0,
            '2': 0,
            '1': 0,
          },
        };
      }

      double totalRating = 0;
      int totalReviews = snapshot.docs.length;
      Map<String, int> ratingDistribution = {
        '5': 0,
        '4': 0,
        '3': 0,
        '2': 0,
        '1': 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as num?;
        if (rating != null) {
          totalRating += rating.toDouble();

          // Count rating distribution
          final ratingInt = rating.toInt();
          if (ratingInt >= 1 && ratingInt <= 5) {
            ratingDistribution[ratingInt.toString()] =
                (ratingDistribution[ratingInt.toString()] ?? 0) + 1;
          }
        }
      }

      final averageRating = totalReviews > 0 ? totalRating / totalReviews : 0.0;

      return {
        'averageRating': averageRating,
        'totalReviews': totalReviews,
        'ratingDistribution': ratingDistribution,
      };
    } catch (e) {
      print('Error getting branch rating: $e');
      return {
        'averageRating': 0.0,
        'totalReviews': 0,
        'ratingDistribution': {
          '5': 0,
          '4': 0,
          '3': 0,
          '2': 0,
          '1': 0,
        },
      };
    }
  }

  // Get real-time stream of ratings for a specific branch
  static Stream<Map<String, dynamic>> getBranchRatingStream(String branchId) {
    return _firestore
        .collection('ratings')
        .where('branchId', isEqualTo: branchId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return {
          'averageRating': 0.0,
          'totalReviews': 0,
          'ratingDistribution': {
            '5': 0,
            '4': 0,
            '3': 0,
            '2': 0,
            '1': 0,
          },
        };
      }

      double totalRating = 0;
      int totalReviews = snapshot.docs.length;
      Map<String, int> ratingDistribution = {
        '5': 0,
        '4': 0,
        '3': 0,
        '2': 0,
        '1': 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as num?;
        if (rating != null) {
          totalRating += rating.toDouble();

          // Count rating distribution
          final ratingInt = rating.toInt();
          if (ratingInt >= 1 && ratingInt <= 5) {
            ratingDistribution[ratingInt.toString()] =
                (ratingDistribution[ratingInt.toString()] ?? 0) + 1;
          }
        }
      }

      final averageRating = totalReviews > 0 ? totalRating / totalReviews : 0.0;

      return {
        'averageRating': averageRating,
        'totalReviews': totalReviews,
        'ratingDistribution': ratingDistribution,
      };
    });
  }

  // Get recent reviews for a specific branch
  static Future<List<Map<String, dynamic>>> getBranchReviews(String branchId,
      {int limit = 5}) async {
    try {
      final snapshot = await _firestore
          .collection('ratings')
          .where('branchId', isEqualTo: branchId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'rating': data['rating'] ?? 0,
          'review': data['review'] ?? '',
          'customerName': data['customerName'] ?? 'Anonymous',
          'createdAt': data['createdAt'],
          'service': data['service'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('Error getting branch reviews: $e');
      return [];
    }
  }

  // Submit a new rating for a branch
  static Future<void> submitRating({
    required String branchId,
    required String customerId,
    required String customerName,
    required double rating,
    required String review,
    required String service,
  }) async {
    try {
      await _firestore.collection('ratings').add({
        'branchId': branchId,
        'customerId': customerId,
        'customerName': customerName,
        'rating': rating,
        'review': review,
        'service': service,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error submitting rating: $e');
      rethrow;
    }
  }
}
