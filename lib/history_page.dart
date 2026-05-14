import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("Weight History"),
      ),
      body: user == null
          ? Center(child: Text("Please log in to see history"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('weights')
                  .where('userId', isEqualTo: user.uid)
                  // Removed orderBy here to avoid the index error
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }


                final docs = snapshot.data?.docs ?? [];
                
                // Sort by timestamp (Oldest first for the graph)
                List<QueryDocumentSnapshot> sortedDocs = List.from(docs);
                sortedDocs.sort((a, b) {
                  Timestamp t1 = a['timestamp'] ?? Timestamp.now();
                  Timestamp t2 = b['timestamp'] ?? Timestamp.now();
                  return t1.compareTo(t2);
                });

                if (sortedDocs.isEmpty) {
                  return Center(child: Text("No weight records found."));
                }

                List<FlSpot> weightSpots = [];
                for (int i = 0; i < sortedDocs.length; i++) {
                  final data = sortedDocs[i].data() as Map<String, dynamic>;
                  double w = (data['weight'] as num).toDouble();
                  weightSpots.add(FlSpot(i.toDouble(), w));
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (weightSpots.isNotEmpty)
                        SizedBox(
                          height: 250,
                          child: LineChart(
                            LineChartData(
                              gridData: FlGridData(show: true),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: weightSpots,
                                  isCurved: true,
                                  barWidth: 4,
                                  color: Colors.blue,
                                  dotData: FlDotData(show: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: sortedDocs.length,
                          itemBuilder: (context, index) {
                            // Show newest at the top (reverse the sorted list)
                            final data = sortedDocs[sortedDocs.length - 1 - index].data() as Map<String, dynamic>;
                            final timestamp = data['timestamp'] as Timestamp?;
                            final weight = data['weight'];
                            final bmiValue = (data['bmi'] ?? 0.0) as num;

                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Icon(Icons.monitor_weight, color: Colors.white),
                                ),
                                title: Text(
                                  "${weight} kg",
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  "BMI: ${bmiValue.toStringAsFixed(1)}\n${timestamp != null ? timestamp.toDate().toString().substring(0, 16) : 'Saving...'}",
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
