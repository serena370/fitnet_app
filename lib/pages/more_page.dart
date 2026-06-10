import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../widgets/nav_card.dart';

/// "More" hub: profile, fitness goals, workouts, nearby gyms, and settings.
class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onProfileUpdated});

  /// Called after the profile screen pops with changes so the dashboard can
  /// reload user data (height, target weight) used by the smart-scale cards.
  final VoidCallback onProfileUpdated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'More',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NavCard(
            title: 'Profile',
            subtitle: 'Personal details, height & target weight',
            icon: Icons.person_outline,
            onTap: () async {
              final updated = await Navigator.pushNamed(
                context,
                AppRoutes.profile,
              );
              if (updated == true) onProfileUpdated();
            },
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Fitness Goals',
            subtitle: 'Daily & weekly activity targets',
            icon: Icons.flag_outlined,
            iconColor: Colors.green,
            onTap: () => Navigator.pushNamed(context, AppRoutes.fitnessGoals),
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Workouts',
            subtitle: 'Log activities & calories burned',
            icon: Icons.fitness_center,
            iconColor: Colors.deepOrange,
            onTap: () => Navigator.pushNamed(context, AppRoutes.workouts),
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Nearby Gyms',
            subtitle: 'Find gyms around your location',
            icon: Icons.map_outlined,
            iconColor: Colors.teal,
            onTap: () => Navigator.pushNamed(context, AppRoutes.nearbyGyms),
          ),
          const SizedBox(height: 12),
          NavCard(
            title: 'Settings',
            subtitle: 'Theme, water goal & app preferences',
            icon: Icons.settings_outlined,
            iconColor: Colors.blueGrey,
            onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
    );
  }
}
