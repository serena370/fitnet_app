import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'history_page.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'profile_page.dart';
import 'login_page.dart';

// Global notifier for theme management
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

final FlutterLocalNotificationsPlugin notificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const AndroidInitializationSettings androidInit =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
  InitializationSettings(android: androidInit);

  await notificationsPlugin.initialize(initSettings);

  runApp(FitNetApp());
}

class FitNetApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: currentMode,
          home: AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return HomePage();
        } else {
          return LoginPage();
        }
      },
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic>? userData;
  double weight = 0;
  double height = 1.70; 
  bool isAppInForeground = true;

  late MqttServerClient client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadUserData();
    connectMQTT();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    isAppInForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      client.disconnect();
    } catch (e) {
      debugPrint("Error disconnecting MQTT: $e");
    }
    super.dispose();
  }

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!mounted) return;

    if (doc.exists) {
      final data = doc.data();
      setState(() {
        userData = data;
        double h = (data?['height'] ?? 1.70).toDouble();
        if (h > 0) height = h;
      });
    }
  }

  double get bmi {
    if (weight == 0 || height <= 0) return 0.0;
    return weight / (height * height);
  }

  String get status {
    if (bmi == 0) return "Waiting...";
    if (bmi < 18.5) return "Underweight";
    if (bmi < 25) return "Normal";
    return "Overweight";
  }

  Color get statusColor {
    if (bmi == 0) return Colors.grey;
    if (bmi < 18.5) return Colors.orange;
    if (bmi < 25) return Colors.green;
    return Colors.red;
  }

  double get remainingToGoal {
    double goal = (userData?['goalWeight'] ?? 0).toDouble();
    if (goal == 0 || weight == 0) return 0;
    return (weight - goal).abs();
  }

  String get goalAction {
    double goal = (userData?['goalWeight'] ?? 0).toDouble();
    if (goal == 0) return "";
    return weight > goal ? "to lose" : "to gain";
  }

  Future<void> connectMQTT() async {
    client = MqttServerClient(
      'broker.hivemq.com',
      'fitnet_client_${DateTime.now().millisecondsSinceEpoch}',
    );

    client.port = 1883;
    client.keepAlivePeriod = 60;
    client.autoReconnect = true;

    try {
      await client.connect();
      client.subscribe("fitnet/weight", MqttQos.atMostOnce);
      client.updates!.listen((messages) {
        final message = messages[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(message.payload.message);
        final data = jsonDecode(payload);

        if (mounted) {
          setState(() {
            weight = (data['weight'] as num).toDouble();
          });

          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            FirebaseFirestore.instance.collection('weights').add({
              'weight': weight,
              'bmi': bmi,
              'timestamp': FieldValue.serverTimestamp(),
              'userId': user.uid,
            });
          }

          if (!isAppInForeground) {
            final String name = userData?['firstName'] ?? "User";
            final double goal = (userData?['goalWeight'] ?? 0).toDouble();
            
            String title = "New Weight Recorded";
            String body = "${weight.toStringAsFixed(1)} kg - BMI: ${bmi.toStringAsFixed(1)}";

            if (goal > 0) {
              double diff = remainingToGoal;
              if (diff < 0.5) {
                title = "Goal Reached! 🏆";
                body = "Amazing job $name! You hit your target weight of ${goal.toStringAsFixed(1)} kg!";
              } else {
                title = "Progress Update, $name! 💪";
                body = "You're at ${weight.toStringAsFixed(1)} kg. Only ${diff.toStringAsFixed(1)} kg left $goalAction!";
              }
            }

            notificationsPlugin.show(
              0,
              title,
              body,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'fitnet_channel',
                  'FitNet Alerts',
                  importance: Importance.max,
                  priority: Priority.high,
                  showWhen: true,
                ),
              ),
            );
          }
        }
      });
    } catch (e) {
      debugPrint("MQTT Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("FitNet"),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, child) {
              return IconButton(
                icon: Icon(mode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
                onPressed: () {
                  themeNotifier.value = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
                },
                tooltip: "Toggle Theme",
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (context) => ProfilePage()));
              loadUserData(); 
            },
          ),
          IconButton(
            icon: Icon(Icons.history),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => HistoryPage())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: userData == null
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadUserData,
              child: SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text("Welcome ${userData!['firstName'] ?? 'User'} 👋",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 30),
                    _buildCard("Current Weight",
                        "${weight.toStringAsFixed(1)} kg", Icons.monitor_weight),
                    SizedBox(height: 20),
                    _buildCard("BMI", bmi.toStringAsFixed(1), Icons.speed,
                        subtitle: status, color: statusColor),
                    SizedBox(height: 20),
                    _buildCard("Goal Weight",
                        "${userData!['goalWeight'] ?? '--'} kg", Icons.flag),
                    
                    if (userData!['goalWeight'] != null && weight > 0)
                      _buildGoalProgressCard(),

                    SizedBox(height: 20),
                    Text(
                        "Height used for calculation: ${height.toStringAsFixed(2)}m",
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGoalProgressCard() {
    double remaining = remainingToGoal;
    String action = goalAction;
    Color progressColor = remaining < 2 ? Colors.green : Colors.orange;

    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Goal Progress", style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                Text("${remaining.toStringAsFixed(1)} kg $action", 
                  style: TextStyle(fontWeight: FontWeight.bold, color: progressColor)),
              ],
            ),
            SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: remaining > 20 ? 0.1 : (1.0 - (remaining / 20.0)).clamp(0.1, 1.0),
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            SizedBox(height: 8),
            Text(
              remaining < 0.5 ? "You've reached your goal! 🎉" : "Keep going! You're getting closer.",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, String value, IconData icon,
      {String? subtitle, Color? color}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color ?? Colors.blue),
            SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                Text(value,
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 16,
                          color: color,
                          fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
