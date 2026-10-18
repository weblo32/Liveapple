import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../batch/presentation/batch_controller.dart';
import 'study_material_tab_view.dart';

class StudyMaterialScreen extends ConsumerStatefulWidget {
  final bool isTeacher;
  final String? initialBatchId;

  const StudyMaterialScreen({
    super.key,
    this.isTeacher = false,
    this.initialBatchId,
  });

  @override
  ConsumerState<StudyMaterialScreen> createState() => _StudyMaterialScreenState();
}

class _StudyMaterialScreenState extends ConsumerState<StudyMaterialScreen> {
  String? _selectedBatchId;

  @override
  void initState() {
    super.initState();
    _selectedBatchId = widget.initialBatchId;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isTeacher = widget.isTeacher || authState.user?.role == 'TEACHER';
    final batchState = ref.watch(batchListProvider);
    final batches = batchState.batches;

    if (_selectedBatchId == null && batches.isNotEmpty) {
      _selectedBatchId = batches.first.id;
    }

    final selectedBatch = batches.isEmpty
        ? null
        : batches.firstWhere(
            (b) => b.id == _selectedBatchId,
            orElse: () => batches.first,
          );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Study Material & Notes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (selectedBatch != null)
              Text(
                'Batch: ${selectedBatch.name}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          if (batches.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list, color: Colors.white),
              tooltip: 'Select Batch',
              onSelected: (batchId) {
                setState(() => _selectedBatchId = batchId);
              },
              itemBuilder: (context) {
                return batches.map((b) {
                  return PopupMenuItem<String>(
                    value: b.id,
                    child: Row(
                      children: [
                        Icon(
                          b.id == _selectedBatchId ? Icons.check_circle : Icons.circle_outlined,
                          size: 18,
                          color: b.id == _selectedBatchId ? AppColors.primary : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b.name,
                            style: TextStyle(
                              fontWeight: b.id == _selectedBatchId ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
        ],
      ),
      body: batchState.isLoading && batches.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No batches available. Join or create a batch to access study materials.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ),
                )
              : StudyMaterialTabView(
                  key: ValueKey(_selectedBatchId),
                  batchId: _selectedBatchId ?? batches.first.id,
                  isTeacher: isTeacher,
                  batchName: selectedBatch?.name,
                ),
    );
  }
}
