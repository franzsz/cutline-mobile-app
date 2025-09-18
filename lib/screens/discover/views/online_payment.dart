import 'package:flutter/material.dart';

class OnlinePaymentScreen extends StatelessWidget {
  final String queueDocId;

  const OnlinePaymentScreen({super.key, required this.queueDocId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Payment'),
        backgroundColor: const Color.fromARGB(255, 253, 253, 253),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Payment Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text('Total Amount: ₱200'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text('Pay with GCash'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 40, 104, 201),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                // TODO: Integrate GCash or payment logic
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Payment successful")),
                );

                // Simulate confirmation and go back
                Navigator.pop(context, true); // return success
              },
            ),
          ],
        ),
      ),
    );
  }
}
