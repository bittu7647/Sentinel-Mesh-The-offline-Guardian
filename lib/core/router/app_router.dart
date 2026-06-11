import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/home_screen.dart';
import '../../features/sender/sender_mode_screen.dart';
import '../../features/responder/responder_radar_screen.dart';
// Note: Placeholder imports for remaining screens
import '../../features/police/police_support_screen.dart';
import '../../features/medical/medical_support_screen.dart';
import '../../features/chatbot/safety_ai_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/sender',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const SenderModeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: animation.drive(
                Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/radar',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const ResponderRadarScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: animation.drive(
                Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
        ),
      ),
      GoRoute(
        path: '/police',
        builder: (context, state) => const PoliceSupportScreen(),
      ),
      GoRoute(
        path: '/medical',
        builder: (context, state) => const MedicalSupportScreen(),
      ),
      GoRoute(
        path: '/chatbot',
        builder: (context, state) => const SafetyAIScreen(),
      ),
    ],
  );
}
