class TrendingHaircutModel {
  final String id;
  final String name;
  final String image;
  final String description;
  final double rating;
  final int reviewCount;
  final String category;
  final bool isPopular;

  TrendingHaircutModel({
    required this.id,
    required this.name,
    required this.image,
    required this.description,
    required this.rating,
    required this.reviewCount,
    required this.category,
    this.isPopular = false,
  });

  factory TrendingHaircutModel.fromMap(Map<String, dynamic> map) {
    return TrendingHaircutModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      image: map['image'] ?? '',
      description: map['description'] ?? '',
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      category: map['category'] ?? '',
      isPopular: map['isPopular'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image': image,
      'description': description,
      'rating': rating,
      'reviewCount': reviewCount,
      'category': category,
      'isPopular': isPopular,
    };
  }
}

// Sample trending haircuts data
List<TrendingHaircutModel> trendingHaircuts = [
  TrendingHaircutModel(
    id: '1',
    name: 'Classic Fade',
    image:
        'https://www.barberstake.com/wp-content/uploads/2025/03/Classic-Low-Fade.jpg',
    description:
        'A timeless fade that never goes out of style. Perfect for those who want a clean, professional look that works in any setting.',
    rating: 4.8,
    reviewCount: 156,
    category: 'Fade',
    isPopular: true,
  ),
  TrendingHaircutModel(
    id: '2',
    name: 'Pompadour',
    image:
        'https://188menssalon.com/wp-content/uploads/2017/08/d0c8f7831452d965a0deb8e4da326c2b-male-hairstyles-latest-hairstyles.jpg',
    description:
        'Vintage-inspired high volume style that adds character and personality to your look.',
    rating: 4.6,
    reviewCount: 89,
    category: 'Classic',
    isPopular: true,
  ),
  TrendingHaircutModel(
    id: '3',
    name: 'Undercut',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Modern and edgy with shaved sides. Perfect for those who want to make a bold statement.',
    rating: 4.7,
    reviewCount: 203,
    category: 'Modern',
    isPopular: true,
  ),
  TrendingHaircutModel(
    id: '4',
    name: 'Textured Crop',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Low maintenance with natural texture. Ideal for busy professionals who want style without the fuss.',
    rating: 4.5,
    reviewCount: 134,
    category: 'Textured',
  ),
  TrendingHaircutModel(
    id: '5',
    name: 'Slick Back',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Sophisticated and professional look that exudes confidence and class.',
    rating: 4.4,
    reviewCount: 78,
    category: 'Classic',
  ),
  TrendingHaircutModel(
    id: '6',
    name: 'Messy Quiff',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Casual yet stylish tousled look that works perfectly for everyday wear.',
    rating: 4.3,
    reviewCount: 95,
    category: 'Casual',
  ),
  TrendingHaircutModel(
    id: '7',
    name: 'High Fade',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Bold and clean high fade style that showcases precision cutting skills.',
    rating: 4.6,
    reviewCount: 167,
    category: 'Fade',
  ),
  TrendingHaircutModel(
    id: '8',
    name: 'Side Part',
    image: 'assets/images/supremo barber1.jpg',
    description:
        'Elegant and refined side part style that never goes out of fashion.',
    rating: 4.2,
    reviewCount: 112,
    category: 'Classic',
  ),
];
