import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/northstar_theme.dart';
import '../features/health/health_page.dart';
import '../features/progress/progress_page.dart';
import '../features/progress/workout_history_detail_page.dart';
import '../features/today/today_page.dart';
import '../features/train/train_page.dart';
import '../features/train/exercise_catalog_page.dart';
import '../features/train/plan_editor_page.dart';
import '../features/train/active_workout_page.dart';
import 'floating_nav_bar.dart';
import 'theme_controller.dart';

final _routes = <String>['/today', '/train', '/progress', '/health'];
final _destinations = <NavigationDestination>[
  const NavigationDestination(
    icon: Icon(Icons.space_dashboard_outlined),
    selectedIcon: Icon(Icons.space_dashboard),
    label: 'Today',
  ),
  const NavigationDestination(
    icon: Icon(Icons.fitness_center_outlined),
    selectedIcon: Icon(Icons.fitness_center),
    label: 'Train',
  ),
  const NavigationDestination(
    icon: Icon(Icons.insights_outlined),
    selectedIcon: Icon(Icons.insights),
    label: 'Progress',
  ),
  const NavigationDestination(
    icon: Icon(Icons.favorite_border),
    selectedIcon: Icon(Icons.favorite),
    label: 'Health',
  ),
];

// Tabs swap in place; default page transitions keep the outgoing tab visible.
Page<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/today',
            pageBuilder: (_, state) => _tabPage(state, const TodayPage()),
          ),
          GoRoute(
            path: '/train',
            pageBuilder: (_, state) => _tabPage(state, const TrainPage()),
          ),
          GoRoute(
            path: '/train/workout',
            builder: (_, _) => const ActiveWorkoutPage(),
          ),
          GoRoute(
            path: '/train/exercises',
            builder: (_, _) => const ExerciseCatalogPage(),
          ),
          GoRoute(
            path: '/train/plans/new',
            builder: (_, _) => const PlanEditorPage(),
          ),
          GoRoute(
            path: '/train/plans/:id/edit',
            builder: (_, state) =>
                PlanEditorPage(planUuid: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/progress',
            pageBuilder: (_, state) => _tabPage(state, const ProgressPage()),
          ),
          GoRoute(
            path: '/progress/workouts/:id',
            builder: (_, state) => WorkoutHistoryDetailPage(
              sessionUuid: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/health',
            pageBuilder: (_, state) => _tabPage(state, const HealthPage()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class NorthstarApp extends ConsumerWidget {
  const NorthstarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'Northstar Health',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: NorthstarTheme.build(Brightness.light),
      darkTheme: NorthstarTheme.build(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index =
        (location.startsWith('/train/')
                ? 1
                : location.startsWith('/progress/')
                ? 2
                : _routes.indexOf(location))
            .clamp(0, 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 600;
        void select(int value) => context.go(_routes[value]);

        final body = SafeArea(
          // Compact: the floating nav overlays content; pages pad past it.
          bottom: expanded,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: child,
            ),
          ),
        );

        if (!expanded) {
          return Scaffold(
            extendBody: true,
            body: body,
            bottomNavigationBar: FloatingNavBar(
              selectedIndex: index,
              onSelected: select,
              destinations: _destinations,
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }
}
