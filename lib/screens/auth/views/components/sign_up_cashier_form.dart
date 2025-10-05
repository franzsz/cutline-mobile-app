import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shop/route/route_constants.dart';
import '../../../../constants.dart';

class SignUpCashierForm extends StatefulWidget {
  const SignUpCashierForm({super.key, required this.formKey});

  final GlobalKey<FormState> formKey;

  @override
  State<SignUpCashierForm> createState() => _SignUpCashierFormState();
}

class _SignUpCashierFormState extends State<SignUpCashierForm> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  String? _selectedBranchId;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name', descending: false)
          .get();
      if (!mounted) return;
      setState(() {
        _branches = snap.docs;
      });
    } catch (_) {
      // ignore errors, show empty list
    }
  }

  String? _validateFullName(String? name) {
    if (name == null || name.trim().isEmpty) return "Enter your full name";
    final trimmed = name.trim();
    if (trimmed.length < 3) return "Name must be at least 3 characters";
    final parts =
        trimmed.split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return "Enter first and last name";
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return "Enter your email";
    final email = value.trim();
    final emailRegex =
        RegExp(r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", caseSensitive: false);
    if (!emailRegex.hasMatch(email)) return "Enter a valid email";
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "Enter a password";
    if (value.length < 8) return "Minimum 8 characters";
    if (!RegExp(r'[A-Z]').hasMatch(value)) return "Add at least 1 uppercase";
    if (!RegExp(r'[a-z]').hasMatch(value)) return "Add at least 1 lowercase";
    if (!RegExp(r'[0-9]').hasMatch(value)) return "Add at least 1 number";
    if (!RegExp(r'[!@#\$&*~^_\-+=().,:;?/\\]').hasMatch(value)) {
      return "Add at least 1 special character";
    }
    if (value.contains(' ')) return "Password cannot contain spaces";
    final emailLocal = emailController.text.trim().split('@').first;
    if (emailLocal.isNotEmpty &&
        value.toLowerCase().contains(emailLocal.toLowerCase())) {
      return "Password must not contain your email username";
    }
    if (value.toLowerCase().contains('password'))
      return "Avoid using common words";
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return "Confirm your password";
    if (value != passwordController.text) return "Passwords do not match";
    return null;
  }

  Future<void> _signUp() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    // Branch is validated by form validator below

    if (widget.formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      final fullName = fullNameController.text.trim();

      try {
        final userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'fullName': fullName,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'role': 'cashier',
          'branchId': _selectedBranchId,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cashier account created.')),
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          LoginEmployeeScreenRoute,
          (route) => false,
        );
      } on FirebaseAuthException catch (e) {
        String message = 'Sign-up failed';
        switch (e.code) {
          case 'email-already-in-use':
            message = 'This email is already in use.';
            break;
          case 'invalid-email':
            message = 'Invalid email format.';
            break;
          case 'weak-password':
            message = 'Password is too weak.';
            break;
          case 'operation-not-allowed':
            message = 'Email/password accounts are not enabled.';
            break;
          case 'network-request-failed':
            message = 'Network error. Check your connection.';
            break;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An unexpected error occurred.')),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        children: [
          TextFormField(
            controller: fullNameController,
            validator: _validateFullName,
            cursorColor: Colors.black,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(
              hintText: "Full Name",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: const Icon(
                  Icons.person,
                  size: 24,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: emailController,
            validator: _validateEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            cursorColor: Colors.black,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              hintText: "Email address",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: const Icon(Icons.email, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: passwordController,
            obscureText: _obscurePassword,
            validator: _validatePassword,
            textInputAction: TextInputAction.next,
            cursorColor: Colors.black,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              hintText: "Password",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: const Icon(Icons.lock, color: Colors.grey),
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() {
                  _obscurePassword = !_obscurePassword;
                }),
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            validator: _validateConfirmPassword,
            textInputAction: TextInputAction.done,
            cursorColor: Colors.black,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              hintText: "Confirm Password",
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: defaultPadding * 0.75),
                child: const Icon(Icons.lock, color: Colors.grey),
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                }),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: defaultPadding),
          DropdownButtonFormField<String>(
            value: _selectedBranchId,
            items: _branches
                .map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        d.data()['name']?.toString() ?? d.id,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedBranchId = v),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please select a branch' : null,
            decoration: const InputDecoration(
              labelText: 'Select Branch',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
          ),
          const SizedBox(height: defaultPadding * 1.5),
          SizedBox(
            width: double.infinity,
            height: 57,
            child: ElevatedButton(
              onPressed: _isLoading || _branches.isEmpty ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(_branches.isEmpty
                      ? 'Loading branches…'
                      : 'Create Cashier Account'),
            ),
          ),
        ],
      ),
    );
  }
}
