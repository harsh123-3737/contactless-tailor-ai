import 'dart:io';

import 'package:flutter/material.dart';

import 'database_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _scans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    // Pull from the database
    final data = await DatabaseHelper.instance.readAllScans();

    // DEBUG TRACKER: This will print into your VS Code terminal!
    print("==== DATABASE CHECK: FETCHED ${data.length} SCANS ====");

    setState(() {
      _scans = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Scan History"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // NEW REFRESH BUTTON
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                _loadHistory, // Forces the screen to check the database again
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
            )
          : _scans.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.straighten_outlined,
                        size: 64,
                        color: Colors.deepPurpleAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "No Saved Scans Yet",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Capture a photo using the calibration card to view your automated tailoring measurements here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _scans.length,
              itemBuilder: (context, index) {
                final scan = _scans[index];
                final scanId = scan['scan_id'].toString();

                DateTime date =
                    DateTime.tryParse(scan['created_at'].toString()) ??
                    DateTime.now();
                String formattedDate =
                    "${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}";

                return Dismissible(
                  // The unique key tells Flutter which specific item to slide away
                  key: Key(scanId),
                  direction: DismissDirection.endToStart, // Swipe right-to-left
                  // The red trash can background that reveals underneath
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                  // The action triggered when the swipe completes
                  onDismissed: (direction) async {
                    // 1. Delete from SQLite database
                    await DatabaseHelper.instance.deleteScan(scanId);

                    // 2. Remove from the screen instantly
                    setState(() {
                      _scans.removeAt(index);
                    });

                    // 3. Show a quick confirmation
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Scan deleted"),
                        backgroundColor: Colors.redAccent,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },

                  // Your existing sleek Card UI
                  child: Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child:
                                scan['image_path'] != 'No Image' &&
                                    File(scan['image_path']).existsSync()
                                ? Image.file(
                                    File(scan['image_path']),
                                    width: 80,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 80,
                                    height: 100,
                                    color: Colors.black26,
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white24,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formattedDate,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Size: ${scan['recommended_size']}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "ID: ${scanId.length > 8 ? scanId.substring(0, 8) : scanId}...",
                                  style: const TextStyle(
                                    color: Colors.deepPurpleAccent,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
