import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shop/route/route_constants.dart';

import '../../../../constants.dart';

class LogInForm extends StatefulWidget {
  const LogInForm({
    super.key,
    required this.formKey,
  });

  final GlobalKey<FormState> formKey;

  @override
  State<LogInForm> createState() => _LogInFormState();
}

class _LogInFormState extends State<LogInForm> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true; // 👈 Add this
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
      final doc = await FirebaseFirestore.instance
          .collection('login_attempts')
          .doc(email)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final failedAttempts = data['failedAttempts'] ?? 0;
        final lockoutUntil = (data['lockoutUntil'] as Timestamp?)?.toDate();

        if (lockoutUntil != null && DateTime.now().isBefore(lockoutUntil)) {
          setState(() {
            _isLockedOut = true;
            _remainingLockoutTime =
                lockoutUntil.difference(DateTime.now()).inMinutes;
          });
          _startLockoutTimer();
        } else if (failedAttempts >= maxFailedAttempts) {
          // Reset if lockout period has expired
          await FirebaseFirestore.instance
              .collection('login_attempts')
              .doc(email)
              .delete();
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
      final docRef =
          FirebaseFirestore.instance.collection('login_attempts').doc(email);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (doc.exists) {
          final data = doc.data()!;
          final failedAttempts = (data['failedAttempts'] ?? 0) + 1;

          if (failedAttempts >= maxFailedAttempts) {
            final lockoutUntil =
                DateTime.now().add(Duration(minutes: lockoutDurationMinutes));
            transaction.update(docRef, {
              'failedAttempts': failedAttempts,
              'lastAttempt': Timestamp.now(),
              'lockoutUntil': Timestamp.fromDate(lockoutUntil),
            });
          } else {
            transaction.update(docRef, {
              'failedAttempts': failedAttempts,
              'lastAttempt': Timestamp.now(),
            });
          }
        } else {
          transaction.set(docRef, {
            'failedAttempts': 1,
            'lastAttempt': Timestamp.now(),
            'email': email,
          });
        }
      });
    } catch (e) {
      print('Error recording failed attempt: $e');
    }
  }

  Future<void> _clearFailedAttempts(String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('login_attempts')
          .doc(email)
          .delete();
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

        // Clear failed attempts on successful login
        await _clearFailedAttempts(emailController.text.trim());

        final uid = credential.user!.uid;
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final role = userDoc.data()?['role'];

        if (role == 'customer') {
          Navigator.pushNamedAndRemoveUntil(
            context,
            entryPointScreenRoute,
            (route) => false,
          );
        } else {
          FirebaseAuth.instance.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Unauthorized: This account is not a customer.")),
          );
        }
      } on FirebaseAuthException catch (e) {
        String message = 'Login failed';
        if (e.code == 'user-not-found') {
          message = 'No user found for that email.';
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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
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
            obscureText: _obscurePassword, // 👈 Control visibility
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
                // 👈 Toggle Button
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
