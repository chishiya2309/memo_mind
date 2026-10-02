import 'package:flutter/material.dart';

import '../application/reminder_coordinator.dart';
import 'reminder_settings_screen.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key, required this.coordinator});
  final ReminderCoordinator coordinator;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cá nhân')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Cài đặt'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Cài đặt')),
                body: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Nhắc học'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ReminderSettingsScreen(coordinator: coordinator),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
