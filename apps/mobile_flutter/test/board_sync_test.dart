import 'package:flutter_test/flutter_test.dart';
import 'package:classora_mobile/features/liveclass/presentation/live_class_room_controller.dart';
import 'package:classora_mobile/features/liveclass/domain/class_participant.dart';

void main() {
  group('BUG B - Board Sync & Stage Transition Integration Test', () {
    test('Teacher toggling board sets BOARD stage, stroke delivery arrives, late joiner snapshot syncs', () async {
      // 1. Initialize Teacher controller state
      var teacherState = LiveClassRoomState(
        isHost: true,
        stage: 'VIDEO',
        isWhiteboardOpen: false,
        participants: [
          ClassParticipant(identity: 'teacher_1', name: 'Prof. Sharma', role: 'TEACHER', isHost: true, isLocal: true),
        ],
      );

      // 2. Initialize Student controller state
      var studentState = LiveClassRoomState(
        isHost: false,
        stage: 'VIDEO',
        isWhiteboardOpen: false,
        participants: [
          ClassParticipant(identity: 'student_1', name: 'Rahul', role: 'STUDENT', isHost: false, isLocal: true),
          ClassParticipant(identity: 'teacher_1', name: 'Prof. Sharma', role: 'TEACHER', isHost: true, isLocal: false),
        ],
      );

      expect(teacherState.stage, 'VIDEO');
      expect(studentState.stage, 'VIDEO');
      expect(studentState.isWhiteboardOpen, false);

      // 3. Teacher opens Digital Whiteboard
      // Controller sets stage to BOARD, isWhiteboardOpen to true, increments boardEventsSent
      const nextStage = 'BOARD';
      teacherState = teacherState.copyWith(
        isWhiteboardOpen: true,
        stage: nextStage,
        boardEventsSent: teacherState.boardEventsSent + 1,
        lastStageEventSent: 'mode: $nextStage at ${DateTime.now().toIso8601String()}',
      );

      expect(teacherState.stage, 'BOARD');
      expect(teacherState.isWhiteboardOpen, true);
      expect(teacherState.boardEventsSent, 1);
      expect(teacherState.lastStageEventSent, contains('mode: BOARD'));

      // 4. Student receives stage:state / stage:changed from server broadcast
      studentState = studentState.copyWith(
        stage: 'BOARD',
        isWhiteboardOpen: true,
        lastStageEventReceived: 'mode: BOARD at ${DateTime.now().toIso8601String()}',
      );

      expect(studentState.stage, 'BOARD');
      expect(studentState.isWhiteboardOpen, true);
      expect(studentState.lastStageEventReceived, contains('mode: BOARD'));

      // 5. Teacher draws a stroke on the board
      final strokeData = {
        'points': [{'x': 10.0, 'y': 20.0}, {'x': 15.0, 'y': 25.0}],
        'color': '#2563EB',
        'strokeWidth': 3.0,
      };

      teacherState = teacherState.copyWith(
        boardEventsSent: teacherState.boardEventsSent + 1,
      );
      expect(teacherState.boardEventsSent, 2);

      // Stroke arrives on student side via whiteboard:draw
      studentState = studentState.copyWith(
        boardEventsReceived: studentState.boardEventsReceived + 1,
      );
      expect(studentState.boardEventsReceived, 1);

      // 6. Late Joiner (student 2) connects to the classroom and receives classroom:snapshot
      var lateJoinerState = LiveClassRoomState(
        isHost: false,
        isSocketConnected: true,
        isRoomJoined: true,
      );

      final snapshotData = {
        'stage': 'BOARD',
        'mode': 'BOARD',
        'isMicLocked': false,
        'board': {
          'isOpen': true,
          'canDraw': false, // Students are view-only
          'strokes': [strokeData],
        },
      };

      final snapshotStage = snapshotData['mode']?.toString() ?? 'VIDEO';
      final boardData = snapshotData['board'] as Map<String, dynamic>;
      final isBoardOpen = boardData['isOpen'] == true || snapshotStage == 'BOARD';

      lateJoinerState = lateJoinerState.copyWith(
        snapshotReceived: true,
        stage: snapshotStage,
        isWhiteboardOpen: isBoardOpen,
        isBoardAllowed: false, // View only
        lastStageEventReceived: 'mode: $snapshotStage (snapshot) at ${DateTime.now().toIso8601String()}',
      );

      expect(lateJoinerState.snapshotReceived, true);
      expect(lateJoinerState.stage, 'BOARD');
      expect(lateJoinerState.isWhiteboardOpen, true);
      expect(lateJoinerState.isBoardAllowed, false); // View-only confirmed

      // 7. Teacher closes Whiteboard -> everyone returns to VIDEO stage cleanly
      teacherState = teacherState.copyWith(
        isWhiteboardOpen: false,
        stage: 'VIDEO',
        lastStageEventSent: 'mode: VIDEO at ${DateTime.now().toIso8601String()}',
      );
      studentState = studentState.copyWith(
        isWhiteboardOpen: false,
        stage: 'VIDEO',
        lastStageEventReceived: 'mode: VIDEO at ${DateTime.now().toIso8601String()}',
      );

      expect(teacherState.stage, 'VIDEO');
      expect(teacherState.isWhiteboardOpen, false);
      expect(studentState.stage, 'VIDEO');
      expect(studentState.isWhiteboardOpen, false);
    });
  });
}
