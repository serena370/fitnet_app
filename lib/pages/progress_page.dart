import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../widgets/nav_card.dart';

/// Progress hub: groups weight history, hydration, and body measurements
/// into a single tracking tab. The weight history still reads from the IoT
/// smart-scale `weights` collection — that flow is unchanged.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Progress',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Track how your body is changing over time.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          NavCard(
            title: 'Weight History',
            subtitle: 'Smart-scale readings, BMI chart & PDF report',
            icon: Icons.monitor_weight_outlined,
            onTap: () => Navigator.pushNamed(context, AppRoutes.weightHistory),
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Hydration',
            subtitle: 'Daily water intake & reminders',
            icon: Icons.water_drop_outlined,
            iconColor: Colors.blueAccent,
            onTap: () => Navigator.pushNamed(context, AppRoutes.water),
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Body Measurements',
            subtitle: 'Waist, chest, arms & hips over time',
            icon: Icons.straighten_outlined,
            iconColor: Colors.purple,
            onTap: () => Navigator.pushNamed(context, AppRoutes.measurements),
          ),
        ],
      ),
    );
  }
}
