import 'package:flutter/material.dart';
import 'package:shop/components/network_image_with_loader.dart';

class BarberCard extends StatelessWidget {
  final String image;
  final String name;
  final VoidCallback onTap;

  const BarberCard({
    super.key,
    required this.image,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: SizedBox(
                width: 80,
                height: 80,
                child: image.startsWith('http')
                    ? NetworkImageWithLoader(
                        image,
                        fit: BoxFit.cover,
                        radius: 50,
                      )
                    : Image.asset(
                        image,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade300,
                            child:
                                const Icon(Icons.person, color: Colors.white70),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
