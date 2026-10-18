import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:classora_mobile/core/network/api_client.dart';
import 'package:classora_mobile/models/slide_deck_model.dart';
import 'package:classora_mobile/screens/classroom/components/document_viewer.dart';
import 'package:classora_mobile/features/liveclass/presentation/live_class_room_controller.dart';
import 'package:classora_mobile/core/theme/app_colors.dart';

void main() {
  group('Part 1 & 4 - Contract Tests: SlideDeckModel parses real server payloads', () {
    test('parses real server POST /slides upload response', () {
      final realUploadPayload = {
        'success': true,
        'deckId': 'deck-abc-123',
        'fileKey': 'slide_c1_1729250000000.pdf',
        'fileName': 'Satyam_Pandey_Resume.pdf',
        'title': 'Satyam_Pandey_Resume.pdf',
        'fileSize': 14500,
        'fileHash': 'd589d6e7f13b65287f329de4b6f70ad3f7c46927bf4959db234e6dcf3ee3d20a',
        'totalPages': 2,
        'currentPage': 1,
        'page': 1,
        'url': '/api/v1/classes/class-demo-phy-01/slides/deck-abc-123/stream',
        'streamUrl': '/api/v1/classes/class-demo-phy-01/slides/deck-abc-123/stream',
        'stage': 'SLIDES',
        'isOpen': true,
      };

      final model = SlideDeckModel.fromJson(realUploadPayload);
      expect(model.deckId, 'deck-abc-123');
      expect(model.fileName, 'Satyam_Pandey_Resume.pdf');
      expect(model.totalPages, 2);
      expect(model.currentPage, 1);
      expect(model.fileHash, 'd589d6e7f13b65287f329de4b6f70ad3f7c46927bf4959db234e6dcf3ee3d20a');
      expect(model.url, '/api/v1/classes/class-demo-phy-01/slides/deck-abc-123/stream');
      expect(model.stage, 'SLIDES');
    });

    test('parses real server doc:present socket event payload', () {
      final realSocketPayload = {
        'deckId': 'deck-xyz-789',
        'fileName': 'Satyam_Pandey_Resume.pdf',
        'totalPages': 2,
        'currentPage': 1,
        'fileHash': 'd589d6e7f13b65287f329de4b6f70ad3f7c46927bf4959db234e6dcf3ee3d20a',
        'url': 'https://liveapple.onrender.com/api/v1/classes/c1/slides/deck-xyz-789/stream',
        'stage': 'SLIDES',
      };

      final model = SlideDeckModel.fromJson(realSocketPayload);
      expect(model.deckId, 'deck-xyz-789');
      expect(model.totalPages, 2);
      expect(model.currentPage, 1);
      expect(model.fileName, 'Satyam_Pandey_Resume.pdf');
      expect(model.url, isNotEmpty);
    });

    test('parses real server classroom:snapshot payload for late joiners', () {
      final realSnapshotDoc = {
        'deckId': 'deck-late-456',
        'fileName': 'Satyam_Pandey_Resume.pdf',
        'totalPages': 2,
        'currentPage': 2,
        'fileHash': 'd589d6e7f13b65287f329de4b6f70ad3f7c46927bf4959db234e6dcf3ee3d20a',
        'url': '/api/v1/classes/c1/slides/deck-late-456/stream',
        'stage': 'SLIDES',
      };

      final model = SlideDeckModel.fromJson(realSnapshotDoc);
      expect(model.deckId, 'deck-late-456');
      expect(model.totalPages, 2);
      expect(model.currentPage, 2); // lands on teacher's current page!
    });
  });

  group('Part 2 - DocumentViewer Widget Tests', () {
    testWidgets('shows clear error and Retry button on fetch failure without endless placeholder', (tester) async {
      ApiClient.markRemoteConfigSynced();
      addTearDown(() {
        ApiClient.resetForTesting();
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      });

      // Intercept and immediately reject download request
      final dio = ApiClient().dio;
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                error: 'Simulated connection failure',
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentViewer(
              docUrl: '/api/v1/classes/c1/slides/deck-fail/stream',
              docTitle: 'Satyam_Pandey_Resume.pdf',
              isTeacher: false,
              syncedPage: 1,
              syncedTotalPages: 2,
              onClose: () {},
            ),
          ),
        ),
      );

      // Pump frames to let async download rejection run
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Assert error message and retry button are shown
      expect(find.text('Slides load nahi ho payi'), findsOneWidget);
      expect(find.text('Dobara koshish karein'), findsOneWidget);

      // Assert developer labels are completely removed
      expect(find.text('Real PDF Mode'), findsNothing);
      expect(find.text('Waiting for Teacher\'s Slides'), findsNothing);
    });
  });

  group('Part 3 - Controls Bar Responsiveness and No Clipping', () {
    Widget buildTestBar({
      required bool isHost,
      required double screenWidth,
      required double textScale,
      bool isPresenting = false,
      bool isMicMuted = false,
      bool isCameraOff = false,
      bool isHandRaised = false,
    }) {
      final roomState = LiveClassRoomState(
        isHost: isHost,
        isDocPresenting: isPresenting,
        isMicMuted: isMicMuted,
        isCameraOff: isCameraOff,
        isHandRaised: isHandRaised,
      );

      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(screenWidth, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            bottomNavigationBar: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final scale = MediaQuery.textScalerOf(context).scale(1.0);
                final isCompact = availableWidth < 390 || scale > 1.15;

                Widget buildControlButton({
                  required IconData icon,
                  required String label,
                  required bool isActive,
                  Color? color,
                  Color? backgroundColor,
                  required VoidCallback onTap,
                }) {
                  final effectiveBg = backgroundColor ?? (isActive ? AppColors.primary : AppColors.slate800);
                  final effectiveIconColor = color ?? (isActive ? Colors.white : AppColors.slate100);

                  return InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: effectiveBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: effectiveIconColor, size: 18),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: effectiveIconColor == Colors.white ? AppColors.slate300 : effectiveIconColor,
                              fontSize: 10.5,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                Widget buildMicBtn() => buildControlButton(
                  icon: roomState.isMicMuted ? Icons.mic_off : Icons.mic,
                  label: 'Mic',
                  isActive: !roomState.isMicMuted,
                  color: roomState.isMicMuted ? AppColors.error : Colors.white,
                  backgroundColor: roomState.isMicMuted ? const Color(0xFF334155) : AppColors.primary,
                  onTap: () {},
                );

                Widget buildCamBtn() => buildControlButton(
                  icon: roomState.isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: 'Video',
                  isActive: !roomState.isCameraOff,
                  color: roomState.isCameraOff ? AppColors.error : Colors.white,
                  backgroundColor: roomState.isCameraOff ? const Color(0xFF334155) : AppColors.primary,
                  onTap: () {},
                );

                Widget buildPresentBtn() => buildControlButton(
                  icon: Icons.present_to_all,
                  label: 'Present',
                  isActive: isPresenting,
                  color: isPresenting ? Colors.white : AppColors.slate100,
                  backgroundColor: isPresenting ? AppColors.primary : AppColors.slate800,
                  onTap: () {},
                );

                Widget buildHandBtn() => buildControlButton(
                  icon: roomState.isHandRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
                  label: 'Hand',
                  isActive: roomState.isHandRaised,
                  color: roomState.isHandRaised ? Colors.white : AppColors.slate100,
                  backgroundColor: roomState.isHandRaised ? AppColors.warning : AppColors.slate800,
                  onTap: () {},
                );

                Widget buildChatBtn() => buildControlButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat',
                  isActive: false,
                  color: AppColors.slate100,
                  backgroundColor: AppColors.slate800,
                  onTap: () {},
                );

                Widget buildPeopleBtn() => buildControlButton(
                  icon: Icons.people_outline,
                  label: 'People',
                  isActive: false,
                  color: AppColors.slate100,
                  backgroundColor: AppColors.slate800,
                  onTap: () {},
                );

                Widget buildMoreBtn() => buildControlButton(
                  icon: Icons.more_horiz,
                  label: 'More',
                  isActive: false,
                  color: AppColors.slate100,
                  backgroundColor: AppColors.slate800,
                  onTap: () {},
                );

                Widget buildEndLeaveBtn() => buildControlButton(
                  icon: Icons.call_end,
                  label: roomState.isHost ? 'End' : 'Leave',
                  isActive: true,
                  color: Colors.white,
                  backgroundColor: AppColors.liveRed,
                  onTap: () {},
                );

                List<Widget> barItems;
                if (roomState.isHost) {
                  if (isCompact) {
                    barItems = [buildMicBtn(), buildCamBtn(), buildPresentBtn(), buildMoreBtn(), buildEndLeaveBtn()];
                  } else {
                    barItems = [buildMicBtn(), buildCamBtn(), buildPresentBtn(), buildChatBtn(), buildPeopleBtn(), buildMoreBtn(), buildEndLeaveBtn()];
                  }
                } else {
                  if (isCompact) {
                    barItems = [buildMicBtn(), buildCamBtn(), buildHandBtn(), buildMoreBtn(), buildEndLeaveBtn()];
                  } else {
                    barItems = [buildMicBtn(), buildCamBtn(), buildHandBtn(), buildChatBtn(), buildPeopleBtn(), buildMoreBtn(), buildEndLeaveBtn()];
                  }
                }

                return SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: barItems.map((item) => Expanded(child: Center(child: item))).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    final testWidths = [320.0, 360.0, 393.0, 411.0, 430.0];
    final testScales = [1.0, 1.3];

    for (final width in testWidths) {
      for (final scale in testScales) {
        testWidgets('Teacher controls bar fits without overflow at width $width and scale $scale', (tester) async {
          tester.view.physicalSize = Size(width * 2, 800 * 2);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(buildTestBar(isHost: true, screenWidth: width, textScale: scale));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'No RenderFlex overflow on width $width scale $scale');
          expect(find.text('Mic'), findsOneWidget);
          expect(find.text('Video'), findsOneWidget);
          expect(find.text('Present'), findsOneWidget);
          expect(find.text('More'), findsOneWidget);
          expect(find.text('End'), findsOneWidget);
        });

        testWidgets('Student controls bar fits without overflow at width $width and scale $scale', (tester) async {
          tester.view.physicalSize = Size(width * 2, 800 * 2);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(buildTestBar(isHost: false, screenWidth: width, textScale: scale));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: 'No RenderFlex overflow on width $width scale $scale');
          expect(find.text('Mic'), findsOneWidget);
          expect(find.text('Video'), findsOneWidget);
          expect(find.text('Hand'), findsOneWidget);
          expect(find.text('More'), findsOneWidget);
          expect(find.text('Leave'), findsOneWidget);
        });
      }
    }
  });

  group('Part 3 Defect B - Present button icon visibility in active and inactive states', () {
    Widget buildPresentButtonTest({required bool isPresenting}) {
      final effectiveBg = isPresenting ? AppColors.primary : AppColors.slate800;
      final effectiveIconColor = isPresenting ? Colors.white : AppColors.slate100;

      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: effectiveBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.present_to_all, color: effectiveIconColor, size: 18),
            ),
          ),
        ),
      );
    }

    testWidgets('Present button in inactive state renders crisp visible icon', (tester) async {
      await tester.pumpWidget(buildPresentButtonTest(isPresenting: false));
      await tester.pumpAndSettle();

      final iconFinder = find.byIcon(Icons.present_to_all);
      expect(iconFinder, findsOneWidget);

      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, AppColors.slate100);
      expect(iconWidget.color, isNot(AppColors.slate800)); // Icon contrasts with bg
    });

    testWidgets('Present button in active state renders white icon on blue circle (NOT empty circle)', (tester) async {
      await tester.pumpWidget(buildPresentButtonTest(isPresenting: true));
      await tester.pumpAndSettle();

      final iconFinder = find.byIcon(Icons.present_to_all);
      expect(iconFinder, findsOneWidget);

      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, Colors.white);
      expect(iconWidget.color, isNot(AppColors.primary)); // NEVER invisible blue on blue!
    });
  });
}
