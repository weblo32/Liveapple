import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/widgets/color_tile.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_pill.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../batch/presentation/batch_controller.dart';
import '../../batch/presentation/batch_detail_screen.dart';
import '../../batch/presentation/batch_students_dialog.dart';
import '../../batch/presentation/create_batch_dialog.dart';
import '../../liveclass/domain/live_class_model.dart';
import '../../liveclass/presentation/live_class_controller.dart';
import '../../notifications/presentation/widgets/notification_bell_button.dart';
import '../../notifications/presentation/controllers/notification_controller.dart';
import '../../timetable/domain/timetable_model.dart';
import '../../timetable/presentation/add_timetable_slot_dialog.dart';
import '../../timetable/presentation/timetable_controller.dart';
import '../../institute/presentation/institute_branding_controller.dart';
import '../../institute/presentation/institute_code_dialog.dart';

class TeacherHomeScreen extends ConsumerStatefulWidget {
  final UserModel user;

  const TeacherHomeScreen({super.key, required this.user});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  int _currentBottomNavIndex = 0; // 0: Home, 1: Timetable, 2: Batches, 3: Profile
  String _liveClassFilter = 'ALL'; // 'ALL', 'LIVE', 'SCHEDULED', 'PAST'
  bool _isGeneratingSlots = false;

  // Settings switches
  bool _classReminders = true;
  bool _liveAlerts = true;

  Timer? _fallbackPollingTimer;
  io.Socket? _globalSocket;

  @override
  void initState() {
    super.initState();
    _classReminders = widget.user.remindersEnabled;
    _liveAlerts = widget.user.liveAlertsEnabled;

    // 10-second fallback polling for live classes and notifications
    _fallbackPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        ref.read(liveClassProvider.notifier).loadClasses();
        ref.read(notificationControllerProvider.notifier).fetchNotifications(showLoading: false);
      }
    });

    Future.microtask(() {
      ref.read(batchListProvider.notifier).loadBatches();
      ref.read(timetableProvider.notifier).loadSlots();
      ref.read(liveClassProvider.notifier).loadClasses();
      ref.read(notificationControllerProvider.notifier).fetchNotifications(showLoading: false);
      ref.read(instituteBrandingProvider.notifier).syncFromUser(widget.user);
      _initGlobalSocket();
    });
  }

  /// Connects a background socket to receive instant 'class:live', 'class:scheduled', and 'notification:new' events.
  Future<void> _initGlobalSocket() async {
    try {
      final storage = SecureStorageService();
      final baseUrl = await storage.getBaseUrl() ?? Endpoints.defaultBaseUrl;
      final accessToken = await storage.getAccessToken();
      if (accessToken == null) return;

      // Register device FCM token if saved
      ref.read(pushNotificationServiceProvider).registerTokenIfSaved();

      final uri = Uri.parse(baseUrl);
      final socketHost = '${uri.scheme}://${uri.host}:${uri.port}';

      _globalSocket = io.io(
        socketHost,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': accessToken})
            .enableAutoConnect()
            .build(),
      );

      _globalSocket?.on('class:live', (data) {
        debugPrint('[TEACHER-SOCKET] class:live received. Reloading classes...');
        if (mounted) {
          ref.read(liveClassProvider.notifier).loadClasses();
        }
      });

      _globalSocket?.on('class:scheduled', (data) {
        if (mounted) {
          ref.read(liveClassProvider.notifier).loadClasses();
        }
      });

      _globalSocket?.on('notification:new', (data) {
        debugPrint('[TEACHER-SOCKET] notification:new received: $data');
        if (mounted && data != null) {
          final dataMap = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          ref.read(pushNotificationServiceProvider).handleIncomingNotification(context, dataMap);
        }
      });

      _globalSocket?.on('connect_error', (err) {
        debugPrint('[TEACHER-SOCKET] connect error: $err');
      });
    } catch (e) {
      debugPrint('[TEACHER-SOCKET] setup error: $e');
    }
  }

  @override
  void dispose() {
    _fallbackPollingTimer?.cancel();
    _globalSocket?.disconnect();
    _globalSocket?.dispose();
    _globalSocket = null;
    super.dispose();
  }

  Future<void> _syncNotificationPrefs() async {
    final prefs = {
      'reminders': _classReminders,
      'liveAlerts': _liveAlerts,
      'homework': true,
      'testAlerts': true,
    };
    await ref.read(authStateProvider.notifier).updateProfile(
      notificationPrefs: prefs,
    );
  }

  void _showCreateBatch() {
    showDialog(
      context: context,
      builder: (ctx) => const CreateBatchDialog(),
    );
  }

  void _showAddSlot({String? batchId, int? day}) {
    AddTimetableSlotDialog.show(
      context,
      preselectedBatchId: batchId,
      preselectedDay: day,
    );
  }

  Future<void> _generateClassesFromSlots() async {
    setState(() => _isGeneratingSlots = true);
    try {
      final res = await ref.read(liveClassProvider.notifier).generateUpcoming(daysAhead: 7);
      final count = res['classesCreated'] ?? res['created'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully synced $count live classes from timetable slots!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate classes: $e'),
            backgroundColor: AppColors.liveRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSlots = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brandingState = ref.watch(instituteBrandingProvider);
    final brandColor = brandingState.branding.brandColor;
    final instituteName = brandingState.branding.name.isNotEmpty
        ? brandingState.branding.name
        : (widget.user.institute?.name ?? 'Classora Faculty');
    final instituteCode = brandingState.branding.effectiveCode;

    return Theme(
      data: AppTheme.lightTheme,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: brandColor,
          elevation: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: _currentBottomNavIndex == 0
              ? Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (brandingState.branding.logoUrl != null &&
                              brandingState.branding.logoUrl!.isNotEmpty)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                brandingState.branding.logoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    brandingState.branding.initials,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: brandColor,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                brandingState.branding.initials,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: brandColor,
                                ),
                              ),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  instituteName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => InstituteCodeDialog.show(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    instituteCode,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Faculty Portal',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Text(
                  _currentBottomNavIndex == 1
                      ? 'Timetable Manager'
                      : _currentBottomNavIndex == 2
                          ? 'My Batches'
                          : 'Faculty Profile',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
          actions: [
            const NotificationBellButton(),
            const SizedBox(width: 8),
          ],
        ),
        drawer: _buildDrawer(),
        body: IndexedStack(
          index: _currentBottomNavIndex,
          children: [
            _buildHomeTab(),
            _buildTimetableTab(),
            _buildBatchesTab(),
            _buildProfileTab(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.borderLight, width: 0.8)),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -1)),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentBottomNavIndex,
            onTap: (idx) {
              setState(() {
                _currentBottomNavIndex = idx;
              });
            },
            backgroundColor: Colors.white,
            selectedItemColor: brandColor,
            unselectedItemColor: AppColors.slate400,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Timetable'),
              BottomNavigationBarItem(icon: Icon(Icons.school_outlined), label: 'Batches'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  /* -------------------------------------------------------------------------- */
  /* DRAWER (FACULTY)                                                           */
  /* -------------------------------------------------------------------------- */
  Widget _buildDrawer() {
    final brandingState = ref.watch(instituteBrandingProvider);
    final instituteCode = brandingState.branding.effectiveCode;
    final coachingName = brandingState.branding.name.isNotEmpty
        ? brandingState.branding.name
        : (widget.user.institute?.name ?? 'Classora Faculty');
    final brandColor = brandingState.branding.brandColor;

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: brandColor.withValues(alpha: 0.15),
                    child: Text(
                      widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : 'F',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: brandColor),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          coachingName,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brandColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Text(
                              'Faculty • Code $instituteCode',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                InstituteCodeDialog.show(context);
                              },
                              child: Icon(Icons.edit_outlined, size: 13, color: brandColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildDrawerItem(
                    icon: Icons.school_outlined,
                    label: 'My Batches',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentBottomNavIndex = 2);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Timetable Manager',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentBottomNavIndex = 1);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.sensors,
                    label: 'Live Classes',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentBottomNavIndex = 0;
                        _liveClassFilter = 'LIVE';
                      });
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.menu_book_outlined,
                    label: 'Study Material & Notes',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/study-material');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.assignment_outlined,
                    label: 'Assignments & Homework',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/assignments');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.videocam_outlined,
                    label: 'Recordings',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/recordings');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.calendar_today_outlined,
                    label: 'Attendance',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/attendance');
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.storefront_outlined,
                    label: 'Course Store',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/store');
                    },
                  ),
                  const Divider(color: AppColors.borderLight, height: 16),
                  _buildDrawerItem(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentBottomNavIndex = 3);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.vpn_key_outlined,
                    label: 'Institute Code ($instituteCode)',
                    onTap: () {
                      Navigator.pop(context);
                      InstituteCodeDialog.show(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.help_outline,
                    label: 'Help / Faculty Guide',
                    onTap: () {
                      Navigator.pop(context);
                      _showHelpDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.logout,
                    label: 'Sign Out',
                    textColor: AppColors.liveRed,
                    onTap: () async {
                      Navigator.pop(context);
                      final confirmed = await ConfirmDialog.show(
                        context,
                        title: 'Sign Out',
                        message: 'Are you sure you want to sign out from Classora?',
                        confirmText: 'Sign Out',
                        isDestructive: true,
                      );
                      if (confirmed == true) {
                        ref.read(authStateProvider.notifier).logout();
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: 'Classora Faculty App: Connect, teach and lead your cohorts.'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Classora Faculty invite link copied!')),
                    );
                  },
                  icon: const Icon(Icons.share, size: 16, color: Colors.white),
                  label: const Text('Share App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.skyBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: textColor ?? AppColors.slate700, size: 20),
      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor ?? AppColors.textLight)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  /* -------------------------------------------------------------------------- */
  /* TAB 0: HOME TAB (FACULTY)                                                  */
  /* -------------------------------------------------------------------------- */
  Widget _buildHomeTab() {
    final liveClassState = ref.watch(liveClassProvider);
    final timetableState = ref.watch(timetableProvider);
    final batchState = ref.watch(batchListProvider);

    final activeLiveClass = liveClassState.classes.cast<LiveClassModel?>().firstWhere(
          (c) => c != null && c.isLive,
          orElse: () => null,
        );
    final upcomingClasses = liveClassState.classes.where((c) => c.isScheduled).toList();

    final todayWeekday = DateTime.now().weekday % 7;
    final todaySlots = timetableState.slots.where((s) => s.dayOfWeek == todayWeekday).toList();

    // Stats
    final totalStudents = batchState.batches.fold<int>(0, (sum, b) => sum + b.activeStudentsCount);
    final totalBatches = batchState.batches.length;
    final weeklySlots = timetableState.slots.length;

    // Filtered classes list
    final List<LiveClassModel> displayedClasses;
    if (_liveClassFilter == 'LIVE') {
      displayedClasses = liveClassState.classes.where((c) => c.isLive).toList();
    } else if (_liveClassFilter == 'SCHEDULED') {
      displayedClasses = liveClassState.classes.where((c) => c.isScheduled).toList();
    } else if (_liveClassFilter == 'PAST') {
      displayedClasses = liveClassState.classes.where((c) => c.isEnded).toList();
    } else {
      displayedClasses = liveClassState.classes;
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(liveClassProvider.notifier).loadClasses();
        await ref.read(batchListProvider.notifier).loadBatches();
        await ref.read(timetableProvider.notifier).loadSlots();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Card
            if (activeLiveClass != null)
              _buildTeacherLiveHero(activeLiveClass)
            else if (upcomingClasses.isNotEmpty)
              _buildTeacherUpcomingHero(upcomingClasses.first)
            else if (todaySlots.isNotEmpty)
              _buildTeacherSlotHero(todaySlots.first)
            else
              _buildTeacherDefaultHero(),

            const SizedBox(height: 18),

            // 2. 2x3 ColorTiles per DESIGN.md
            const Text(
              'Quick Access',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textLight),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ColorTile(
                    title: 'Batches',
                    color: AppColors.tileBatches,
                    icon: Icons.school,
                    onTap: () => setState(() => _currentBottomNavIndex = 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ColorTile(
                    title: 'Timetable',
                    color: AppColors.tileSchedule,
                    icon: Icons.calendar_month,
                    onTap: () => setState(() => _currentBottomNavIndex = 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ColorTile(
                    title: 'Live Classes',
                    color: AppColors.tileRecordings,
                    icon: Icons.sensors,
                    onTap: () {
                      setState(() => _liveClassFilter = 'LIVE');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ColorTile(
                    title: 'Study Material',
                    color: AppColors.tileMaterial,
                    icon: Icons.menu_book,
                    onTap: () => context.push('/study-material'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ColorTile(
                    title: 'Assignments\n& Tests',
                    color: const Color(0xFF4F46E5),
                    icon: Icons.assignment_outlined,
                    onTap: () => context.push('/assignments'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ColorTile(
                    title: 'Recordings',
                    color: AppColors.skyBlue,
                    icon: Icons.videocam_outlined,
                    onTap: () => context.push('/recordings'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 3. Faculty Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Students',
                    value: '$totalStudents',
                    icon: Icons.people_outline,
                    color: AppColors.skyBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    title: 'Batches',
                    value: '$totalBatches',
                    icon: Icons.school_outlined,
                    color: AppColors.tileBatches,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    title: 'Weekly Slots',
                    value: '$weeklySlots',
                    icon: Icons.schedule_outlined,
                    color: AppColors.tileRecordings,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 4. Live & Scheduled Classes Header + Generate Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live & Scheduled Sessions',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textLight),
                ),
                InkWell(
                  onTap: _isGeneratingSlots ? null : _generateClassesFromSlots,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.skyBlueLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isGeneratingSlots)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.skyBlue),
                          )
                        else
                          const Icon(Icons.sync, size: 14, color: AppColors.skyBlue),
                        const SizedBox(width: 4),
                        const Text(
                          'Sync from slots',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.skyBlue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'All (${liveClassState.classes.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip('LIVE', 'Live (${liveClassState.classes.where((c) => c.isLive).length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip('SCHEDULED', 'Upcoming (${liveClassState.classes.where((c) => c.isScheduled).length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip('PAST', 'Past (${liveClassState.classes.where((c) => c.isEnded).length})'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Classes List
            if (liveClassState.isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (displayedClasses.isEmpty)
              EmptyState(
                icon: Icons.videocam_off_outlined,
                title: 'No $_liveClassFilter classes found',
                subtitle: 'Use "Sync from slots" or Timetable tab to schedule sessions',
                buttonText: 'Sync Classes Now',
                onAction: _generateClassesFromSlots,
              )
            else
              ...displayedClasses.map((cls) => _buildClassCard(cls)),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _liveClassFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _liveClassFilter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.skyBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.skyBlue : AppColors.borderLight),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.slate700,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textLight),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: AppColors.slate500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(LiveClassModel cls) {
    final status = cls.isLive
        ? ClassStatus.live
        : cls.isScheduled
            ? ClassStatus.upcoming
            : ClassStatus.ended;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cls.isLive ? AppColors.liveRed.withValues(alpha: 0.5) : AppColors.borderLight),
      ),
      child: Row(
        children: [
          StatusPill(status: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cls.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${cls.batchName ?? 'Batch'} • ${cls.formattedDate} • ${cls.formattedTime}',
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _startOrEnterClass(cls),
            style: ElevatedButton.styleFrom(
              backgroundColor: cls.isLive ? AppColors.liveRed : AppColors.skyBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              cls.isLive ? 'Enter Room' : 'Start',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherLiveHero(LiveClassModel cls) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.liveRed.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const StatusPill(status: ClassStatus.live, customText: 'YOU ARE LIVE'),
              Text('${cls.attendanceCount} Students Connected', style: const TextStyle(fontSize: 11, color: AppColors.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(cls.batchName ?? 'Batch', style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/live/${cls.id}'),
                icon: const Icon(Icons.videocam, size: 16, color: Colors.white),
                label: const Text('Enter Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.liveRed, elevation: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherUpcomingHero(LiveClassModel cls) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.4)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusPill(status: ClassStatus.upcoming, customText: cls.timeUntilText),
              Text('${cls.formattedDate} • ${cls.formattedTime}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cls.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(cls.batchName ?? 'Batch', style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _startOrEnterClass(cls),
                icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                label: const Text('Start Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.skyBlue, elevation: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherSlotHero(TimetableSlotModel slot) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.4)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusPill(
                status: ClassStatus.upcoming,
                customText: 'TODAY AT ${TimetableSlotModel.formatMinutes(slot.startMin)}',
              ),
              Text('${slot.subject ?? 'Subject'} • ${slot.durationString}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.batchName ?? 'Batch', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Scheduled: ${TimetableSlotModel.formatMinutes(slot.startMin)} to ${TimetableSlotModel.formatMinutes(slot.endMin)}', style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _startSlotClass(slot),
                icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                label: const Text('Start Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.skyBlue, elevation: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherDefaultHero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: AppColors.skyBlueLight, shape: BoxShape.circle),
            child: const Icon(Icons.school, color: AppColors.skyBlue, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Faculty Command Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 2),
                Text('Schedule classes, broadcast live, and track student mastery', style: TextStyle(fontSize: 12, color: AppColors.slate500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startOrEnterClass(LiveClassModel cls) async {
    if (!cls.isLive) {
      final success = await ref.read(liveClassProvider.notifier).startClass(cls.id);
      if (success != null && mounted) {
        context.push('/live/${cls.id}');
      }
    } else {
      context.push('/live/${cls.id}');
    }
  }

  Future<void> _startSlotClass(TimetableSlotModel slot) async {
    try {
      final liveClassState = ref.read(liveClassProvider);
      final existing = liveClassState.classes.where((c) => c.batchId == slot.batchId && !c.isEnded).firstOrNull;
      if (existing != null) {
        await _startOrEnterClass(existing);
        return;
      }

      final newCls = await ref.read(liveClassProvider.notifier).createClass(
            batchId: slot.batchId,
            title: '${slot.subject ?? 'Live'}: ${slot.batchName ?? 'Class'}',
            scheduledAt: DateTime.now().toIso8601String(),
          );
      await ref.read(liveClassProvider.notifier).startClass(newCls.id);
      if (mounted) {
        context.push('/live/${newCls.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start slot class: $e')),
        );
      }
    }
  }

  /* -------------------------------------------------------------------------- */
  /* TAB 1: TIMETABLE MANAGER                                                   */
  /* -------------------------------------------------------------------------- */
  Widget _buildTimetableTab() {
    final timetableState = ref.watch(timetableProvider);
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final selectedDayIndex = timetableState.selectedDay;
    final currentDaySlots = timetableState.slots.where((s) => s.dayOfWeek == selectedDayIndex).toList();

    return Column(
      children: [
        // Day selector strip
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(7, (idx) {
                final isSelected = selectedDayIndex == idx;
                final count = timetableState.slots.where((s) => s.dayOfWeek == idx).length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => ref.read(timetableProvider.notifier).selectDay(idx),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.skyBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? AppColors.skyBlue : AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          if (isSelected) ...[
                            const Icon(Icons.check, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${days[idx]} ($count)',
                            style: TextStyle(
                              color: isSelected ? Colors.white : AppColors.slate700,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.borderLight),

        // Action Bar: Add Slot
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${days[selectedDayIndex]} Schedule (${currentDaySlots.length} slots)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddSlot(day: selectedDayIndex),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Slot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.skyBlue,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),

        // Slots List
        Expanded(
          child: currentDaySlots.isEmpty
              ? EmptyState(
                  icon: Icons.alarm_off_outlined,
                  title: 'No slots scheduled for ${days[selectedDayIndex]}',
                  subtitle: 'Add weekly recurring slots to broadcast live classes',
                  buttonText: 'Schedule Slot Now',
                  onAction: () => _showAddSlot(day: selectedDayIndex),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: currentDaySlots.length,
                  itemBuilder: (context, idx) {
                    final slot = currentDaySlots[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.skyBlueLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  TimetableSlotModel.formatMinutes(slot.startMin),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.skyBlue),
                                ),
                                Text(
                                  'to ${TimetableSlotModel.formatMinutes(slot.endMin)}',
                                  style: const TextStyle(fontSize: 9, color: AppColors.skyBlue),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slot.batchName ?? 'Batch',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textLight),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${slot.subject ?? 'Subject'} • ${slot.durationString}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.liveRed, size: 20),
                            onPressed: () async {
                              final confirmed = await ConfirmDialog.show(
                                context,
                                title: 'Delete Timetable Slot',
                                message: 'Remove ${slot.batchName} slot from ${days[selectedDayIndex]}?',
                                confirmText: 'Delete',
                                isDestructive: true,
                              );
                              if (confirmed == true) {
                                await ref.read(timetableProvider.notifier).deleteSlot(slot.id);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /* -------------------------------------------------------------------------- */
  /* TAB 2: MY BATCHES                                                          */
  /* -------------------------------------------------------------------------- */
  Widget _buildBatchesTab() {
    final batchState = ref.watch(batchListProvider);

    return Column(
      children: [
        // Action Bar: Create Batch
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cohort Batches (${batchState.batches.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateBatch,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Create Batch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.skyBlue,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.borderLight),

        Expanded(
          child: batchState.batches.isEmpty
              ? EmptyState(
                  icon: Icons.school_outlined,
                  title: 'No batches created yet',
                  subtitle: 'Create your first cohort to schedule classes and invite students',
                  buttonText: 'Create First Batch',
                  onAction: _showCreateBatch,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: batchState.batches.length,
                  itemBuilder: (context, idx) {
                    final b = batchState.batches[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  b.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textLight),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.skyBlueLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${b.activeStudentsCount} Students',
                                  style: const TextStyle(color: AppColors.skyBlue, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${b.subject} • Join Code: ${b.joinCode}', style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: b.joinCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Join code ${b.joinCode} copied!')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text('Copy Code', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: b)),
                                  );
                                },
                                icon: const Icon(Icons.info_outline, size: 14, color: Colors.white),
                                label: const Text('Batch Details', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.skyBlue,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => BatchStudentsDialog(batch: b),
                                  );
                                },
                                icon: const Icon(Icons.people_outline, size: 14),
                                label: const Text('Students', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /* -------------------------------------------------------------------------- */
  /* TAB 3: PROFILE / SETTINGS                                                  */
  /* -------------------------------------------------------------------------- */
  Widget _buildProfileTab() {
    final authState = ref.watch(authStateProvider);
    final currentUser = authState.user ?? widget.user;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.skyBlueLight,
                  backgroundImage: (currentUser.avatarUrl != null && currentUser.avatarUrl!.isNotEmpty)
                      ? NetworkImage(currentUser.avatarUrl!)
                      : null,
                  child: (currentUser.avatarUrl == null || currentUser.avatarUrl!.isEmpty)
                      ? Text(
                          currentUser.name.isNotEmpty ? currentUser.name[0].toUpperCase() : 'F',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.skyBlue),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(currentUser.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textLight)),
                      const SizedBox(height: 2),
                      Text(currentUser.email, style: const TextStyle(fontSize: 13, color: AppColors.slate500)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.skyBlueLight, borderRadius: BorderRadius.circular(4)),
                        child: const Text('FACULTY / TEACHER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.skyBlue)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight)),
            subtitle: const Text('Name, photo, phone', style: TextStyle(fontSize: 12, color: AppColors.slate500)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.slate400),
            onTap: () {
              context.push('/edit-profile');
            },
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Class schedule reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight)),
            subtitle: const Text('Notify 15m prior to scheduled sessions', style: TextStyle(fontSize: 12, color: AppColors.slate500)),
            trailing: Switch(
              value: _classReminders,
              activeColor: AppColors.skyBlue,
              onChanged: (v) {
                setState(() => _classReminders = v);
                _syncNotificationPrefs();
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Live alert broadcasts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight)),
            subtitle: const Text('Notify students automatically when starting class', style: TextStyle(fontSize: 12, color: AppColors.slate500)),
            trailing: Switch(
              value: _liveAlerts,
              activeColor: AppColors.skyBlue,
              onChanged: (v) {
                setState(() => _liveAlerts = v);
                _syncNotificationPrefs();
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Faculty Guide & Resources', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textLight)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.slate400),
            onTap: _showHelpDialog,
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final shareText = 'Join my faculty classes on Classora! Download App: https://classora.app/download\nInstitute: ${currentUser.effectiveCoachingName}';
                    Clipboard.setData(ClipboardData(text: shareText));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Classora Faculty share link copied to clipboard!')));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.skyBlue,
                    side: const BorderSide(color: AppColors.skyBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Share App', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: OutlinedButton(
                  onPressed: _showRateAppDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.skyBlue,
                    side: const BorderSide(color: AppColors.skyBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Rate Us', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Center(
            child: TextButton(
              onPressed: () async {
                final confirmed = await ConfirmDialog.show(
                  context,
                  title: 'Sign Out',
                  message: 'Are you sure you want to log out of your faculty account?',
                  confirmText: 'Sign Out',
                  isDestructive: true,
                );
                if (confirmed == true) {
                  ref.read(authStateProvider.notifier).logout();
                }
              },
              child: const Text('Sign Out', style: TextStyle(color: AppColors.liveRed, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),

          const SizedBox(height: 20),
          const Center(
            child: Text('Version 2.0.0 • Classora Education Systems', style: TextStyle(color: AppColors.slate400, fontSize: 11)),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    context.push('/help?role=TEACHER');
  }

  void _showRateAppDialog() {
    int selectedRating = 5;
    final feedbackController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rate Classora App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How is your teaching experience with Classora?',
                style: TextStyle(fontSize: 13, color: AppColors.slate500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return IconButton(
                    icon: Icon(
                      starIndex <= selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 34,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        selectedRating = starIndex;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: feedbackController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Any teaching feedback or feature suggestions? (Optional)',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.slate400),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Maybe Later', style: TextStyle(color: AppColors.slate500)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.skyBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Thank you for rating Classora $selectedRating stars! We value your feedback.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
