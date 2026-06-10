import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/reminder_scheduler.dart';
import 'storage/app_preferences.dart';

class WaterPage extends StatefulWidget {
  const WaterPage({super.key});

  @override
  State<WaterPage> createState() => _WaterPageState();
}

class _WaterPageState extends State<WaterPage> {
  static const int _reminderNotificationId = 1001;

  // Daily goal is a user preference (SharedPreferences), editable in
  // Settings. Defaults to 2.5 liters.
  int get dailyGoalMl => AppPreferences.instance.dailyWaterGoalMl;
  int currentMl = 0;
  bool isLoading = true;

  // Reminder State
  DateTime? _targetDateTime;
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadDailyWater();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _updateTimeLeft();
    // This timer only drives the on-screen countdown. The notification
    // itself is OS-scheduled via ReminderScheduler, so it fires even if the
    // app is closed before the chosen time.
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateTimeLeft();
        });
      }
      if (_timeLeft.inSeconds <= 0) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _targetDateTime = null;
          });
        }
      }
    });
  }

  void _updateTimeLeft() {
    if (_targetDateTime == null) return;
    final now = DateTime.now();
    _timeLeft = _targetDateTime!.difference(now);
    if (_timeLeft.isNegative) _timeLeft = Duration.zero;
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  Future<void> _setReminder() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: "SELECT REMINDER TIME",
    );

    if (picked != null) {
      final now = DateTime.now();
      var reminderDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );

      if (reminderDateTime.isBefore(now)) {
        reminderDateTime = reminderDateTime.add(const Duration(days: 1));
      }

      ReminderScheduler.schedule(
        notificationId: _reminderNotificationId,
        title: 'Time to drink water! 💧',
        body: 'Stay hydrated and reach your daily goal!',
        reminderAt: reminderDateTime,
        channelId: 'water_reminder_channel',
        channelName: 'Water Reminder',
        channelDescription: 'Daily hydration reminders',
      );

      setState(() {
        _targetDateTime = reminderDateTime;
        _startTimer();
      });
    }
  }

  String _getTodayId() {
    final now = DateTime.now();
    return "${now.year}-${now.month}-${now.day}";
  }

  Future<void> _loadDailyWater() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('water_logs')
        .doc(_getTodayId())
        .get();

    if (doc.exists) {
      setState(() {
        currentMl = doc.data()?['amountMl'] ?? 0;
      });
    }
    setState(() => isLoading = false);
  }

  Future<void> _addWater(int amount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      currentMl += amount;
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('water_logs')
        .doc(_getTodayId())
        .set({
          'amountMl': currentMl,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _resetWater() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      currentMl = 0;
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('water_logs')
        .doc(_getTodayId())
        .set({'amountMl': 0, 'timestamp': FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {
    double progress = (currentMl / dailyGoalMl).clamp(0.0, 1.0);
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Hydration Tracker",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _resetWater,
            tooltip: "Reset Today",
          ),
        ],
      ),
      body: Column(
        children: [
          // Sticky Countdown at the top
          if (_targetDateTime != null)
            Container(
              width: double.infinity,
              color: Colors.blueAccent.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Reminder in: ${_formatDuration(_timeLeft)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      ReminderScheduler.cancel(_reminderNotificationId);
                      setState(() {
                        _timer?.cancel();
                        _targetDateTime = null;
                      });
                    },
                    child: const Icon(
                      Icons.cancel,
                      size: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _setReminder,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                    ),
                    label: const Text("Set Water Reminder"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withValues(alpha: 0.05),
                      foregroundColor: Colors.blueAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Progress Ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 250,
                        width: 250,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 15,
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          color: Colors.blueAccent,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        children: [
                          const Icon(
                            Icons.water_drop,
                            size: 50,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "${(progress * 100).toInt()}%",
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "$currentMl / $dailyGoalMl ml",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),

                  const Text(
                    "Quick Add",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildWaterButton(100, Icons.local_drink_outlined),
                      _buildWaterButton(250, Icons.local_drink),
                      _buildWaterButton(500, Icons.water_drop),
                    ],
                  ),

                  const SizedBox(height: 40),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.blue.withValues(alpha: 0.1)
                          : Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            progress >= 1.0
                                ? "Goal reached! You are perfectly hydrated today. 💧"
                                : "Drinking water helps boost metabolism and keeps your skin glowing!",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.blue[100]
                                  : Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaterButton(int amount, IconData icon) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => _addWater(amount),
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(20),
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
          child: Icon(icon, size: 30),
        ),
        const SizedBox(height: 8),
        Text("$amount ml", style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
