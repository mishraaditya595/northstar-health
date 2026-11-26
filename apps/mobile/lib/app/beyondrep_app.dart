import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/beyondrep_theme.dart';
import '../features/health/detail/activity_detail_page.dart';
import '../features/health/detail/body_detail_page.dart';
import '../features/health/detail/health_terms_page.dart';
import '../features/health/detail/heart_detail_page.dart';
import '../features/health/detail/readiness_detail_page.dart';
import '../features/health/detail/sleep_detail_page.dart';
import '../features/health/health_page.dart';
import '../features/account/account_sync_page.dart';
import '../features/sync/workout_conflict_review_page.dart';
import '../features/progress/progress_page.dart';
import '../features/progress/outside_workout_detail_page.dart';
import '../features/progress/workout_history_detail_page.dart';
import '../features/today/today_page.dart';
import '../features/train/train_page.dart';
import '../features/train/exercise_catalog_page.dart';
import '../features/train/template_detail_page.dart';
import '../features/train/my_program_page.dart';
import '../features/train/program_detail_page.dart';
import '../features/train/programs_page.dart';
import '../features/train/workout_templates_page.dart';
import '../features/train/exercise_detail_page.dart';
import '../features/train/plan_editor_page.dart';
import '../features/train/active_workout_page.dart';
import 'floating_nav_bar.dart';
import 'theme_controller.dart';

final _routes = <String>['/today', '/train', '/progress', '/health'];
final _destinations = <NavigationDestination>[
  const NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
    label: 'Today',
  ),
  const NavigationDestination(
    icon: Icon(Icons.contrast),
    selectedIcon: Icon(Icons.contrast),
    label: 'Train',
  ),
  const NavigationDestination(
    icon: Icon(Icons.north_east),
    selectedIcon: Icon(Icons.north_east),
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
            path: '/today/sync/review',
            builder: (_, _) => const WorkoutConflictReviewPage(),
          ),
          GoRoute(
            path: '/today/account',
            builder: (_, _) => const AccountSyncPage(),
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
            path: '/train/workouts',
            builder: (_, _) => const WorkoutTemplatesPage(),
          ),
          GoRoute(
            path: '/train/workouts/:id',
            builder: (_, state) =>
                TemplateDetailPage(templateId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/train/programs',
            builder: (_, _) => const ProgramsPage(),
          ),
          GoRoute(
            path: '/train/programs/:id',
            builder: (_, state) =>
                ProgramDetailPage(programId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/train/program/:uuid',
            builder: (_, state) =>
                MyProgramPage(programUuid: state.pathParameters['uuid']!),
          ),
          GoRoute(
            path: '/train/exercises',
            builder: (_, _) => const ExerciseCatalogPage(),
          ),
          GoRoute(
            path: '/train/exercises/:id',
            builder: (_, state) =>
                ExerciseDetailPage(exerciseId: state.pathParameters['id']!),
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
            path: '/progress/health-workouts/:id',
            builder: (_, state) => OutsideWorkoutDetailPage(
              workoutId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/health',
            pageBuilder: (_, state) => _tabPage(state, const HealthPage()),
          ),
          GoRoute(
            path: '/health/readiness',
            builder: (_, _) => const ReadinessDetailPage(),
          ),
          GoRoute(
            path: '/health/sleep',
            builder: (_, _) => const SleepDetailPage(),
          ),
          GoRoute(
            path: '/health/heart',
            builder: (_, _) => const HeartDetailPage(),
          ),
          GoRoute(
            path: '/health/activity',
            builder: (_, _) => const ActivityDetailPage(),
          ),
          GoRoute(
            path: '/health/body',
            builder: (_, _) => const BodyDetailPage(),
          ),
          GoRoute(
            path: '/health/terms',
            builder: (_, _) => const HealthTermsPage(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class BeyondRepApp extends ConsumerWidget {
  const BeyondRepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: 'BeyondRep',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: BeyondRepTheme.build(Brightness.light),
      darkTheme: BeyondRepTheme.build(Brightness.dark),
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
                : location.startsWith('/health/')
                ? 3
                : _routes.indexOf(location))
            .clamp(0, 3);
    // The live workout is a focus screen: no tab bar or rail.
    final focus = location == '/train/workout';
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 600;
        void select(int value) => context.go(_routes[value]);

        final body = SafeArea(
          // Compact: the floating nav overlays content; pages pad past it.
          bottom: expanded || focus,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: child,
            ),
          ),
        );

        if (focus) return Scaffold(body: body);

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
