import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shop/constants.dart';
import 'package:shop/app_config.dart';
import 'package:shop/route/route_constants.dart';

class VerifyCodeScreen extends StatefulWidget {
  final String uid;
  final String email;

  const VerifyCodeScreen({
    super.key,
    required this.uid,
    required this.email,
  });

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final TextEditingController codeController = TextEditingController();
  bool isVerifying = false;

  Future<void> _verifyCode() async {
    setState(() => isVerifying = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final data = doc.data();

      if (data == null ||
          data['verificationCode'] == null ||
          data['codeExpiresAt'] == null) {
        _showMessage('Invalid verification setup. Please login again.');
        return;
      }

      final savedCode = data['verificationCode'].toString();
      final expiresAt = (data['codeExpiresAt'] as Timestamp).toDate();

      if (DateTime.now().isAfter(expiresAt)) {
        _showMessage('Code expired. Please login again.');
        return;
      }

      if (codeController.text.trim() != savedCode) {
        _showMessage('Incorrect verification code.');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'verificationCode': FieldValue.delete(),
        'codeExpiresAt': FieldValue.delete(),
      });

      // After successful verification, route based on role
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final role = userDoc.data()?['role'];
      final branchId = userDoc.data()?['branchId'];

      if (role == 'cashier') {
        final String targetBranchId =
            (branchId is String && branchId.isNotEmpty)
                ? branchId
                : kHardwiredBranchId;
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          cashierQueueScreenRoute,
          (route) => false,
          arguments: targetBranchId,
        );
        return;
      }

      if (role == 'barber') {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          employeeQueueScreenRoute,
          (route) => false,
        );
        return;
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        entryPoint2ScreenRoute,
        (route) => false,
      );
    } catch (e) {
      _showMessage('Verification failed. Please try again.');
    } finally {
      setState(() => isVerifying = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    setState(() => isVerifying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Code')),
      body: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("A verification code has been sent to ${widget.email}."),
            const SizedBox(height: defaultPadding),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Enter 6-digit code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: defaultPadding * 2),
            ElevatedButton(
              onPressed: isVerifying ? null : _verifyCode,
              child: isVerifying
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
