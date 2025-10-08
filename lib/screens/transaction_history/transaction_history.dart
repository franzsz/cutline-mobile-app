import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:intl/intl.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final GlobalKey previewContainer = GlobalKey();

  Future<void> exportToGallery(Uint8List imageBytes) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission denied!')),
      );
      return;
    }

    try {
      final directory = Directory('/storage/emulated/0/Download');
      // ✅ safe path
      final path =
          '${directory.path}/transaction_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(imageBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receipt saved at: $path')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save receipt: $e')),
      );
    }
  }

  Future<Uint8List?> _capturePng() async {
    try {
      RenderRepaintBoundary boundary = previewContainer.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      var image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print("Error capturing image: $e");
      return null;
    }
  }

  void showTransactionDetails(Map<String, dynamic> transaction) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return RepaintBoundary(
          key: previewContainer,
          child: Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text('Receipt Details',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 10),
                Text('Customer: ${transaction['customerName'] ?? 'N/A'}'),
                Text('Barber: ${transaction['barberName'] ?? 'N/A'}'),
                Text('Queue #: ${transaction['queueNumber'] ?? 'N/A'}'),
                Text(
                    'Payment Method: ${transaction['paymentMethod'] ?? 'N/A'}'),
                Text('Amount: ₱${transaction['paymentAmount'] ?? 0}'),
                Text('Status: ${transaction['status'] ?? 'Pending'}'),
                Text(
                    'Date: ${DateFormat.yMMMd().add_jm().format(transaction['createdAt'].toDate())}'),
                const SizedBox(height: 20),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Export Receipt'),
                    onPressed: () async {
                      // Wait for the widget to finish rendering
                      await Future.delayed(Duration.zero);
                      await WidgetsBinding.instance.endOfFrame;

                      final image = await _capturePng();
                      if (image != null) {
                        await exportToGallery(image);
                      }
                    },
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshTransactions() async {
    // Force refresh by rebuilding the StreamBuilder
    setState(() {});
    // Add a small delay to show the refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Transaction History"),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshTransactions,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text("Error loading transactions."));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final transactions = snapshot.data!.docs;

            if (transactions.isEmpty) {
              return const Center(child: Text("No transactions found."));
            }

            return ListView.builder(
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final data = transactions[index].data() as Map<String, dynamic>;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text("₱${data['paymentAmount']}"),
                    subtitle: Text(
                        "Barber: ${data['barberName'] ?? 'N/A'}\nPaid via ${data['paymentMethod'] ?? 'N/A'}"),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long),
                        Text("#${data['queueNumber'] ?? '0'}"),
                      ],
                    ),
                    onTap: () => showTransactionDetails(data),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
