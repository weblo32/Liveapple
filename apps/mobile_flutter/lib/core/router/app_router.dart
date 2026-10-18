import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/accept_invite_screen.dart';
import '../../features/admin/presentation/admin_home_screen.dart';
import '../../features/teacher/presentation/teacher_home_screen.dart';
import '../../features/student/presentation/student_home_screen.dart';
import '../../features/liveclass/presentation/live_classroom_screen.dart';
import '../../features/learning/presentation/screens/recordings_screen.dart';
import '../../features/learning/presentation/screens/assignments_screen.dart';
import '../../features/learning/presentation/screens/study_material_screen.dart';
import '../../features/learning/presentation/screens/cbt_tests_screen.dart';
import '../../features/learning/presentation/screens/fees_screen.dart';
import '../../features/learning/presentation/screens/attendance_screen.dart';
import '../../features/auth/presentation/edit_profile_screen.dart';
import '../../features/help/presentation/help_walkthrough_screen.dart';
import '../../features/institute/presentation/manage_institute_content_screen.dart';
import '../../features/learning/presentation/screens/test_result_screen.dart';
import '../../features/store/presentation/screens/course_store_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/accept-invite',
        builder: (context, state) => const AcceptInviteScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => AdminHomeScreen(user: authState.user!),
      ),
      GoRoute(
        path: '/teacher',
        builder: (context, state) => TeacherHomeScreen(user: authState.user!),
      ),
      GoRoute(
        path: '/student',
        builder: (context, state) => StudentHomeScreen(user: authState.user!),
      ),
      GoRoute(
        path: '/live/:id',
        builder: (context, state) => LiveClassroomScreen(classId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/recordings',
        builder: (context, state) => const RecordingsScreen(),
      ),
      GoRoute(
        path: '/assignments',
        builder: (context, state) => AssignmentsScreen(isTeacher: authState.user?.role == 'TEACHER'),
      ),
      GoRoute(
        path: '/study-material',
        builder: (context, state) => StudyMaterialScreen(isTeacher: authState.user?.role == 'TEACHER'),
      ),
      GoRoute(
        path: '/tests',
        builder: (context, state) => const CbtTestsScreen(),
      ),
      GoRoute(
        path: '/fees',
        builder: (context, state) => const FeesScreen(),
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) => const AttendanceScreen(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => EditProfileScreen(user: authState.user!),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => HelpWalkthroughScreen(
          initialRole: state.uri.queryParameters['role'] ?? authState.user?.role ?? 'STUDENT',
          user: authState.user,
          openTourImmediately: state.uri.queryParameters['tour'] == 'true',
        ),
      ),
      GoRoute(
        path: '/institute-content',
        builder: (context, state) => const ManageInstituteContentScreen(),
      ),
      GoRoute(
        path: '/test-result',
        builder: (context, state) {
          final attemptId = state.uri.queryParameters['attemptId'] ?? '';
          final code = state.uri.queryParameters['code'];
          return TestResultScreen(attemptId: attemptId, code: code);
        },
      ),
      GoRoute(
        path: '/store',
        builder: (context, state) => const CourseStoreScreen(),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      final status = authState.status;
      final location = state.matchedLocation;

      // 1. Initial / Loading -> Stay on splash
      if (status == AuthStatus.initial || status == AuthStatus.loading) {
        return location == '/splash' ? null : '/splash';
      }

      // 2. Unauthenticated -> Go to login, accept-invite, or test-result
      if (status == AuthStatus.unauthenticated || status == AuthStatus.error) {
        if (location == '/login' || location == '/accept-invite' || location == '/test-result') {
          return null;
        }
        return '/login';
      }

      // 3. Authenticated -> Route based on role
      if (status == AuthStatus.authenticated && authState.user != null) {
        final role = authState.user!.role;
        final targetHome = role == 'ADMIN'
            ? '/admin'
            : role == 'TEACHER'
                ? '/teacher'
                : '/student';

        // If on splash, login, or accept-invite, redirect to role home
        if (location == '/splash' || location == '/login' || location == '/accept-invite') {
          return targetHome;
        }

        // Role protection: prevent students from going to /admin, etc.
        if (location == '/admin' && role != 'ADMIN') return targetHome;
        if (location == '/teacher' && role != 'TEACHER') return targetHome;
        if (location == '/student' && role != 'STUDENT') return targetHome;

        return null;
      }

      return null;
    },
  );
});
