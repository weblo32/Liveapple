import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:classora_mobile/features/liveclass/domain/class_participant.dart';
import 'package:classora_mobile/features/liveclass/presentation/live_class_room_controller.dart';
import 'package:classora_mobile/core/theme/app_colors.dart';

Widget buildTestTile(ClassParticipant p, LiveClassRoomState roomState) {
  return MaterialApp(
    home: Scaffold(
      body: Container(
        width: 120,
        height: 120,
        color: const Color(0xFF1E293B),
        child: Stack(
          children: [
            Center(
              child: Text(p.name, style: const TextStyle(color: Colors.white)),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                  Icon(
                    p.isRealMicMuted ? Icons.mic_off : Icons.mic,
                    color: p.isRealMicMuted ? AppColors.error : AppColors.success,
                    size: 11,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('BUG A - Participant Microphone Icon and State Updates', () {
    test('Derived real mic state strictly reflects publication state', () {
      // 1. Initial remote participant with no publication yet -> treated as muted
      var student = ClassParticipant(
        identity: 'student_1',
        name: 'Rahul Sharma',
        role: 'STUDENT',
        isLocal: false,
        micPubPresent: false,
        micPubMuted: true,
      );
      expect(student.isRealMicMuted, true);

      // 2. Publication published and unmuted
      student = student.copyWith(
        micPubPresent: true,
        micPubMuted: false,
        micPubSubscribed: true,
      );
      expect(student.isRealMicMuted, false);

      // 3. TrackMutedEvent occurs -> publication muted
      student = student.copyWith(
        micPubMuted: true,
      );
      expect(student.isRealMicMuted, true);

      // 4. TrackUnmutedEvent occurs -> publication unmuted
      student = student.copyWith(
        micPubMuted: false,
      );
      expect(student.isRealMicMuted, false);
    });

    testWidgets('Tile icon transitions correctly: muted -> unmuted -> muted', (tester) async {
      final roomState = LiveClassRoomState();

      // State 1: Muted
      var student = ClassParticipant(
        identity: 'student_1',
        name: 'Rahul',
        isLocal: false,
        micPubPresent: true,
        micPubMuted: true,
      );

      await tester.pumpWidget(buildTestTile(student, roomState));
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);

      // State 2: Unmuted
      student = student.copyWith(micPubMuted: false);
      await tester.pumpWidget(buildTestTile(student, roomState));
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsNothing);

      // State 3: Muted again
      student = student.copyWith(micPubMuted: true);
      await tester.pumpWidget(buildTestTile(student, roomState));
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('After teacher mute-all, when student unmutes, icon shows unmuted', (tester) async {
      // Teacher executes muteAll which sets room micLock
      var roomState = LiveClassRoomState(isMicLocked: true);

      // Student is initially muted
      var student = ClassParticipant(
        identity: 'student_1',
        name: 'Priya',
        isLocal: false,
        micPubPresent: true,
        micPubMuted: true,
      );

      await tester.pumpWidget(buildTestTile(student, roomState));
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);

      // Student subsequently unmutes their mic publication in LiveKit
      student = student.copyWith(micPubMuted: false);

      await tester.pumpWidget(buildTestTile(student, roomState));
      // Derived icon must show unmuted because the real audio publication is enabled!
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsNothing);
      expect(student.isRealMicMuted, false);
    });
  });
}
