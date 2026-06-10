import 'package:flutter/material.dart';

import '../main.dart' show themeNotifier;
import '../services/gemini_service.dart'
    show geminiPrimaryModel, geminiFallbackModel;
import '../storage/app_preferences.dart';

/// App settings backed by SharedPreferences (course topic: Shared
/// Preferences). Stores lightweight UI preferences only — fitness data
/// stays in Firestore.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppPreferences get _prefs => AppPreferences.instance;

  Future<void> _setThemeMode(ThemeMode? mode) async {
    if (mode == null) return;
    themeNotifier.value = mode;
    await _prefs.setThemeMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _editWaterGoal() async {
    final controller = TextEditingController(
      text: _prefs.dailyWaterGoalMl.toString(),
    );
    final newGoal = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily water goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Goal in ml',
            hintText: 'Example: 2500',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a positive amount in ml.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newGoal == null) return;
    await _prefs.setDailyWaterGoalMl(newGoal);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Appearance'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeNotifier.value,
              onChanged: _setThemeMode,
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('Follow system'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Light'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Dark'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Hydration'),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.water_drop_outlined,
                color: Colors.blueAccent,
              ),
              title: const Text('Daily water goal'),
              subtitle: Text('${_prefs.dailyWaterGoalMl} ml'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editWaterGoal,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('AI Coach'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.psychology_outlined, color: Colors.blue),
                  title: Text('Primary model'),
                  subtitle: Text(geminiPrimaryModel),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.alt_route_outlined, color: Colors.blue),
                  title: Text('Fallback model'),
                  subtitle: Text(geminiFallbackModel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.monitor_weight_outlined, color: Colors.blue),
              title: Text('FitNet'),
              subtitle: Text(
                'IoT smart-scale fitness tracker.\n'
                'Theme, last tab, and water goal are stored locally with '
                'SharedPreferences; meals are mirrored to a local SQLite '
                'cache for offline viewing.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
