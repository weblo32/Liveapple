import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:classora_mobile/features/liveclass/presentation/live_class_room_controller.dart';
import 'package:classora_mobile/features/liveclass/domain/class_participant.dart';
import 'package:classora_mobile/core/theme/app_colors.dart';

Widget buildTestControlsBar({
  required bool isHost,
  required double screenWidth,
  bool isMicLocked = false,
  bool isHandRaised = false,
}) {
  final roomState = LiveClassRoomState(
    isHost: isHost,
    isMicLocked: isMicLocked,
    isHandRaised: isHandRaised,
    participants: [
      ClassParticipant(identity: 'u1', name: 'User 1', isLocal: true),
      ClassParticipant(identity: 'u2', name: 'User 2', isLocal: false),
    ],
  );

  Widget buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    Color? color,
    Color? backgroundColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: backgroundColor ?? (isActive ? AppColors.primary : AppColors.slate800),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 16),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: color ?? AppColors.slate400,
              fontSize: 9,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: screenWidth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildControlButton(
                    icon: roomState.isMicMuted ? Icons.mic_off : Icons.mic,
                    label: roomState.isMicMuted ? 'Unmute' : 'Mute',
                    isActive: !roomState.isMicMuted,
                    onTap: () {},
                  ),
                  buildControlButton(
                    icon: roomState.isCameraOff ? Icons.videocam_off : Icons.videocam,
                    label: roomState.isCameraOff ? 'Start Video' : 'Stop Video',
                    isActive: !roomState.isCameraOff,
                    onTap: () {},
                  ),
                  if (roomState.isHost)
                    buildControlButton(
                      icon: Icons.present_to_all,
                      label: 'Present',
                      isActive: false,
                      onTap: () {},
                    )
                  else
                    buildControlButton(
                      icon: roomState.isHandRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
                      label: roomState.isHandRaised ? 'Lower Hand' : 'Raise Hand',
                      isActive: roomState.isHandRaised,
                      onTap: () {},
                    ),
                  buildControlButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    isActive: false,
                    onTap: () {},
                  ),
                  buildControlButton(
                    icon: Icons.people_outline,
                    label: 'People (${roomState.participants.length})',
                    isActive: false,
                    onTap: () {},
                  ),
                  buildControlButton(
                    icon: Icons.more_horiz,
                    label: 'More',
                    isActive: false,
                    onTap: () {},
                  ),
                  buildControlButton(
                    icon: Icons.call_end,
                    label: roomState.isHost ? 'End Class' : 'Leave',
                    isActive: true,
                    backgroundColor: AppColors.liveRed,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildTestDesktopLayout({required double width, required double height}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            // Stage (left ~70%)
            Expanded(
              flex: 7,
              child: Container(
                color: const Color(0xFF0F172A),
                child: const Column(
                  children: [
                    Text('Stage Area', style: TextStyle(color: Colors.white)),
                    Expanded(child: Center(child: Text('Video Grid', style: TextStyle(color: Colors.white)))),
                    Text('Centered Controls Bar', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
            // Right Sidebar (360dp)
            SizedBox(
              width: 360,
              child: Container(
                color: const Color(0xFF1E293B),
                child: const Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Chat', style: TextStyle(color: Colors.white))),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('People', style: TextStyle(color: Colors.white))),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Hands', style: TextStyle(color: Colors.white))),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Polls', style: TextStyle(color: Colors.white))),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Doubts', style: TextStyle(color: Colors.white))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('Part 1 Item 3: Controls Bar Layout and Zero Clipping Tests', () {
    testWidgets('Teacher controls bar fits 320 dp without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestControlsBar(isHost: true, screenWidth: 320));
      expect(tester.takeException(), isNull, reason: 'Must not produce layout overflow at 320 dp');

      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Start Video'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('People (2)'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('End Class'), findsOneWidget);

      // Verify NO Record button
      expect(find.text('Record'), findsNothing);
    });

    testWidgets('Student controls bar fits 320 dp without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestControlsBar(isHost: false, screenWidth: 320));
      expect(tester.takeException(), isNull, reason: 'Must not produce layout overflow at 320 dp');

      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Start Video'), findsOneWidget);
      expect(find.text('Raise Hand'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('People (2)'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);

      // Verify NO Record button
      expect(find.text('Record'), findsNothing);
    });

    testWidgets('Controls bar fits 360 dp without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestControlsBar(isHost: true, screenWidth: 360));
      expect(tester.takeException(), isNull);
    });
  });

  group('Part 1 Item 5: Desktop Layout Tests (>=900px)', () {
    testWidgets('Desktop layout at 1280x720 renders stage and 360px sidebar with 5 tabs', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestDesktopLayout(width: 1280, height: 720));
      expect(tester.takeException(), isNull);

      expect(find.text('Stage Area'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Hands'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);
      expect(find.text('Doubts'), findsOneWidget);
    });

    testWidgets('Desktop layout at 1024x768 renders stage and 360px sidebar with 5 tabs', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestDesktopLayout(width: 1024, height: 768));
      expect(tester.takeException(), isNull);

      expect(find.text('Stage Area'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Hands'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);
      expect(find.text('Doubts'), findsOneWidget);
    });
  });
}
