import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'coach_page.dart';
import 'login_page.dart';
import 'pages/meals_page.dart';
import 'pages/more_page.dart';
import 'pages/progress_page.dart';
import 'routes/app_routes.dart';
import 'services/fitness_repository.dart';
import 'services/gemini_service.dart';
import 'storage/app_preferences.dart';
import 'widgets/nav_card.dart';
import 'widgets/stat_card.dart';

// Global notifier for theme management
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // SharedPreferences-backed app settings (theme, last tab, water goal).
  await AppPreferences.init();
  themeNotifier.value = AppPreferences.instance.themeMode;

  // Timezone database for OS-scheduled reminders (water/workout).
  tzdata.initializeTimeZones();

  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
  );

  await notificationsPlugin.initialize(initSettings);
  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  GeminiService.initializeOnAppLaunch();

  runApp(const FitNetApp());
}

class FitNetApp extends StatelessWidget {
  const FitNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, child) {
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
          routes: AppRoutes.table,
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          return const MainPage();
        } else {
          return LoginPage();
        }
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _selectedIndex = AppPreferences.instance.lastTabIndex;
  Map<String, dynamic>? userData;
  double weight = 0;
  double height = 1.70;
  bool isAppInForeground = true;
  final FitnessRepository _fitnessRepository = FitnessRepository();

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

  void requestWeight() {
    final builder = MqttClientPayloadBuilder();
    builder.addString(
      jsonEncode({
        "command": "get_weight",
        "email": FirebaseAuth.instance.currentUser?.email,
      }),
    );

    client.publishMessage(
      "fitnet/get_weight",
      MqttQos.atMostOnce,
      builder.payload!,
    );
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
      client.subscribe("fitnet/reset", MqttQos.atMostOnce);

      client.updates!.listen((messages) {
        final message = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          message.payload.message,
        );
        final data = jsonDecode(payload);
        final topic = messages[0].topic;

        if (topic == "fitnet/reset") {
          if (mounted) setState(() => weight = 0);
        }

        if (topic == "fitnet/weight" && mounted) {
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
            String body =
                "${weight.toStringAsFixed(1)} kg - BMI: ${bmi.toStringAsFixed(1)}";

            if (goal > 0) {
              double diff = remainingToGoal;
              if (diff < 0.5) {
                title = "Goal Reached! 🏆";
                body =
                    "Amazing job $name! You hit your target weight of ${goal.toStringAsFixed(1)} kg!";
              } else {
                title = "Progress Update, $name! 💪";
                body =
                    "You're at ${weight.toStringAsFixed(1)} kg. Only ${diff.toStringAsFixed(1)} kg left $goalAction!";
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

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Remember the last selected tab (SharedPreferences course topic).
    AppPreferences.instance.setLastTabIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeView(),
      const CoachPage(),
      MealsPage(),
      const ProgressPage(),
      MorePage(onProfileUpdated: loadUserData),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', height: 32),
            ),
            const SizedBox(width: 10),
            const Text("FitNet", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, child) {
              return IconButton(
                icon: Icon(
                  mode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode,
                ),
                onPressed: () {
                  final next = mode == ThemeMode.light
                      ? ThemeMode.dark
                      : ThemeMode.light;
                  themeNotifier.value = next;
                  AppPreferences.instance.setThemeMode(next);
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.profile);
              loadUserData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'AI Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Meals',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_outlined),
            selectedIcon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeView() {
    if (userData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: loadUserData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                "Welcome ${userData!['firstName'] ?? 'User'} 👋",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                onPressed: requestWeight,
                icon: const Icon(Icons.refresh),
                label: const Text("Get Weight"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildCard(
              "Current Weight",
              "${weight.toStringAsFixed(1)} kg",
              Icons.monitor_weight,
            ),
            const SizedBox(height: 20),
            _buildCard(
              "BMI",
              bmi.toStringAsFixed(1),
              Icons.speed,
              subtitle: status,
              color: statusColor,
            ),
            const SizedBox(height: 20),
            _buildCard(
              "Target Weight",
              "${userData!['goalWeight'] ?? '--'} kg",
              Icons.flag,
            ),
            if (userData!['goalWeight'] != null && weight > 0)
              _buildGoalProgressCard(),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "Height used for calculation: ${height.toStringAsFixed(2)}m",
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Today",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatsSection(),
            const SizedBox(height: 12),
            _buildWaterSummaryCard(),
            const SizedBox(height: 24),
            const Text(
              "Quick Actions",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            NavCard(
              title: "Log food with AI Coach",
              subtitle: "Type \"I ate ...\" and it's logged instantly",
              icon: Icons.psychology_outlined,
              onTap: () => _selectTab(1),
            ),
            const SizedBox(height: 12),
            NavCard(
              title: "Scan a meal",
              subtitle: "Photo or description — AI estimates calories",
              icon: Icons.camera_alt_outlined,
              iconColor: Colors.orange,
              onTap: () => Navigator.pushNamed(context, AppRoutes.mealScan),
            ),
            const SizedBox(height: 12),
            NavCard(
              title: "Meal history",
              subtitle: "Review, edit or delete logged meals",
              icon: Icons.restaurant_outlined,
              iconColor: Colors.green,
              onTap: () => _selectTab(2),
            ),
            const SizedBox(height: 12),
            NavCard(
              title: "Find Nearby Gyms",
              subtitle: "Open a map with gyms around your location",
              icon: Icons.map_outlined,
              iconColor: Colors.teal,
              onTap: () => Navigator.pushNamed(context, AppRoutes.nearbyGyms),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return StreamBuilder<FitnessStats>(
      stream: _fitnessRepository.watchDashboardStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final stats = snapshot.data!;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'Eaten Today',
                    value: '${stats.caloriesEatenToday}',
                    subtitle: 'kcal',
                    icon: Icons.local_fire_department_outlined,
                    color: Colors.orange,
                    onTap: () => _selectTab(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    title: 'Workouts',
                    value: '${stats.workoutsThisWeek}',
                    subtitle: 'this week',
                    icon: Icons.fitness_center,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.workouts),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'Burned',
                    value: '${stats.caloriesBurnedThisWeek}',
                    subtitle: 'kcal this week',
                    icon: Icons.bolt_outlined,
                    color: Colors.deepOrange,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.workouts),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    title: 'Fitness Goals',
                    value: '${stats.activeGoals}',
                    subtitle: '${stats.completedGoals} completed',
                    icon: Icons.flag_outlined,
                    color: Colors.green,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.fitnessGoals),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Water summary read from the same Firestore document the Hydration page
  /// writes, with the goal coming from SharedPreferences.
  Widget _buildWaterSummaryCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final todayId = "${now.year}-${now.month}-${now.day}";
    final goalMl = AppPreferences.instance.dailyWaterGoalMl;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('water_logs')
          .doc(todayId)
          .snapshots(),
      builder: (context, snapshot) {
        final currentMl = snapshot.data?.data()?['amountMl'] as int? ?? 0;
        final progress = goalMl > 0
            ? (currentMl / goalMl).clamp(0.0, 1.0)
            : 0.0;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => Navigator.pushNamed(context, AppRoutes.water),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.water_drop_outlined,
                    color: Colors.blueAccent,
                    size: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Water',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Text(
                          '$currentMl / $goalMl ml',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.blueAccent.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGoalProgressCard() {
    double remaining = remainingToGoal;
    String action = goalAction;
    Color progressColor = remaining < 2 ? Colors.green : Colors.orange;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Target Progress",
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                Text(
                  "${remaining.toStringAsFixed(1)} kg $action",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: remaining > 20
                    ? 0.1
                    : (1.0 - (remaining / 20.0)).clamp(0.1, 1.0),
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              remaining < 0.5
                  ? "You've reached your target weight! 🎉"
                  : "Keep going! You're getting closer.",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    String title,
    String value,
    IconData icon, {
    String? subtitle,
    Color? color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color ?? Colors.blue),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
