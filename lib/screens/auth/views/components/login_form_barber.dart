import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shop/route/route_constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../constants.dart';

class LogInFormBarber extends StatefulWidget {
  const LogInFormBarber({
    super.key,
    required this.formKey,
  });

  final GlobalKey<FormState> formKey;

  @override
  State<LogInFormBarber> createState() => _LogInFormState();
}

class _LogInFormState extends State<LogInFormBarber> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _signIn(BuildContext context) async {
    if (widget.formKey.currentState?.validate() ?? false) {
      try {
        final credential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
        await FirebaseFirestore.instance.enableNetwork();

        final uid = credential.user!.uid;
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();

        final role = doc.data()?['role'];
        if (!doc.exists ||
            (role != 'barber' && role != 'cashier' && role != 'admin')) {
          await FirebaseAuth.instance.signOut(); // Log out if not staff
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Access denied. Not a staff account.')),
          );
          return;
        }

// Generate a random 6-digit code
        final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
            .toString();

        // Save to Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'verificationCode': code,
          'codeExpiresAt':
              Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5)))
        });

        // ✅ Add login log
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('logs')
            .add({
          'type': 'login',
          'timestamp': Timestamp.now(),
        });

        await sendEmailCode(emailController.text.trim(), code);

// Then navigate to the verification screen
        Navigator.pushNamed(context, verifyCodeScreenRoute, arguments: {
          'uid': uid,
          'email': emailController.text.trim(),
        });
      } on FirebaseAuthException catch (e) {
        String message = 'Login failed';
        if (e.code == 'user-not-found') {
          message = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          message = 'Wrong password.';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> sendEmailCode(String email, String code) async {
    const serviceId = 'service_a4zqrgx';
    const templateId = 'template_rsx4knf';
    const userId = 'Aqi65C5OiPqyMRPoy';

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    final response = await http.post(
      url,
      headers: {
        'origin': 'http://localhost',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': userId,
        'template_params': {
          'to_email': email,
          'code': code,
        },
      }),
    );

    if (response.statusCode == 200) {
      print('✅ Verification email sent');
    } else {
      print('❌ Email failed: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey, // ✅ Required to make .validate() work
      child: Column(
        children: [
          TextFormField(
            controller: emailController,
            cursorColor: Colors.black,
            validator: (value) {
              if (value == null || value.isEmpty || !value.contains('@')) {
                return 'Please enter a valid email';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: "Email address",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: SvgPicture.asset(
                  "assets/icons/Message.svg",
                  height: 24,
                  width: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context)
                        .textTheme
                        .bodyLarge!
                        .color!
                        .withOpacity(0.3),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: passwordController,
            cursorColor: Colors.black,
            obscureText: _obscurePassword, // 🔒 based on toggle
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: "Password",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: SvgPicture.asset(
                  "assets/icons/Lock.svg",
                  height: 24,
                  width: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context)
                        .textTheme
                        .bodyLarge!
                        .color!
                        .withOpacity(0.3),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: defaultPadding * 1.5),
          SizedBox(
            width: double.infinity,
            height: 57,
            child: ElevatedButton(
              onPressed: () => _signIn(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log in'),
            ),
          ),
        ],
      ),
    );
  }
}
