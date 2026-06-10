import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'widgets/friendly_error.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Weight History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () => _generateAndPrintPdf(context, user.uid),
                label: const Text(
                  "Generate Report",
                  style: TextStyle(
                    color: Colors.blueAccent,
                    //fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                icon: const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.blueAccent,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
      extendBodyBehindAppBar: false,
      body: user == null
          ? const Center(child: Text("Please log in to see history"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('weights')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FriendlyErrorState(error: snapshot.error);
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                List<QueryDocumentSnapshot> sortedDocs = List.from(docs);
                sortedDocs.sort((a, b) {
                  Timestamp t1 = a['timestamp'] ?? Timestamp.now();
                  Timestamp t2 = b['timestamp'] ?? Timestamp.now();
                  return t1.compareTo(t2);
                });

                if (sortedDocs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No weight records yet.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                List<FlSpot> weightSpots = [];
                for (int i = 0; i < sortedDocs.length; i++) {
                  final data = sortedDocs[i].data() as Map<String, dynamic>;
                  double w = (data['weight'] as num).toDouble();
                  weightSpots.add(FlSpot(i.toDouble(), w));
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Area Chart with Floating Values
                      if (weightSpots.isNotEmpty)
                        Container(
                          height: 240,
                          margin: const EdgeInsets.only(top: 10, bottom: 20),
                          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[900] : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: LineChart(
                            LineChartData(
                              lineTouchData: LineTouchData(
                                enabled: false, // Labels are persistent
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (spot) => Colors.transparent,
                                  tooltipPadding: EdgeInsets.zero,
                                  tooltipMargin: 8,
                                  tooltipRoundedRadius: 0,
                                  tooltipBorder: BorderSide.none,
                                  getTooltipItems:
                                      (List<LineBarSpot> touchedBarSpots) {
                                        return touchedBarSpots.map((barSpot) {
                                          return LineTooltipItem(
                                            barSpot.y.toStringAsFixed(1),
                                            TextStyle(
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.blueAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          );
                                        }).toList();
                                      },
                                ),
                              ),
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: weightSpots,
                                  isCurved: true,
                                  barWidth: 4,
                                  color: Colors.blueAccent,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) =>
                                            FlDotCirclePainter(
                                              radius: 4,
                                              color: Colors.white,
                                              strokeWidth: 2,
                                              strokeColor: Colors.blueAccent,
                                            ),
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blueAccent.withValues(
                                          alpha: 0.3,
                                        ),
                                        Colors.blueAccent.withValues(
                                          alpha: 0.0,
                                        ),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ],
                              // This makes the labels persistent for every dot
                              showingTooltipIndicators: weightSpots
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                    return ShowingTooltipIndicators([
                                      LineBarSpot(
                                        LineChartBarData(
                                          spots: weightSpots,
                                          color: Colors.blueAccent,
                                        ),
                                        0,
                                        entry.value,
                                      ),
                                    ]);
                                  })
                                  .toList(),
                            ),
                          ),
                        ),

                      const Row(
                        children: [
                          Text(
                            "Timeline",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.swap_vert, size: 16, color: Colors.grey),
                          Text(
                            " Newest first",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: sortedDocs.length,
                          itemBuilder: (context, index) {
                            final doc =
                                sortedDocs[sortedDocs.length - 1 - index];
                            final data = doc.data() as Map<String, dynamic>;
                            final timestamp = data['timestamp'] as Timestamp?;
                            final weight = data['weight'];
                            final bmiValue = (data['bmi'] ?? 0.0) as num;

                            return TweenAnimationBuilder<double>(
                              duration: Duration(
                                milliseconds: 300 + (index * 50).clamp(0, 300),
                              ),
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Dismissible(
                                  key: Key(doc.id),
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (direction) async {
                                    final backupData =
                                        Map<String, dynamic>.from(data);
                                    final docId = doc.id;
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );

                                    await FirebaseFirestore.instance
                                        .collection('weights')
                                        .doc(docId)
                                        .delete();

                                    messenger.clearSnackBars();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text("Record removed"),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        action: SnackBarAction(
                                          label: "UNDO",
                                          onPressed: () {
                                            FirebaseFirestore.instance
                                                .collection('weights')
                                                .doc(docId)
                                                .set(backupData);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  background: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                          color: Colors.white,
                                        ),
                                        Text(
                                          "Delete",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(
                                        color: isDark
                                            ? Colors.grey[800]!
                                            : Colors.grey[200]!,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                      leading: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(
                                            alpha: 0.1,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.monitor_weight_outlined,
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Text(
                                            "$weight kg",
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              "BMI: ${bmiValue.toStringAsFixed(1)}",
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          timestamp != null
                                              ? _formatDate(timestamp.toDate())
                                              : 'Syncing...',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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

  Future<void> _generateAndPrintPdf(BuildContext context, String uid) async {
    final pdf = pw.Document();

    // Fetch User Data
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userData = userDoc.data() ?? {};

    // Fetch Weight Data
    final weightSnap = await FirebaseFirestore.instance
        .collection('weights')
        .where('userId', isEqualTo: uid)
        .get();

    List<QueryDocumentSnapshot> sortedWeights = List.from(weightSnap.docs);
    sortedWeights.sort((a, b) {
      Timestamp t1 = a['timestamp'] ?? Timestamp.now();
      Timestamp t2 = b['timestamp'] ?? Timestamp.now();
      return t2.compareTo(t1); // Newest first for the report
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "FitNet Health Report",
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(DateTime.now().toString().substring(0, 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Personal Information",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Text(
                  "Name: ",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text("${userData['firstName']} ${userData['lastName']}"),
              ],
            ),
            pw.Row(
              children: [
                pw.Text(
                  "Email: ",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text("${userData['email']}"),
              ],
            ),
            pw.Row(
              children: [
                pw.Text(
                  "Height: ",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text("${userData['height']} m"),
              ],
            ),
            pw.Row(
              children: [
                pw.Text(
                  "Target Weight: ",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text("${userData['goalWeight']} kg"),
              ],
            ),

            pw.SizedBox(height: 30),
            pw.Text(
              "Weight History Log",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),

            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        "Date",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        "Weight (kg)",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        "BMI",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                ...sortedWeights.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final date =
                      (data['timestamp'] as Timestamp?)
                          ?.toDate()
                          .toString()
                          .substring(0, 16) ??
                      "N/A";
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(date),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text("${data['weight']}"),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          (data['bmi'] as num?)?.toStringAsFixed(1) ?? 'N/A',
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'FitNet_Report_${userData['firstName']}.pdf',
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
