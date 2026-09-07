import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../customer/customer_home_screen.dart';
import '../worker/worker_home_screen.dart';

/// Role-aware root shell.
///
/// - `customer`: search & top-rated contractors + "post a project".
/// - `worker`: project marketplace + filters + their own profile.
class RoleHome extends StatelessWidget {
  final UserRole role;

  const RoleHome({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    if (role == UserRole.customer) return const CustomerHomeScreen();
    return const WorkerHomeScreen();
  }
}