import 'package:cloud_firestore/cloud_firestore.dart';

class BranchModel {
  final String id;
  final String name;
  final String location;
  final String address;
  final String status; // "Open", "Closed", "Busy"
  final String image;
  final String phone;
  final String email;
  final Map<String, dynamic> operatingHours;
  final List<String> services;
  final double rating;
  final int reviewCount;
  final Map<String, double> coordinates; // latitude, longitude
  final int currentQueueCount;
  final int estimatedWaitTime;

  BranchModel({
    required this.id,
    required this.name,
    required this.location,
    required this.address,
    required this.status,
    required this.image,
    required this.phone,
    required this.email,
    required this.operatingHours,
    required this.services,
    required this.rating,
    required this.reviewCount,
    required this.coordinates,
    this.currentQueueCount = 0,
    this.estimatedWaitTime = 0,
  });

  factory BranchModel.fromMap(Map<String, dynamic> map) {
    return BranchModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      location: map['location'] ?? '',
      address: map['address'] ?? '',
      status: map['status'] ?? 'Closed',
      image: map['image'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      operatingHours: map['operatingHours'] ?? {},
      services: List<String>.from(map['services'] ?? []),
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      coordinates: normalizeCoordinates(map['coordinates']), // ✅
      currentQueueCount: map['currentQueueCount'] ?? 0,
      estimatedWaitTime: map['estimatedWaitTime'] ?? 0,
    );
  }

  /// New: create from Firestore DocumentSnapshot safely
  factory BranchModel.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    return BranchModel(
      id: doc.id, // use Firestore doc id
      name: (data['name'] ?? '') as String,
      location: (data['location'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      status: ((data['status'] ??
              ((data['isActive'] == true) ? 'Open' : 'Closed')) as String)
          .toString(),
      image: (data['image'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      operatingHours:
          (data['operatingHours'] as Map?)?.cast<String, dynamic>() ?? {},
      services: List<String>.from((data['services'] ?? const []) as List),
      rating: (data['rating'] is int)
          ? (data['rating'] as int).toDouble()
          : (data['rating'] ?? 0.0).toDouble(),
      reviewCount: (data['reviewCount'] ?? 0) as int,
      coordinates: normalizeCoordinates(data['coordinates']), // ✅ non-null,
      currentQueueCount: (data['currentQueueCount'] ?? 0) as int,
      estimatedWaitTime: (data['estimatedWaitTime'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'address': address,
      'status': status,
      'image': image,
      'phone': phone,
      'email': email,
      'operatingHours': operatingHours,
      'services': services,
      'rating': rating,
      'reviewCount': reviewCount,
      'coordinates': coordinates, // already {lat, lng} doubles
      'currentQueueCount': currentQueueCount,
      'estimatedWaitTime': estimatedWaitTime,
    };
  }
}

// Top-level helper (no `static`)
Map<String, double> normalizeCoordinates(dynamic raw) {
  if (raw == null) return {};

  if (raw is GeoPoint) {
    return {'latitude': raw.latitude, 'longitude': raw.longitude};
  }

  if (raw is Map) {
    final lat = raw['latitude'] ?? raw['lat'];
    final lng = raw['longitude'] ?? raw['lng'] ?? raw['lon'];
    if (lat is num && lng is num) {
      return {'latitude': lat.toDouble(), 'longitude': lng.toDouble()};
    }
  }

  return {};
}

// Demo data for branches
List<BranchModel> demoBranches = [
  BranchModel(
    id: '1',
    name: 'Supremo Barber - 9th Ave',
    location: 'Caloocan City',
    address: '9th Avenue, Caloocan City, Metro Manila',
    status: 'Open',
    image: 'assets/images/supremo barber1.jpg',
    phone: '+63 912 345 6789',
    email: 'caloocan@supremobarber.com',
    operatingHours: {
      'Monday': '9:00 AM - 8:00 PM',
      'Tuesday': '9:00 AM - 8:00 PM',
      'Wednesday': '9:00 AM - 8:00 PM',
      'Thursday': '9:00 AM - 8:00 PM',
      'Friday': '9:00 AM - 8:00 PM',
      'Saturday': '9:00 AM - 8:00 PM',
      'Sunday': '10:00 AM - 6:00 PM',
    },
    services: [
      'Haircut',
      'Beard Trim',
      'Hair Coloring',
      'Shaving',
      'Kids Haircut'
    ],
    rating: 4.8,
    reviewCount: 156,
    coordinates: {'latitude': 14.6546, 'longitude': 120.9842},
    currentQueueCount: 3,
    estimatedWaitTime: 15,
  ),
  BranchModel(
    id: '2',
    name: 'Supremo Barber - Shorthorn',
    location: 'Quezon City',
    address: 'Shorthorn Street, Quezon City, Metro Manila',
    status: 'Busy',
    image: 'assets/images/supremo barber1.jpg',
    phone: '+63 923 456 7890',
    email: 'shorthorn@supremobarber.com',
    operatingHours: {
      'Monday': '8:00 AM - 9:00 PM',
      'Tuesday': '8:00 AM - 9:00 PM',
      'Wednesday': '8:00 AM - 9:00 PM',
      'Thursday': '8:00 AM - 9:00 PM',
      'Friday': '8:00 AM - 9:00 PM',
      'Saturday': '8:00 AM - 9:00 PM',
      'Sunday': '9:00 AM - 7:00 PM',
    },
    services: [
      'Haircut',
      'Beard Trim',
      'Hair Styling',
      'Facial Treatment',
      'Massage'
    ],
    rating: 4.9,
    reviewCount: 203,
    coordinates: {'latitude': 14.6760, 'longitude': 121.0437},
    currentQueueCount: 7,
    estimatedWaitTime: 35,
  ),
  BranchModel(
    id: '3',
    name: 'Supremo Barber - Abad Santos',
    location: 'Manila',
    address: 'Abad Santos Avenue, Manila, Metro Manila',
    status: 'Open',
    image: 'assets/images/supremo barber1.jpg',
    phone: '+63 934 567 8901',
    email: 'abadsantos@supremobarber.com',
    operatingHours: {
      'Monday': '9:00 AM - 8:00 PM',
      'Tuesday': '9:00 AM - 8:00 PM',
      'Wednesday': '9:00 AM - 8:00 PM',
      'Thursday': '9:00 AM - 8:00 PM',
      'Friday': '9:00 AM - 8:00 PM',
      'Saturday': '9:00 AM - 8:00 PM',
      'Sunday': '10:00 AM - 6:00 PM',
    },
    services: [
      'Haircut',
      'Beard Trim',
      'Hair Coloring',
      'Shaving',
      'Kids Haircut',
      'Hair Treatment'
    ],
    rating: 4.7,
    reviewCount: 89,
    coordinates: {'latitude': 14.5995, 'longitude': 120.9842},
    currentQueueCount: 0,
    estimatedWaitTime: 0,
  ),
  BranchModel(
    id: '4',
    name: 'Supremo Barber - Sta. Mesa',
    location: 'Manila',
    address: 'Sta. Mesa, Manila, Metro Manila',
    status: 'Closed',
    image: 'assets/images/supremo barber1.jpg',
    phone: '+63 945 678 9012',
    email: 'stamesa@supremobarber.com',
    operatingHours: {
      'Monday': '9:00 AM - 8:00 PM',
      'Tuesday': '9:00 AM - 8:00 PM',
      'Wednesday': '9:00 AM - 8:00 PM',
      'Thursday': '9:00 AM - 8:00 PM',
      'Friday': '9:00 AM - 8:00 PM',
      'Saturday': '9:00 AM - 8:00 PM',
      'Sunday': '10:00 AM - 6:00 PM',
    },
    services: [
      'Haircut',
      'Beard Trim',
      'Hair Coloring',
      'Shaving',
      'Kids Haircut',
      'Hair Styling'
    ],
    rating: 4.6,
    reviewCount: 134,
    coordinates: {'latitude': 14.5995, 'longitude': 121.0042},
    currentQueueCount: 0,
    estimatedWaitTime: 0,
  ),
];
