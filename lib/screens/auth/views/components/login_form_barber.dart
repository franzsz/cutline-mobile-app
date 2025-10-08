import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shop/route/route_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isSubmitting = false;
  bool _isLockedOut = false;
  int _remainingLockoutTime = 0;

  // Constants for lockout system
  static const int maxFailedAttempts = 5;
  static const int lockoutDurationMinutes = 15;

  @override
  void initState() {
    super.initState();
    _checkLockoutStatus();
  }

  Future<void> _checkLockoutStatus() async {
    final email = emailController.text.trim();
    if (email.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final failedAttempts = prefs.getInt('login_failedAttempts_$email') ?? 0;
      final lockoutUntilMs = prefs.getInt('login_lockoutUntilMs_$email');

      if (lockoutUntilMs != null) {
        final lockoutUntil =
            DateTime.fromMillisecondsSinceEpoch(lockoutUntilMs);
        if (DateTime.now().isBefore(lockoutUntil)) {
          setState(() {
            _isLockedOut = true;
            _remainingLockoutTime =
                lockoutUntil.difference(DateTime.now()).inMinutes;
          });
          _startLockoutTimer();
        } else if (failedAttempts >= maxFailedAttempts) {
          await _clearFailedAttempts(email);
        }
      }
    } catch (e) {
      print('Error checking lockout status: $e');
    }
  }

  void _startLockoutTimer() {
    if (_remainingLockoutTime > 0) {
      Future.delayed(const Duration(minutes: 1), () {
        if (mounted) {
          setState(() {
            _remainingLockoutTime--;
          });
          if (_remainingLockoutTime > 0) {
            _startLockoutTimer();
          } else {
            setState(() {
              _isLockedOut = false;
            });
          }
        }
      });
    }
  }

  Future<void> _recordFailedAttempt(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('login_failedAttempts_$email') ?? 0;
      final updated = current + 1;
      await prefs.setInt('login_failedAttempts_$email', updated);

      if (updated >= maxFailedAttempts) {
        final lockoutUntil =
            DateTime.now().add(Duration(minutes: lockoutDurationMinutes));
        await prefs.setInt(
            'login_lockoutUntilMs_$email', lockoutUntil.millisecondsSinceEpoch);
        setState(() {
          _isLockedOut = true;
          _remainingLockoutTime =
              lockoutUntil.difference(DateTime.now()).inMinutes;
        });
        _startLockoutTimer();
      }
    } catch (e) {
      print('Error recording failed attempt: $e');
    }
  }

  Future<void> _clearFailedAttempts(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_failedAttempts_$email');
      await prefs.remove('login_lockoutUntilMs_$email');
    } catch (e) {
      print('Error clearing failed attempts: $e');
    }
  }

  Future<void> _signIn(BuildContext context) async {
    if (_isLockedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Account locked. Try again in $_remainingLockoutTime minutes.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.formKey.currentState?.validate() ?? false) {
      try {
        setState(() {
          _isSubmitting = true;
        });
        final credential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
        await FirebaseFirestore.instance.enableNetwork();

        // Clear failed attempts on successful login
        await _clearFailedAttempts(emailController.text.trim());

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
          message = 'Account not found. Please sign up.';
        } else if (e.code == 'wrong-password') {
          message = 'Wrong password.';
        }

        // Record failed attempt
        await _recordFailedAttempt(emailController.text.trim());

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
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
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          TextFormField(
            controller: emailController,
            cursorColor: Colors.black,
            validator: (value) => emaildValidator.call(value),
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
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
            validator: (value) => passwordValidator.call(value),
            autofillHints: const [AutofillHints.password],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
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
              onPressed: (_isSubmitting || _isLockedOut)
                  ? null
                  : () => _signIn(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLockedOut ? Colors.grey : Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : _isLockedOut
                      ? Text('Locked ($_remainingLockoutTime min)')
                      : const Text('Log in'),
            ),
          ),
        ],
      ),
    );
  }
}
