import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../data/taxonomy.dart';

/// Lightweight account screen shared by both roles: identity info,
/// wilaya help, and logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final u = scope.auth.user!;
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFE0E5F0),
                child: Text(
                  u.fullName.isEmpty ? '؟' : u.fullName.characters.first,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.fullName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(u.phone, style: const TextStyle(color: Color(0xFF6E6E73))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (u.wilaya != null)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(Taxonomy.wilayaName(u.wilaya!)),
              subtitle: const Text('الولاية'),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('تسجيل الخروج'),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            onTap: () async {
              await scope.auth.logout();
            },
          ),
        ],
      ),
    );
  }
}