class BarberModel {
  final String image;
  final String name;
  final List<String> services;

  BarberModel({
    required this.image,
    required this.name,
    required this.services,
  });
}

List<BarberModel> demoBarbers = [
  BarberModel(
    image:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRAd5avdba8EiOZH8lmV3XshrXx7dKRZvhx-A&s',
    name: 'Barber A',
    services: ['Haircut', 'Beard Trim'],
  ),
  BarberModel(
    image:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRAd5avdba8EiOZH8lmV3XshrXx7dKRZvhx-A&s',
    name: 'Barber B',
    services: ['Haircut', 'Coloring', 'Shaving'],
  ),
  BarberModel(
    image:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRAd5avdba8EiOZH8lmV3XshrXx7dKRZvhx-A&s',
    name: 'Barber C',
    services: ['Fade Cut', 'Shaving'],
  ),
  BarberModel(
    image:
        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRAd5avdba8EiOZH8lmV3XshrXx7dKRZvhx-A&s',
    name: 'Barber D',
    services: ['Haircut', 'Massage'],
  ),
];
