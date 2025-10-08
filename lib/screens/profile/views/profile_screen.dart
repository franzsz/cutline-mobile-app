import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shop/components/theme_toggle.dart';
import 'package:shop/constants.dart';
import 'package:shop/route/screen_export.dart';
import 'components/profile_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  String fullName = '';
  String email = '';
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userDoc.data();
    if (data != null) {
      setState(() {
        _nameController.text = data['fullName'] ?? '';
        email = data['email'];
      });
    }
  }

  bool _validateName(String name) {
    if (name.trim().isEmpty) {
      return false;
    }
    // Check for valid characters (letters, spaces, hyphens, apostrophes)
    final validNameRegex = RegExp(r"^[a-zA-Z\s\-'\.]+$");
    return validNameRegex.hasMatch(name.trim());
  }

  Future<void> _updateProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final fullName = _nameController.text.trim();

    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    // Validate name
    if (!_validateName(fullName)) {
      setState(() {
        _nameError = "Please enter a valid name";
      });
      return;
    }

    // Clear any previous errors
    setState(() {
      _nameError = null;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fullName': fullName,
      });
      setState(() {}); // Refresh UI
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update profile.')),
      );
    }
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final uid = user.uid;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();

      setState(() {
        fullName = data?['fullName'] ?? 'Unknown User';
        email = user.email ?? 'No email';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 32),
          Center(
            child: CircleAvatar(
              radius: 50,
              // Use foregroundImage so we can gracefully fall back to child on errors
              foregroundImage: const NetworkImage(
                "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRAd5avdba8EiOZH8lmV3XshrXx7dKRZvhx-A&s",
              ),
              onForegroundImageError: (_, __) {},
              child:
                  const Icon(Icons.person, size: 40, color: Color(0xFFD4AF37)),
              backgroundColor: const Color(0xFFF7F3E7),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ProfileCard(
              name: fullName,
              email: email,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
            child: Text(
              "Account",
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Full Name",
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                // Clear error when user starts typing
                if (_nameError != null) {
                  setState(() {
                    _nameError = null;
                  });
                }
              },
            ),
          ),

          const SizedBox(height: defaultPadding),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: defaultPadding, vertical: defaultPadding / 2),
            child: Text(
              "Settings",
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),

          // Dark Mode Toggle
          const ThemeToggle(),

          const SizedBox(height: defaultPadding),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
            child: ElevatedButton(
              onPressed: _updateProfile,
              child: const Text("Save Changes"),
            ),
          ),

          // Log Out
          ListTile(
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            minLeadingWidth: 24,
            leading: SvgPicture.asset(
              "assets/icons/Logout.svg",
              height: 24,
              width: 24,
              colorFilter: const ColorFilter.mode(
                errorColor,
                BlendMode.srcIn,
              ),
            ),
            title: const Text(
              "Log Out",
              style: TextStyle(color: errorColor, fontSize: 14, height: 1),
            ),
          )
        ],
      ),
    );
  }
}
