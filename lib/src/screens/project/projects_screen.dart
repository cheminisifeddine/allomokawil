import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../models/project.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/project_card.dart';
import 'project_detail_screen.dart';

/// "My projects" with status tabs, shared by customers and workers
/// (both have a cap to reach the detail screen of a project they're involved in).
class ProjectsScreen extends StatefulWidget {
  final Repository repo;

  const ProjectsScreen({super.key, required this.repo});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  ProjectStatus _status = ProjectStatus.open;
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.myProjects(status: _status);
  }

  void _reload(ProjectStatus s) {
    setState(() {
      _status = s;
      _future = widget.repo.myProjects(status: s);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشاريعي')),
      body: Column(
        children: [
          SegmentedButton<ProjectStatus>(
            segments: const [
              ButtonSegment(
                  value: ProjectStatus.open, label: Text('مفتوح')),
              ButtonSegment(
                  value: ProjectStatus.inProgress, label: Text('قيد التنفيذ')),
              ButtonSegment(
                  value: ProjectStatus.completed, label: Text('منجز')),
              ButtonSegment(
                  value: ProjectStatus.cancelled, label: Text('ملغى')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => _reload(s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Project>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingList(count: 4);
                }
                if (snap.hasError) {
                  return EmptyState(
                      icon: Icons.wifi_off,
                      title: 'تعذّر جلب المشاريع',
                      action: TextButton(
                          onPressed: () => _reload(_status),
                          child: const Text('إعادة المحاولة')));
                }
                final projects = snap.data ?? const [];
                if (projects.isEmpty) {
                  return const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: 'لا مشاريع في هذه الحالة');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => ProjectCard(
                    project: projects[i],
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ProjectDetailScreen(
                                projectId: projects[i].id,
                                repo: widget.repo))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}