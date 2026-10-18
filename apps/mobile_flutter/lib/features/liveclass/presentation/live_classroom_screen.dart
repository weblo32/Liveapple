import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/live_class_model.dart';
import '../domain/class_participant.dart';
import 'live_class_controller.dart';
import 'live_class_room_controller.dart';
import '../../../screens/classroom/components/digital_board.dart';
import '../../../screens/classroom/components/document_viewer.dart';
import '../../../core/services/pip_service.dart';

const bool kEnableAndroidScreenShare = bool.fromEnvironment('ENABLE_ANDROID_SCREEN_SHARE', defaultValue: false);
const String kAppCommit = String.fromEnvironment('APP_COMMIT', defaultValue: 'unknown');

class LiveClassroomScreen extends ConsumerStatefulWidget {
  final String classId;

  const LiveClassroomScreen({super.key, required this.classId});

  @override
  ConsumerState<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends ConsumerState<LiveClassroomScreen> {
  final _chatTextController = TextEditingController();

  // Desktop Responsive State (Section 5)
  int _desktopSidebarTab = 0; // 0: Chat, 1: People, 2: Hands, 3: Polls, 4: Doubts
  bool _showDesktopSidebar = true;

  // Green Room / Pre-Join Lobby State (Zoom & Meet style)
  bool _isInLobby = true;
  bool _isLoadingLobby = true;
  LiveClassModel? _lobbyClass;
  bool _lobbyMicEnabled = false;
  bool _lobbyCameraEnabled = false;
  lk.LocalVideoTrack? _lobbyVideoTrack;

  // Real In-Class Session Elapsed Timer (Rule: zero fake timers)
  Timer? _sessionTimer;
  int _sessionSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initLobby();
  }

  Future<void> _initLobby() async {
    final user = ref.read(authStateProvider).user;
    final isTeacher = user?.role == 'TEACHER' || user?.role == 'ADMIN';
    _lobbyMicEnabled = isTeacher;
    _lobbyCameraEnabled = isTeacher;

    try {
      final repo = ref.read(liveClassRepositoryProvider);
      final cls = await repo.getClassById(widget.classId);
      if (mounted) {
        setState(() {
          _lobbyClass = cls;
          _isLoadingLobby = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingLobby = false;
        });
      }
    }

    if (_lobbyCameraEnabled) {
      _startLobbyCamera();
    }
  }

  Future<void> _startLobbyCamera() async {
    try {
      final track = await lk.LocalVideoTrack.createCameraTrack();
      if (mounted) {
        setState(() {
          _lobbyVideoTrack = track;
          _lobbyCameraEnabled = true;
        });
      }
    } catch (e) {
      debugPrint('[LOBBY] Camera start error: $e');
      if (mounted) {
        setState(() {
          _lobbyCameraEnabled = false;
        });
      }
    }
  }

  Future<void> _stopLobbyCamera() async {
    try {
      await _lobbyVideoTrack?.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _lobbyVideoTrack = null;
        _lobbyCameraEnabled = false;
      });
    }
  }

  void _toggleLobbyMic() {
    setState(() {
      _lobbyMicEnabled = !_lobbyMicEnabled;
    });
  }

  void _toggleLobbyCamera() {
    if (_lobbyCameraEnabled) {
      _stopLobbyCamera();
    } else {
      _startLobbyCamera();
    }
  }

  void _enterClassroom() {
    final user = ref.read(authStateProvider).user;
    setState(() {
      _isInLobby = false;
    });

    _startSessionTimer();

    ref.read(liveClassRoomProvider.notifier).joinRoom(
          widget.classId,
          currentUserId: user?.id,
          currentUserName: user?.name,
          currentUserRole: user?.role,
          initialMicMuted: !_lobbyMicEnabled,
          initialCameraOff: !_lobbyCameraEnabled,
          prewarmVideoTrack: _lobbyVideoTrack,
        );
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionSeconds = 0;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _sessionSeconds++;
        });
      }
    });
  }

  String _formatSessionTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _lobbyVideoTrack?.stop();
    _chatTextController.dispose();
    super.dispose();
  }

  Future<void> _handleLeaveOrEnd(bool isHost) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: isHost ? 'End Live Class?' : 'Leave Live Class?',
      message: isHost
          ? 'This will end the live class session for all students and participants.'
          : 'Are you sure you want to leave this live classroom session?',
      confirmText: isHost ? 'End Class' : 'Leave',
      cancelText: 'Cancel',
      isDestructive: true,
    );

    if (confirmed == true && mounted) {
      if (isHost) {
        await ref.read(liveClassRoomProvider.notifier).endClass();
      } else {
        ref.read(liveClassRoomProvider.notifier).leaveRoom();
      }
      if (mounted) context.pop();
    }
  }

  void _showChatDrawer() {
    final user = ref.read(authStateProvider).user;
    final userName = user?.name ?? 'User';
    final userRole = user?.role ?? 'STUDENT';
    ref.read(liveClassRoomProvider.notifier).markChatRead();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final roomState = ref.watch(liveClassRoomProvider);

            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'In-Class Discussion',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155)),
                  Expanded(
                    child: roomState.chatMessages.isEmpty
                        ? const Center(
                            child: Text(
                              'No messages yet. Ask doubt or message the class!',
                              style: TextStyle(color: AppColors.slate400, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: roomState.chatMessages.length,
                            itemBuilder: (context, idx) {
                              final msg = roomState.chatMessages[idx];
                              final isMe = msg.senderId == (user?.id ?? 'me');

                              if (msg.isSystem) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Center(
                                    child: Text(
                                      msg.text,
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 11,
                                        color: AppColors.slate400,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isMe ? AppColors.primary : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: Radius.circular(isMe ? 14 : 2),
                                      bottomRight: Radius.circular(isMe ? 2 : 14),
                                    ),
                                    border: isMe ? null : Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isMe ? 'You' : msg.senderName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: isMe ? Colors.white : AppColors.primaryLight,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: msg.senderRole == 'TEACHER'
                                                  ? AppColors.primaryLight.withValues(alpha: 0.2)
                                                  : AppColors.slate700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              msg.senderRole,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: isMe ? Colors.white : AppColors.slate400,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isMe ? Colors.white70 : AppColors.slate400,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        msg.text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatTextController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Type doubt or message...',
                            hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              ref.read(liveClassRoomProvider.notifier).sendChatMessage(
                                    val,
                                    userName,
                                    userRole,
                                  );
                              _chatTextController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed: () {
                          if (_chatTextController.text.trim().isNotEmpty) {
                            ref.read(liveClassRoomProvider.notifier).sendChatMessage(
                                  _chatTextController.text,
                                  userName,
                                  userRole,
                                );
                            _chatTextController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showParticipantsDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final roomState = ref.watch(liveClassRoomProvider);

            // Sort participants: Hand raised first, then host, then local, then alphabetical
            final sortedParticipants = List<ClassParticipant>.from(roomState.participants)
              ..sort((a, b) {
                if (a.isHandRaised != b.isHandRaised) {
                  return a.isHandRaised ? -1 : 1;
                }
                if (a.isHost != b.isHost) {
                  return a.isHost ? -1 : 1;
                }
                if (a.isLocal != b.isLocal) {
                  return a.isLocal ? -1 : 1;
                }
                return a.name.compareTo(b.name);
              });

            return Container(
              padding: const EdgeInsets.all(16),
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Participants (${roomState.participants.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      if (roomState.isHost)
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(liveClassRoomProvider.notifier).muteAll(lock: true);
                            _showToast(context, 'All student microphones muted and locked');
                          },
                          icon: const Icon(Icons.mic_off, size: 14),
                          label: const Text('Mute All', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155)),
                  Expanded(
                    child: sortedParticipants.isEmpty
                        ? const Center(
                            child: Text(
                              'No participants in classroom yet',
                              style: TextStyle(color: AppColors.slate400, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: sortedParticipants.length,
                            itemBuilder: (context, idx) {
                              final p = sortedParticipants[idx];

                              return ListTile(
                                dense: true,
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: p.isHost ? AppColors.primary : AppColors.slate700,
                                      child: Text(
                                        p.initials,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (p.isHandRaised)
                                      const Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: CircleAvatar(
                                          radius: 7,
                                          backgroundColor: AppColors.warning,
                                          child: Icon(Icons.pan_tool, size: 8, color: Colors.white),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        p.isLocal ? '${p.name} (You)' : p.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (p.isHost) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'HOST',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (p.isHandRaised) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppColors.warning, width: 0.5),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.pan_tool, size: 9, color: AppColors.warning),
                                            SizedBox(width: 3),
                                            Text(
                                              'Hand Raised',
                                              style: TextStyle(
                                                color: AppColors.warning,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (p.deviceCount > 1) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.slate700,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${p.deviceCount} devices',
                                          style: const TextStyle(color: AppColors.slate400, fontSize: 9),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      p.isMicMuted ? Icons.mic_off : Icons.mic,
                                      size: 16,
                                      color: p.isMicMuted ? AppColors.error : AppColors.success,
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      p.isCameraOff ? Icons.videocam_off : Icons.videocam,
                                      size: 16,
                                      color: p.isCameraOff ? AppColors.slate500 : AppColors.success,
                                    ),
                                    if (roomState.isHost && !p.isHost) ...[
                                      const SizedBox(width: 6),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white70),
                                        color: const Color(0xFF0F172A),
                                        onSelected: (action) {
                                          if (action == 'remove') {
                                            ref.read(liveClassRoomProvider.notifier).removeParticipant(p.identity);
                                            _showToast(context, 'Removed ${p.name} from class');
                                          } else if (action == 'muteMic') {
                                            ref.read(liveClassRoomProvider.notifier).muteStudentMic(p.identity);
                                            _showToast(context, 'Muted mic for ${p.name}');
                                          } else if (action == 'stopCam') {
                                            ref.read(liveClassRoomProvider.notifier).stopStudentCamera(p.identity);
                                            _showToast(context, 'Stopped camera for ${p.name}');
                                          } else if (action == 'allowSpeak') {
                                            ref.read(liveClassRoomProvider.notifier).allowStudentToSpeak(p.identity);
                                            _showToast(context, 'Granted speaking rights to ${p.name}');
                                          } else if (action == 'grantBoard') {
                                            ref.read(liveClassRoomProvider.notifier).grantBoardToStudent(p.identity);
                                            _showToast(context, 'Allowed ${p.name} to draw on board');
                                          } else if (action == 'revokeBoard') {
                                            ref.read(liveClassRoomProvider.notifier).revokeBoardFromStudent(p.identity);
                                            _showToast(context, 'Revoked board drawing from ${p.name}');
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'allowSpeak',
                                            child: Text('Allow Mic / Unmute', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'muteMic',
                                            child: Text('Mute Microphone', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'stopCam',
                                            child: Text('Stop Camera', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'grantBoard',
                                            child: Text('Allow Board Draw', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'revokeBoard',
                                            child: Text('Revoke Board Draw', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Remove from Class', style: TextStyle(color: AppColors.error, fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showToast(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 74, left: 16, right: 16),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF334155),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showPresentMenu(BuildContext context, LiveClassRoomState roomState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Present to Classroom',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.slate400),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155)),
              ListTile(
                leading: Icon(
                  Icons.draw_outlined,
                  color: roomState.isWhiteboardOpen ? AppColors.primary : Colors.white,
                ),
                title: Text(
                  roomState.isWhiteboardOpen ? 'Close Digital Whiteboard' : 'Open Digital Whiteboard',
                  style: TextStyle(
                    color: roomState.isWhiteboardOpen ? AppColors.primary : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  roomState.isWhiteboardOpen
                      ? 'Currently active on stage. Tap to return to video grid.'
                      : 'Draw formulas, diagrams, and notes with live sync to all students',
                  style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(liveClassRoomProvider.notifier).toggleWhiteboard();
                },
              ),
              if (kIsWeb || (defaultTargetPlatform == TargetPlatform.android && kEnableAndroidScreenShare))
                ListTile(
                  leading: Icon(
                    roomState.isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                    color: roomState.isScreenSharing ? AppColors.skyBlue : Colors.white,
                  ),
                  title: Text(
                    roomState.isScreenSharing ? 'Stop Screen Share' : 'Share Screen',
                    style: TextStyle(
                      color: roomState.isScreenSharing ? AppColors.skyBlue : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    roomState.isScreenSharing
                        ? 'Currently sharing your screen with class'
                        : 'Broadcast your screen to all students',
                    style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(liveClassRoomProvider.notifier).toggleScreenShare(
                          onError: (msg) => _showToast(context, msg),
                        );
                  },
                ),
              ListTile(
                leading: Icon(
                  roomState.isDocPresenting ? Icons.slideshow : Icons.picture_as_pdf_outlined,
                  color: roomState.isDocPresenting ? AppColors.primary : Colors.white,
                ),
                title: Text(
                  roomState.isDocPresenting ? 'Stop Notes / Slides' : 'Present Notes / PDF / PPT',
                  style: TextStyle(
                    color: roomState.isDocPresenting ? AppColors.primary : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  roomState.isDocPresenting
                      ? 'Currently presenting ${roomState.docTitle.isNotEmpty ? roomState.docTitle : 'Slides'}'
                      : 'Present lecture notes and synchronized PDF slides',
                  style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (roomState.isDocPresenting) {
                    ref.read(liveClassRoomProvider.notifier).setDocPresentation(isOpen: false);
                  } else {
                    await _pickAndPresentSlides();
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndPresentSlides() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'ppt', 'pptx'],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final nameLower = file.name.toLowerCase();
        if (nameLower.endsWith('.ppt') || nameLower.endsWith('.pptx')) {
          if (!mounted) return;
          _showToast(context, 'PPT ko PDF me export karo ya screen share karo');
          return;
        }

        if (file.path != null) {
          await ref.read(liveClassRoomProvider.notifier).uploadAndPresentSlides(
                fileName: file.name,
                filePath: file.path,
                fileBytes: file.bytes,
                onError: (msg) {
                  if (mounted) _showToast(context, msg);
                },
              );
        } else {
          ref.read(liveClassRoomProvider.notifier).setDocPresentation(
                isOpen: true,
                title: file.name,
                page: 1,
              );
        }
      }
    } catch (e) {
      debugPrint('[SLIDES] File picker note: $e');
    }
  }

  void _showDebugOverlay(BuildContext context, LiveClassRoomState roomState) {
    const appCommit = String.fromEnvironment('APP_COMMIT', defaultValue: 'dev');
    final isCommitMismatch = appCommit != 'dev' &&
        roomState.serverBuildCommit != null &&
        roomState.serverBuildCommit != 'Unknown' &&
        appCommit != roomState.serverBuildCommit;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live Classroom Diagnostics',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.slate400),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF334155)),
                if (isCommitMismatch)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'WARNING: App build ($appCommit) differs from server commit (${roomState.serverBuildCommit})',
                            style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildDebugRow('App Build ID (Git SHA)', appCommit),
                _buildDebugRow('Server Commit', roomState.serverBuildCommit ?? 'Unknown / Local'),
                _buildDebugRow('Server Built At', roomState.serverBuildTime ?? 'Unknown'),
                _buildDebugRow('Socket Connected', roomState.isSocketConnected ? 'YES' : 'NO'),
                _buildDebugRow('Class Room Joined', roomState.isRoomJoined ? 'YES' : 'NO'),
                _buildDebugRow('Snapshot Received', roomState.snapshotReceived ? 'YES' : 'NO'),
                _buildDebugRow('Class ID', roomState.liveClass?.id ?? widget.classId),
                _buildDebugRow('Role / Host', roomState.isHost ? 'TEACHER (Host)' : 'STUDENT'),
                _buildDebugRow('Connection State', roomState.connectionState),
                _buildDebugRow('Current Stage', roomState.stage),
                _buildDebugRow('Last Stage Event Sent', roomState.lastStageEventSent ?? 'None'),
                _buildDebugRow('Last Stage Event Received', roomState.lastStageEventReceived ?? 'None'),
                _buildDebugRow('Board Events (Sent / Received)', '${roomState.boardEventsSent} sent / ${roomState.boardEventsReceived} received'),
                _buildDebugRow('Mic Locked by Host', roomState.isMicLocked ? 'YES' : 'NO'),
                _buildDebugRow('Participants Count', '${roomState.participants.length}'),
                _buildDebugRow('Video Tracks Count', '${roomState.remoteVideoTracks.length}'),
                _buildDebugRow('Token Grants', '${roomState.tokenGrants ?? "None"}'),
                if (roomState.lastLiveKitError != null)
                  _buildDebugRow('Last LiveKit Error', roomState.lastLiveKitError!, isError: true),
                const SizedBox(height: 12),
                const Text(
                  'Slides Presentation Diagnostics:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                _buildDebugRow('Deck ID', roomState.slidesDeckId ?? (roomState.docUrl != null ? 'Active' : 'None')),
                _buildDebugRow('Deck Title', roomState.docTitle.isNotEmpty ? roomState.docTitle : 'None'),
                _buildDebugRow('Total Pages', '${roomState.docTotalPages}'),
                _buildDebugRow('Current Page', '${roomState.docPage}'),
                _buildDebugRow('Received Via', roomState.slidesReceiveSource ?? (roomState.snapshotReceived ? 'snapshot' : 'event')),
                _buildDebugRow('Fetch Status', roomState.slidesFetchStatus ?? (roomState.docUrl != null ? '200 OK' : 'Idle')),
                _buildDebugRow('Bytes / Pages Loaded', roomState.slidesBytesLoaded != null ? '${roomState.slidesBytesLoaded} bytes' : '${roomState.docPage} / ${roomState.docTotalPages} pages'),
                _buildDebugRow('Render Error', roomState.slidesRenderError ?? 'None', isError: roomState.slidesRenderError != null),
                _buildDebugRow('Server Commit', roomState.serverBuildCommit ?? 'Unknown / Local'),
                const SizedBox(height: 12),
                const Text(
                  'Remote Participants Media Details:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ...roomState.participants.where((p) => !p.isLocal).map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.name} (${p.identity}) • ${p.role}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mic Pub: present=${p.micPubPresent}, muted=${p.micPubMuted}, sub=${p.micPubSubscribed} (Effective: ${p.isRealMicMuted ? "MUTED" : "UNMUTED"})',
                        style: TextStyle(
                          color: p.isRealMicMuted ? AppColors.error : AppColors.success,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cam Pub: present=${p.camPubPresent}, muted=${p.camPubMuted}, sub=${p.camPubSubscribed} (Effective: ${p.isRealCameraOff ? "OFF" : "ON"})',
                        style: TextStyle(
                          color: p.isRealCameraOff ? AppColors.error : AppColors.success,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.slate400, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: isError ? AppColors.error : Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherPip(LiveClassRoomState roomState) {
    lk.VideoTrack? teacherTrack;
    if (roomState.isHost) {
      if (!roomState.isCameraOff && roomState.localVideoTrack != null) {
        teacherTrack = roomState.localVideoTrack;
      }
    } else {
      final hostP = roomState.participants.firstWhere(
        (p) => p.isHost || p.role == 'TEACHER',
        orElse: () => ClassParticipant(identity: '', name: '', role: ''),
      );
      if (hostP.identity.isNotEmpty && roomState.remoteVideoTracks.containsKey(hostP.identity)) {
        teacherTrack = roomState.remoteVideoTracks[hostP.identity];
      } else if (roomState.remoteVideoTracks.isNotEmpty) {
        teacherTrack = roomState.remoteVideoTracks.values.first;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (teacherTrack != null)
            Positioned.fill(
              child: lk.VideoTrackRenderer(
                teacherTrack,
                fit: lk.VideoViewFit.cover,
              ),
            )
          else
            const Center(
              child: Icon(Icons.person, color: AppColors.slate400, size: 36),
            ),
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                roomState.liveClass?.teacherName ?? 'Teacher',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreActionsSheet(LiveClassRoomState roomState, String userName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'More Options',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.slate400),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF334155)),
              if (roomState.isHost) ...[
                ListTile(
                  leading: const Icon(Icons.mic_off, color: AppColors.error),
                  title: const Text('Mute All Students', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Mute and lock microphones of all students', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(liveClassRoomProvider.notifier).muteAll(lock: true);
                    _showToast(context, 'All student microphones muted and locked');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: AppColors.success),
                  title: const Text('Unlock Student Mics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Allow students to unmute their microphones', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(liveClassRoomProvider.notifier).unlockMics();
                    _showToast(context, 'Student microphones unlocked');
                  },
                ),
                ListTile(
                  leading: Icon(
                    roomState.isRoomLocked ? Icons.lock : Icons.lock_open,
                    color: roomState.isRoomLocked ? AppColors.warning : Colors.white,
                  ),
                  title: Text(
                    roomState.isRoomLocked ? 'Unlock Classroom' : 'Lock Classroom',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    roomState.isRoomLocked ? 'New students cannot enter until unlocked' : 'Prevent new entries into session',
                    style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(liveClassRoomProvider.notifier).toggleLockRoom();
                    _showToast(
                      context,
                      roomState.isRoomLocked ? 'Classroom unlocked' : 'Classroom locked to new entries',
                    );
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(
                    roomState.isHandRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
                    color: roomState.isHandRaised ? AppColors.warning : Colors.white,
                  ),
                  title: Text(
                    roomState.isHandRaised ? 'Lower Hand' : 'Raise Hand',
                    style: TextStyle(
                      color: roomState.isHandRaised ? AppColors.warning : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    roomState.isHandRaised ? 'Teacher has notified your hand raise' : 'Notify teacher that you have a doubt',
                    style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(liveClassRoomProvider.notifier).toggleHandRaise(userName);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline, color: AppColors.skyBlue),
                  title: const Text('Ask a Doubt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Post query in live discussion chat', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChatDrawer();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: AppColors.primaryLight),
                title: Text(
                  roomState.unreadChatCount > 0
                      ? 'Live Chat (${roomState.unreadChatCount} new)'
                      : 'Live Chat',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('View and send messages to classroom', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChatDrawer();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline, color: AppColors.primaryLight),
                title: Text('Participants (${roomState.participants.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('View everyone currently in class', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showParticipantsDrawer();
                },
              ),
              ListTile(
                key: const Key('enter_pip_menu_tile'),
                leading: const Icon(Icons.picture_in_picture_alt, color: AppColors.skyBlue),
                title: const Text('Picture-in-Picture', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Minimize class to a floating window', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterPip();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: AppColors.slate400),
                title: const Text('Classroom Diagnostics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('View server commit, room tokens and stats', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDebugOverlay(context, roomState);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _enterPip() async {
    final pipService = ref.read(pipServiceProvider);
    final entered = await pipService.enterPip(width: 16, height: 9);
    if (!entered && mounted) {
      _showToast(context, 'Picture-in-Picture is not supported on this device/platform');
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(liveClassRoomProvider);
    final user = ref.watch(authStateProvider).user;
    final userName = user?.name ?? 'User';

    // 1. Zoom & Google Meet Style Pre-Join Lobby (Green Room)
    if (_isInLobby) {
      return _buildLobbyScreen(user);
    }

    if (roomState.isConnecting) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connecting to Live Classroom...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Establishing secure media session and interactive canvas',
                style: TextStyle(color: AppColors.slate400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (roomState.errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Failed to Join Live Classroom',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  roomState.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate400, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _isInLobby = true;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF334155)),
                      ),
                      child: const Text('Back to Lobby'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        ref.read(liveClassRoomProvider.notifier).joinRoom(
                              widget.classId,
                              currentUserId: user?.id,
                              currentUserName: user?.name,
                              currentUserRole: user?.role,
                              initialMicMuted: !_lobbyMicEnabled,
                              initialCameraOff: !_lobbyCameraEnabled,
                              prewarmVideoTrack: _lobbyVideoTrack,
                            );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final liveClass = roomState.liveClass;
    final isPipActive = ref.watch(isPipActiveProvider);

    if (isPipActive) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _buildVideoStage(roomState),
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final stageWidget = (roomState.stage == 'BOARD' || roomState.isWhiteboardOpen)
        ? Stack(
            children: [
              Positioned.fill(
                child: DigitalBoard(
                  isTeacher: roomState.isHost || roomState.isBoardAllowed,
                  onDrawStroke: (stroke) => ref.read(liveClassRoomProvider.notifier).sendDrawStroke(stroke),
                  onClearBoard: () => ref.read(liveClassRoomProvider.notifier).sendClearBoard(),
                  remoteDrawStream: ref.read(liveClassRoomProvider.notifier).remoteDrawStream,
                  remoteClearStream: ref.read(liveClassRoomProvider.notifier).remoteClearStream,
                ),
              ),
              // Teacher camera PiP overlay over board (Stage 1.3)
              Positioned(
                top: 10,
                right: 10,
                width: 100,
                height: 125,
                child: _buildTeacherPip(roomState),
              ),
            ],
          )
        : ((roomState.stage == 'SLIDES' || roomState.isDocPresenting)
            ? DocumentViewer(
                isTeacher: roomState.isHost,
                syncedPage: roomState.docPage,
                syncedTotalPages: roomState.docTotalPages,
                docTitle: roomState.docTitle,
                docPath: roomState.docPath,
                docUrl: roomState.docUrl,
                isSharedWithStudents: roomState.isSharedWithStudents,
                isUploading: roomState.isSlidesUploading,
                uploadProgress: roomState.slidesUploadProgress,
                onDiagnosticsUpdate: ({fetchStatus, bytesLoaded, renderError}) {
                  ref.read(liveClassRoomProvider.notifier).updateSlidesDiagnostics(
                        fetchStatus: fetchStatus,
                        bytesLoaded: bytesLoaded,
                        renderError: renderError,
                      );
                },
                onClose: roomState.isHost
                    ? () => ref.read(liveClassRoomProvider.notifier).setDocPresentation(isOpen: false)
                    : null,
                onPageChanged: roomState.isHost
                    ? (page) => ref.read(liveClassRoomProvider.notifier).setDocPage(page)
                    : null,
                onLocalFileSelected: roomState.isHost
                    ? (path, name) => ref.read(liveClassRoomProvider.notifier).uploadAndPresentSlides(
                          fileName: name,
                          filePath: path,
                          onError: (err) => _showToast(context, err),
                          onSuccess: (msg) => _showToast(context, msg),
                        )
                    : null,
              )
            : _buildVideoStage(roomState));

    final mainColumn = Column(
      children: [
        // Top Bar
        _buildTopBar(liveClass, roomState),

        // Reconnection Alert Banner
        if (roomState.connectionState == 'reconnecting') _buildReconnectBanner(),

        // Student locked mic banner: "Teacher ne mic band kiya hai" + Raise Hand
        if (!roomState.isHost && roomState.isMicLocked)
          _buildMicLockedBanner(userName, roomState),

        // Main Stage Area
        Expanded(child: stageWidget),

        // Bottom Controls Toolbar (centered, 320dp responsive)
        _buildControlsBar(roomState, userName, isDesktop: isDesktop),
      ],
    );

    // Desktop & Web Keyboard Shortcuts (M, V, S, B, C, Left, Right)
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        if (!roomState.isHost && roomState.isMicLocked) {
          _showToast(context, 'Teacher ne mic band kiya hai. Raise Hand to speak.');
          return;
        }
        ref.read(liveClassRoomProvider.notifier).toggleMic();
      },
      const SingleActivator(LogicalKeyboardKey.keyV): () {
        ref.read(liveClassRoomProvider.notifier).toggleCamera();
      },
      const SingleActivator(LogicalKeyboardKey.keyS): () {
        if (roomState.isHost) {
          ref.read(liveClassRoomProvider.notifier).toggleScreenShare(
                onError: (msg) => _showToast(context, msg),
              );
        }
      },
      const SingleActivator(LogicalKeyboardKey.keyB): () {
        if (roomState.isHost || roomState.isBoardAllowed) {
          ref.read(liveClassRoomProvider.notifier).toggleWhiteboard();
        }
      },
      const SingleActivator(LogicalKeyboardKey.keyC): () {
        if (isDesktop) {
          setState(() {
            _showDesktopSidebar = !_showDesktopSidebar;
            _desktopSidebarTab = 0;
          });
        } else {
          _showChatDrawer();
        }
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        if (roomState.isHost && (roomState.stage == 'SLIDES' || roomState.isDocPresenting)) {
          if (roomState.docPage > 1) {
            ref.read(liveClassRoomProvider.notifier).setDocPresentation(
                  isOpen: true,
                  title: roomState.docTitle,
                  page: roomState.docPage - 1,
                );
          }
        }
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        if (roomState.isHost && (roomState.stage == 'SLIDES' || roomState.isDocPresenting)) {
          ref.read(liveClassRoomProvider.notifier).setDocPresentation(
                isOpen: true,
                title: roomState.docTitle,
                page: roomState.docPage + 1,
              );
        }
      },
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: isDesktop
                ? Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: mainColumn,
                      ),
                      if (_showDesktopSidebar)
                        _buildDesktopSidebar(roomState, user, userName),
                    ],
                  )
                : mainColumn,
          ),
        ),
      ),
    );
  }

  Widget _buildMicLockedBanner(String userName, LiveClassRoomState roomState) {
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Teacher ne mic band kiya hai',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => ref.read(liveClassRoomProvider.notifier).toggleHandRaise(userName),
            icon: Icon(roomState.isHandRaised ? Icons.pan_tool : Icons.pan_tool_outlined, size: 14),
            label: Text(roomState.isHandRaised ? 'Hand Raised' : 'Raise Hand', style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connection unstable. Attempting to reconnect...',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(LiveClassModel? liveClass, LiveClassRoomState roomState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
      ),
      child: Row(
        children: [
          // Red LIVE pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.liveRed,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.white, size: 7),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Elapsed Session Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              _formatSessionTime(_sessionSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Title & Batch Info (with ellipsis for overflow safety at 320/360 dp, long press for debug overlay)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _showDebugOverlay(context, roomState),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    liveClass?.title ?? 'Live Class',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    '${liveClass?.batchName ?? 'Batch'} • Host: ${liveClass?.teacherName ?? 'Teacher'}',
                    style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),

          // Connection status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: roomState.connectionState == 'connected'
                  ? AppColors.success.withValues(alpha: 0.2)
                  : (roomState.connectionState == 'reconnecting'
                      ? AppColors.warning.withValues(alpha: 0.2)
                      : AppColors.slate700),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: roomState.connectionState == 'connected'
                    ? AppColors.success
                    : (roomState.connectionState == 'reconnecting'
                        ? AppColors.warning
                        : AppColors.slate500),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: roomState.connectionState == 'connected'
                      ? AppColors.success
                      : (roomState.connectionState == 'reconnecting'
                          ? AppColors.warning
                          : AppColors.slate400),
                ),
                const SizedBox(width: 4),
                Text(
                  roomState.connectionState == 'connected'
                      ? 'Connected'
                      : (roomState.connectionState == 'reconnecting' ? 'Reconnecting' : 'Connecting'),
                  style: TextStyle(
                    color: roomState.connectionState == 'connected'
                        ? AppColors.success
                        : (roomState.connectionState == 'reconnecting'
                            ? AppColors.warning
                            : AppColors.slate400),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Picture-in-Picture Button
          IconButton(
            key: const Key('enter_pip_topbar_btn'),
            tooltip: 'Picture-in-Picture',
            icon: const Icon(Icons.picture_in_picture_alt, size: 18, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _enterPip,
          ),
          const SizedBox(width: 8),

          // Leave / End button (triggers ConfirmDialog)
          ElevatedButton(
            onPressed: () => _handleLeaveOrEnd(roomState.isHost),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.liveRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(54, 30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              roomState.isHost ? 'End' : 'Leave',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStage(LiveClassRoomState roomState) {
    // 1. Check if remote screen share is active
    if (roomState.remoteScreenShareTrack != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF0F172A),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: lk.VideoTrackRenderer(
                        roomState.remoteScreenShareTrack!,
                        fit: lk.VideoViewFit.contain,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.screen_share, color: AppColors.skyBlue, size: 14),
                            SizedBox(width: 6),
                            Text('Live Screen Share', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 1,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: roomState.participants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 120,
                    child: _buildParticipantTile(roomState.participants[index], roomState),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // 2. Check if local screen sharing is active
    if (roomState.isScreenSharing) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF0F172A),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.skyBlue, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.screen_share_rounded, color: AppColors.skyBlue, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'You are sharing your screen',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All students in the class can see your screen in real time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.slate400, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => ref.read(liveClassRoomProvider.notifier).toggleScreenShare(),
                      icon: const Icon(Icons.stop_screen_share, size: 18),
                      label: const Text('Stop Sharing Screen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.liveRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 1,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: roomState.participants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 120,
                    child: _buildParticipantTile(roomState.participants[index], roomState),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // Find teacher / host participant
    final hostParticipant = roomState.participants.firstWhere(
      (p) => p.isHost,
      orElse: () => ClassParticipant(
        identity: 'host',
        name: roomState.liveClass?.teacherName ?? 'Teacher',
        role: 'TEACHER',
        isHost: true,
      ),
    );

    // Other student participants
    final otherParticipants = roomState.participants.where((p) => !p.isHost).toList();

    // Determine hero participant and secondary strip
    ClassParticipant heroParticipant;
    List<ClassParticipant> secondaryParticipants;

    if (roomState.isHost) {
      // Teacher screen: hero shows the student (active or with video)
      final studentWithVideo = otherParticipants.firstWhere(
        (p) => roomState.remoteVideoTracks.containsKey(p.identity),
        orElse: () => otherParticipants.isNotEmpty ? otherParticipants.first : hostParticipant,
      );
      heroParticipant = studentWithVideo;
      // Secondary strip includes teacher's own preview + all other participants
      secondaryParticipants = [
        hostParticipant,
        ...otherParticipants.where((p) => p.identity != heroParticipant.identity),
      ];
    } else {
      // Student screen: hero shows Teacher
      heroParticipant = hostParticipant;
      secondaryParticipants = [
        ...roomState.participants.where((p) => p.identity != hostParticipant.identity),
      ];
    }

    // Determine hero video track
    lk.VideoTrack? heroVideoTrack;
    if (heroParticipant.isLocal) {
      if (roomState.localVideoTrack != null && !roomState.isCameraOff) {
        heroVideoTrack = roomState.localVideoTrack;
      }
    } else {
      if (roomState.remoteVideoTracks.containsKey(heroParticipant.identity)) {
        heroVideoTrack = roomState.remoteVideoTracks[heroParticipant.identity];
      } else if (roomState.remoteVideoTracks.isNotEmpty) {
        heroVideoTrack = roomState.remoteVideoTracks.values.first;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Hero Box (Host / Teacher / Active Speaker)
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: heroParticipant.isSpeaking ? AppColors.success : const Color(0xFF334155),
                  width: heroParticipant.isSpeaking ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (heroVideoTrack != null)
                    Positioned.fill(
                      child: lk.VideoTrackRenderer(
                        heroVideoTrack,
                        fit: lk.VideoViewFit.cover,
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              heroParticipant.initials,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            heroParticipant.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                heroParticipant.isRealMicMuted ? Icons.mic_off : Icons.graphic_eq,
                                color: heroParticipant.isRealMicMuted ? AppColors.error : AppColors.primaryLight,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                heroParticipant.isRealMicMuted ? 'Microphone Muted' : (heroParticipant.isHost ? 'Speaking (Host)' : 'Speaking'),
                                style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Bottom left badge with name and mic status
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            heroParticipant.isRealMicMuted ? Icons.mic_off : Icons.mic,
                            color: heroParticipant.isRealMicMuted ? AppColors.error : AppColors.success,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            heroParticipant.isLocal ? '${heroParticipant.name} (You)' : heroParticipant.name,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Secondary Peer Tiles Strip (deduplicated real participants, max 9)
          Expanded(
            flex: 1,
            child: secondaryParticipants.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Waiting for students to join classroom...',
                        style: TextStyle(color: AppColors.slate400, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: secondaryParticipants.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final p = secondaryParticipants[index];
                      return SizedBox(
                        width: 120,
                        child: _buildParticipantTile(p, roomState),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(ClassParticipant p, LiveClassRoomState roomState) {
    lk.VideoTrack? tileVideoTrack;
    if (p.isLocal) {
      if (roomState.localVideoTrack != null && !roomState.isCameraOff) {
        tileVideoTrack = roomState.localVideoTrack;
      }
    } else {
      if (roomState.remoteVideoTracks.containsKey(p.identity)) {
        tileVideoTrack = roomState.remoteVideoTracks[p.identity];
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: p.isSpeaking ? AppColors.success : (p.isHandRaised ? AppColors.warning : const Color(0xFF334155)),
          width: p.isSpeaking || p.isHandRaised ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (tileVideoTrack != null)
            Positioned.fill(
              child: lk.VideoTrackRenderer(
                tileVideoTrack,
                fit: lk.VideoViewFit.cover,
              ),
            )
          else
            Center(
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.slate700,
                child: Text(
                  p.initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          if (p.isHandRaised)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.pan_tool, color: AppColors.warning, size: 14),
            ),
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      p.isLocal ? '${p.name} (You)' : p.name,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    p.isRealMicMuted ? Icons.mic_off : Icons.mic,
                    color: p.isRealMicMuted ? AppColors.error : AppColors.success,
                    size: 11,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Google Meet Style Bottom Bar (Priority ordered, fits 320-430dp without clipping or overflow)
  Widget _buildControlsBar(LiveClassRoomState roomState, String userName, {bool isDesktop = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        // Compact if screen is narrow (< 390dp) or large text scale (> 1.15)
        final isCompact = availableWidth < 390 || textScale > 1.15;

        Widget buildMicBtn() => _buildControlButton(
          icon: roomState.isMicMuted ? Icons.mic_off : Icons.mic,
          label: 'Mic',
          isActive: !roomState.isMicMuted,
          color: roomState.isMicMuted ? AppColors.error : Colors.white,
          backgroundColor: roomState.isMicMuted ? const Color(0xFF334155) : AppColors.primary,
          onTap: () {
            if (!roomState.isHost && roomState.isMicLocked) {
              _showToast(context, 'Teacher ne mic band kiya hai. Raise Hand to speak.');
              return;
            }
            ref.read(liveClassRoomProvider.notifier).toggleMic();
          },
        );

        Widget buildCamBtn() => _buildControlButton(
          icon: roomState.isCameraOff ? Icons.videocam_off : Icons.videocam,
          label: 'Video',
          isActive: !roomState.isCameraOff,
          color: roomState.isCameraOff ? AppColors.error : Colors.white,
          backgroundColor: roomState.isCameraOff ? const Color(0xFF334155) : AppColors.primary,
          onTap: () => ref.read(liveClassRoomProvider.notifier).toggleCamera(),
        );

        final isPresenting = roomState.isWhiteboardOpen || roomState.isScreenSharing || roomState.isDocPresenting;
        Widget buildPresentBtn() => _buildControlButton(
          icon: Icons.present_to_all,
          label: 'Present',
          isActive: isPresenting,
          color: isPresenting ? Colors.white : AppColors.slate100,
          backgroundColor: isPresenting ? AppColors.primary : AppColors.slate800,
          onTap: () => _showPresentMenu(context, roomState),
        );

        Widget buildHandBtn() => _buildControlButton(
          icon: roomState.isHandRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
          label: 'Hand',
          isActive: roomState.isHandRaised,
          color: roomState.isHandRaised ? Colors.white : AppColors.slate100,
          backgroundColor: roomState.isHandRaised ? AppColors.warning : AppColors.slate800,
          onTap: () => ref.read(liveClassRoomProvider.notifier).toggleHandRaise(userName),
        );

        Widget buildChatBtn() => Stack(
          clipBehavior: Clip.none,
          children: [
            _buildControlButton(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              isActive: isDesktop && _showDesktopSidebar && _desktopSidebarTab == 0,
              color: (isDesktop && _showDesktopSidebar && _desktopSidebarTab == 0) ? Colors.white : AppColors.slate100,
              backgroundColor: (isDesktop && _showDesktopSidebar && _desktopSidebarTab == 0)
                  ? AppColors.primary
                  : AppColors.slate800,
              onTap: () {
                if (isDesktop) {
                  setState(() {
                    _showDesktopSidebar = true;
                    _desktopSidebarTab = 0;
                  });
                } else {
                  _showChatDrawer();
                }
              },
            ),
            if (roomState.unreadChatCount > 0)
              Positioned(
                top: 0,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.liveRed,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '${roomState.unreadChatCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );

        Widget buildPeopleBtn() => _buildControlButton(
          icon: Icons.people_outline,
          label: 'People',
          isActive: isDesktop && _showDesktopSidebar && _desktopSidebarTab == 1,
          color: (isDesktop && _showDesktopSidebar && _desktopSidebarTab == 1) ? Colors.white : AppColors.slate100,
          backgroundColor: (isDesktop && _showDesktopSidebar && _desktopSidebarTab == 1)
              ? AppColors.primary
              : AppColors.slate800,
          onTap: () {
            if (isDesktop) {
              setState(() {
                _showDesktopSidebar = true;
                _desktopSidebarTab = 1;
              });
            } else {
              _showParticipantsDrawer();
            }
          },
        );

        Widget buildMoreBtn() => _buildControlButton(
          icon: Icons.more_horiz,
          label: 'More',
          isActive: false,
          color: AppColors.slate100,
          backgroundColor: AppColors.slate800,
          onTap: () => _showMoreActionsSheet(roomState, userName),
        );

        Widget buildEndLeaveBtn() => _buildControlButton(
          icon: Icons.call_end,
          label: roomState.isHost ? 'End' : 'Leave',
          isActive: true,
          color: Colors.white,
          backgroundColor: AppColors.liveRed,
          onTap: () => _handleLeaveOrEnd(roomState.isHost),
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
    );
  }

  Widget _buildControlButton({
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

  Widget _buildDesktopSidebar(LiveClassRoomState roomState, dynamic user, String userName) {
    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(left: BorderSide(color: Color(0xFF334155), width: 1)),
      ),
      child: Column(
        children: [
          // Sidebar header tabs (Chat, People, Hands, Polls, Doubts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSidebarTabBtn(0, Icons.chat_bubble_outline, 'Chat'),
                _buildSidebarTabBtn(1, Icons.people_outline, 'People'),
                _buildSidebarTabBtn(2, Icons.pan_tool_outlined, 'Hands'),
                _buildSidebarTabBtn(3, Icons.poll_outlined, 'Polls'),
                _buildSidebarTabBtn(4, Icons.help_outline, 'Doubts'),
              ],
            ),
          ),
          Expanded(
            child: _buildSidebarTabBody(roomState, user, userName),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTabBtn(int index, IconData icon, String label) {
    final isSelected = _desktopSidebarTab == index;
    return InkWell(
      onTap: () => setState(() => _desktopSidebarTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: AppColors.primary, width: 1) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppColors.primary : AppColors.slate400),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarTabBody(LiveClassRoomState roomState, dynamic user, String userName) {
    switch (_desktopSidebarTab) {
      case 0:
        return _buildDesktopChat(roomState, user, userName);
      case 1:
        return _buildDesktopPeople(roomState);
      case 2:
        return _buildDesktopHands(roomState);
      case 3:
        return _buildDesktopPolls(roomState);
      case 4:
        return _buildDesktopDoubts(roomState, user, userName);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDesktopChat(LiveClassRoomState roomState, dynamic user, String userName) {
    final userRole = user?.role ?? 'STUDENT';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: roomState.chatMessages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet. Ask doubt or message the class!',
                      style: TextStyle(color: AppColors.slate400, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: roomState.chatMessages.length,
                    itemBuilder: (context, idx) {
                      final msg = roomState.chatMessages[idx];
                      final isMe = msg.senderId == (user?.id ?? 'me');

                      if (msg.isSystem) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Text(
                              msg.text,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 11,
                                color: AppColors.slate400,
                              ),
                            ),
                          ),
                        );
                      }

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.primary : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: isMe ? null : Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isMe ? 'You' : msg.senderName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: isMe ? Colors.white : AppColors.primaryLight,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isMe ? Colors.white70 : AppColors.slate400,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg.text,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatTextController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Type doubt or message...',
                    hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      ref.read(liveClassRoomProvider.notifier).sendChatMessage(val, userName, userRole);
                      _chatTextController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                icon: const Icon(Icons.send, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.all(10),
                ),
                onPressed: () {
                  if (_chatTextController.text.trim().isNotEmpty) {
                    ref.read(liveClassRoomProvider.notifier).sendChatMessage(_chatTextController.text, userName, userRole);
                    _chatTextController.clear();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPeople(LiveClassRoomState roomState) {
    final sorted = List<ClassParticipant>.from(roomState.participants)
      ..sort((a, b) {
        if (a.isHandRaised != b.isHandRaised) return a.isHandRaised ? -1 : 1;
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Participants (${sorted.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              if (roomState.isHost)
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(liveClassRoomProvider.notifier).muteAll(lock: true);
                    _showToast(context, 'All student microphones muted and locked');
                  },
                  icon: const Icon(Icons.mic_off, size: 12),
                  label: const Text('Mute All', style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),
          const Divider(color: Color(0xFF334155)),
          Expanded(
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, idx) {
                final p = sorted[idx];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: p.isHost ? AppColors.primary : AppColors.slate700,
                    child: Text(p.initials, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(
                    p.isLocal ? '${p.name} (You)' : p.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    p.isHost ? 'Host / Teacher' : (p.isHandRaised ? 'Hand Raised' : 'Student'),
                    style: TextStyle(
                      color: p.isHandRaised ? AppColors.warning : AppColors.slate400,
                      fontSize: 10,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(p.isMicMuted ? Icons.mic_off : Icons.mic, size: 14, color: p.isMicMuted ? AppColors.error : AppColors.success),
                      const SizedBox(width: 4),
                      Icon(p.isCameraOff ? Icons.videocam_off : Icons.videocam, size: 14, color: p.isCameraOff ? AppColors.slate500 : AppColors.success),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHands(LiveClassRoomState roomState) {
    final hands = roomState.participants.where((p) => p.isHandRaised).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pan_tool, color: AppColors.warning, size: 16),
              const SizedBox(width: 8),
              Text(
                'Hand Raise Queue (${hands.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155)),
          Expanded(
            child: hands.isEmpty
                ? const Center(
                    child: Text(
                      'No students raising hand currently',
                      style: TextStyle(color: AppColors.slate400, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: hands.length,
                    itemBuilder: (context, idx) {
                      final p = hands[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${idx + 1}',
                                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const Text('Waiting to speak', style: TextStyle(color: AppColors.slate400, fontSize: 10)),
                                ],
                              ),
                            ),
                            if (roomState.isHost)
                              ElevatedButton(
                                onPressed: () {
                                  ref.read(liveClassRoomProvider.notifier).allowStudentToSpeak(p.identity);
                                  ref.read(liveClassRoomProvider.notifier).lowerStudentHand(p.identity);
                                  _showToast(context, 'Granted speak rights to ${p.name}');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                                child: const Text('Allow to Speak', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPolls(LiveClassRoomState roomState) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.poll_outlined, color: AppColors.slate500, size: 40),
            SizedBox(height: 12),
            Text(
              'No Active Poll',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text(
              'Teacher can launch live quick-polls during lecture to check comprehension.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.slate400, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopDoubts(LiveClassRoomState roomState, dynamic user, String userName) {
    return _buildDesktopChat(roomState, user, userName);
  }

  // Pre-join Green Room / Lobby Screen
  Widget _buildLobbyScreen(dynamic user) {
    final isTeacher = user?.role == 'TEACHER' || user?.role == 'ADMIN';
    final title = _lobbyClass?.title ?? 'Live Classroom';
    final batch = _lobbyClass?.batchName ?? 'Class';
    final teacher = _lobbyClass?.teacherName ?? 'Teacher';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _stopLobbyCamera();
            if (mounted) context.pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$batch • Host: $teacher',
              style: const TextStyle(fontSize: 11, color: AppColors.slate400),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoadingLobby
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Heading
                    const Text(
                      'Ready to join?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Check your camera and microphone preview before entering the live class.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 20),

                    // Camera Preview Card (Zoom / Google Meet Style)
                    Container(
                      height: 320,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _lobbyCameraEnabled ? AppColors.primary : const Color(0xFF334155),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Live camera preview or avatar placeholder
                          if (_lobbyCameraEnabled && _lobbyVideoTrack != null)
                            Positioned.fill(
                              child: lk.VideoTrackRenderer(
                                _lobbyVideoTrack!,
                                fit: lk.VideoViewFit.cover,
                              ),
                            )
                          else
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 46,
                                  backgroundColor: AppColors.primary,
                                  child: Text(
                                    (user?.name != null && user!.name.isNotEmpty)
                                        ? user.name.substring(0, 1).toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  user?.name ?? 'You',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Camera is off',
                                  style: TextStyle(color: AppColors.slate400, fontSize: 12),
                                ),
                              ],
                            ),

                          // Pre-join Quick Controls (Mic & Cam toggle pills overlaid at bottom)
                          Positioned(
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Mic Toggle
                                  InkWell(
                                    onTap: _toggleLobbyMic,
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _lobbyMicEnabled ? const Color(0xFF1E293B) : AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _lobbyMicEnabled ? Icons.mic : Icons.mic_off,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Camera Toggle
                                  InkWell(
                                    onTap: _toggleLobbyCamera,
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _lobbyCameraEnabled ? const Color(0xFF1E293B) : AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _lobbyCameraEnabled ? Icons.videocam : Icons.videocam_off,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Media Status Summary Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLobbyBadge(
                          icon: _lobbyMicEnabled ? Icons.mic : Icons.mic_off,
                          label: _lobbyMicEnabled ? 'Mic On' : 'Mic Off',
                          isPositive: _lobbyMicEnabled,
                        ),
                        const SizedBox(width: 12),
                        _buildLobbyBadge(
                          icon: _lobbyCameraEnabled ? Icons.videocam : Icons.videocam_off,
                          label: _lobbyCameraEnabled ? 'Camera On' : 'Camera Off',
                          isPositive: _lobbyCameraEnabled,
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          isTeacher ? Icons.play_arrow : Icons.login,
                          color: Colors.white,
                        ),
                        label: Text(
                          isTeacher ? 'Start Class Now' : 'Join Classroom Now',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        onPressed: _enterClassroom,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF334155)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          _stopLobbyCamera();
                          if (mounted) context.pop();
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLobbyBadge({
    required IconData icon,
    required String label,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isPositive ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isPositive ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
