import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';

class DocumentViewer extends StatefulWidget {
  final DocumentItem? initialDocument;
  final VoidCallback? onClose;
  final bool isTeacher;
  final int? syncedPage;
  final int? syncedTotalPages;
  final String? docTitle;
  final String? docPath;
  final String? docUrl;
  final bool isSharedWithStudents;
  final bool isUploading;
  final double? uploadProgress;
  final Function(int page)? onPageChanged;
  final Function(DocumentItem doc)? onDocumentChanged;
  final Function(String path, String name)? onLocalFileSelected;
  final Function({String? fetchStatus, int? bytesLoaded, String? renderError})? onDiagnosticsUpdate;

  const DocumentViewer({
    super.key,
    this.initialDocument,
    this.onClose,
    this.isTeacher = true,
    this.syncedPage,
    this.syncedTotalPages,
    this.docTitle,
    this.docPath,
    this.docUrl,
    this.isSharedWithStudents = false,
    this.isUploading = false,
    this.uploadProgress,
    this.onPageChanged,
    this.onDocumentChanged,
    this.onLocalFileSelected,
    this.onDiagnosticsUpdate,
  });

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  String? _resolvedPdfPath;
  String? _currentTitle;
  bool _isDownloading = false;
  String? _errorMessage;
  String? _errorDetail;
  int _currentPage = 0;
  int _totalPages = 1;
  bool _isPdfReady = false;
  PDFViewController? _pdfViewController;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.docTitle ?? widget.initialDocument?.fileName ?? 'PDF Presentation';
    if (widget.syncedPage != null && widget.syncedPage! > 0) {
      _currentPage = widget.syncedPage! - 1;
    }
    if (widget.syncedTotalPages != null && widget.syncedTotalPages! > 0) {
      _totalPages = widget.syncedTotalPages!;
    }
    _resolveDocument();
  }

  @override
  void didUpdateWidget(DocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.docTitle != null && widget.docTitle != _currentTitle) {
      setState(() => _currentTitle = widget.docTitle);
    }

    if (widget.syncedTotalPages != null && widget.syncedTotalPages! > 0 && widget.syncedTotalPages != _totalPages) {
      setState(() => _totalPages = widget.syncedTotalPages!);
    }

    if (!widget.isTeacher && widget.syncedPage != null) {
      final target = widget.syncedPage! - 1;
      if (target >= 0 && target != _currentPage) {
        _currentPage = target;
        _pdfViewController?.setPage(target);
        if (mounted) setState(() {});
      }
    }

    if (widget.docPath != oldWidget.docPath || widget.docUrl != oldWidget.docUrl) {
      _resolveDocument();
    }
  }

  Future<void> _resolveDocument({bool forceRefetch = false}) async {
    // 1. Check local file path first (for teacher with local file)
    if (widget.docPath != null && widget.docPath!.isNotEmpty) {
      final file = File(widget.docPath!);
      if (file.existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedPdfPath = widget.docPath;
            _isDownloading = false;
            _errorMessage = null;
            _errorDetail = null;
          });
        }
        widget.onDiagnosticsUpdate?.call(
          fetchStatus: '200 OK (Local)',
          bytesLoaded: file.lengthSync(),
        );
        return;
      }
    }

    // 2. Download from remote URL if provided (for student or remote view)
    if (widget.docUrl != null && widget.docUrl!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isDownloading = true;
          _errorMessage = null;
          _errorDetail = null;
        });
      }
      widget.onDiagnosticsUpdate?.call(fetchStatus: 'Downloading...');

      String tempPath = Directory.systemTemp.path;
      try {
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          final tempDir = await getTemporaryDirectory();
          tempPath = tempDir.path;
        }
      } catch (_) {
        tempPath = Directory.systemTemp.path;
      }
      final sanitized = widget.docUrl!.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final targetFile = File('$tempPath/slides_$sanitized.pdf');

      try {
        if (forceRefetch && targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        if (targetFile.existsSync() && targetFile.lengthSync() == 0) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }

        if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
          final dio = ApiClient().dio;
          var downloadUrl = widget.docUrl!;
          if (!downloadUrl.startsWith('http://') && !downloadUrl.startsWith('https://')) {
            var base = dio.options.baseUrl;
            while (base.endsWith('/')) {
              base = base.substring(0, base.length - 1);
            }
            var path = downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl';
            // Prevent duplicate /api when base ends with /api and path starts with /api/
            if (base.endsWith('/api') && path.startsWith('/api/')) {
              path = path.substring(4);
            }
            downloadUrl = '$base$path';
          }

          final res = await dio.download(downloadUrl, targetFile.path);
          widget.onDiagnosticsUpdate?.call(
            fetchStatus: '${res.statusCode ?? 200} OK',
            bytesLoaded: targetFile.lengthSync(),
          );
        } else {
          widget.onDiagnosticsUpdate?.call(
            fetchStatus: '200 OK (Cached)',
            bytesLoaded: targetFile.lengthSync(),
          );
        }

        if (mounted) {
          setState(() {
            _resolvedPdfPath = targetFile.path;
            _isDownloading = false;
            _errorMessage = null;
            _errorDetail = null;
          });
        }
      } catch (e) {
        debugPrint('[DOC_VIEWER] PDF download error: $e');
        try {
          if (targetFile.existsSync()) targetFile.deleteSync();
        } catch (_) {}
        const errorMsg = 'Slides load nahi ho payi';
        widget.onDiagnosticsUpdate?.call(
          fetchStatus: 'Error',
          renderError: e.toString(),
        );
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = errorMsg;
            _errorDetail = e.toString();
          });
        }
      }
      return;
    }

    // 3. For students when presentation is open but URL is still pending
    if (!widget.isTeacher && (widget.docTitle != null && widget.docTitle!.isNotEmpty)) {
      if (mounted) {
        setState(() {
          _isDownloading = true;
          _errorMessage = null;
        });
      }
      widget.onDiagnosticsUpdate?.call(fetchStatus: 'Connecting to slide stream...');
      return;
    }
  }

  Future<void> _pickLocalDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'ppt', 'pptx'],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final nameLower = file.name.toLowerCase();
        if (nameLower.endsWith('.ppt') || nameLower.endsWith('.pptx')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PPT ko PDF me export karo ya screen share karo'),
                backgroundColor: AppColors.rose,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        if (file.path != null) {
          setState(() {
            _resolvedPdfPath = file.path;
            _currentTitle = file.name;
            _isPdfReady = false;
            _currentPage = 0;
            _errorMessage = null;
          });
          widget.onLocalFileSelected?.call(file.path!, file.name);
          widget.onPageChanged?.call(1);
        }
      }
    } catch (e) {
      debugPrint('[DOC_PICKER] Error picking document: $e');
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      final target = _currentPage - 1;
      _pdfViewController?.setPage(target);
      setState(() => _currentPage = target);
      if (widget.isTeacher) {
        widget.onPageChanged?.call(target + 1);
      }
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      final target = _currentPage + 1;
      _pdfViewController?.setPage(target);
      setState(() => _currentPage = target);
      if (widget.isTeacher) {
        widget.onPageChanged?.call(target + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.slate900,
      child: Column(
        children: [
          // Top Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.slate800,
              border: Border(bottom: BorderSide(color: AppColors.slate700)),
            ),
            child: Row(
              children: [
                if (widget.onClose != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClose,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.indigo600.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: AppColors.indigo400,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),

                // Document Title & Page Count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentTitle ?? 'PDF Presentation',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isPdfReady
                            ? 'Page ${_currentPage + 1} of $_totalPages'
                            : (_isDownloading ? 'Downloading...' : 'PDF Presentation'),
                        style: const TextStyle(
                          color: AppColors.indigo300,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Teacher Upload Progress or Shared Status Badge
                if (widget.isTeacher && widget.isUploading)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Uploading ${widget.uploadProgress != null ? (widget.uploadProgress! * 100).toInt() : 0}%',
                          style: const TextStyle(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (widget.isTeacher && widget.isSharedWithStudents)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.emerald, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Shared with students',
                          style: TextStyle(color: AppColors.emerald, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                if (widget.isTeacher)
                  IconButton(
                    icon: const Icon(Icons.upload_file_rounded, color: AppColors.indigo300, size: 20),
                    tooltip: 'Change PDF File',
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    onPressed: _pickLocalDocument,
                  ),
              ],
            ),
          ),

          // Main Presentation Stage
          Expanded(
            child: _buildMainStage(),
          ),

          // Bottom Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.slate800,
              border: Border(top: BorderSide(color: AppColors.slate700)),
            ),
            child: widget.isTeacher
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _currentPage > 0 ? _prevPage : null,
                        icon: const Icon(Icons.arrow_back_rounded, size: 14),
                        label: const Text('Previous', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.slate700,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.slate800,
                          disabledForegroundColor: AppColors.slate600,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      Text(
                        'Page ${_currentPage + 1} of $_totalPages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: const Text('Next Page', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.indigo600,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.slate800,
                          disabledForegroundColor: AppColors.slate600,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync_rounded, color: AppColors.indigo400, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Live Presentation • Page ${_currentPage + 1} of $_totalPages',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStage() {
    if (_isDownloading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.indigo400),
            SizedBox(height: 16),
            Text(
              'PDF slides download ho rahi hain...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (_errorDetail != null && _errorDetail!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _errorDetail!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.slate400, fontSize: 11),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _resolveDocument(forceRefetch: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Dobara koshish karein'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (widget.isTeacher) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickLocalDocument,
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Device se dusri PDF chunein'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppColors.slate600),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_resolvedPdfPath != null) {
      return Stack(
        children: [
          PDFView(
            key: ValueKey(_resolvedPdfPath),
            filePath: _resolvedPdfPath!,
            enableSwipe: widget.isTeacher,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: _currentPage,
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false,
            onRender: (pages) {
              if (mounted) {
                setState(() {
                  _totalPages = (pages != null && pages > 0)
                      ? pages
                      : (widget.syncedTotalPages ?? _totalPages);
                  _isPdfReady = true;
                });
                widget.onDiagnosticsUpdate?.call(
                  renderError: null,
                  bytesLoaded: _resolvedPdfPath != null ? File(_resolvedPdfPath!).lengthSync() : null,
                );
              }
            },
            onViewCreated: (PDFViewController controller) {
              _pdfViewController = controller;
              if (_currentPage > 0) {
                controller.setPage(_currentPage);
              }
            },
            onPageChanged: (page, total) {
              if (page != null && page != _currentPage) {
                if (mounted) {
                  setState(() {
                    _currentPage = page;
                    if (total != null && total > 0) _totalPages = total;
                  });
                }
                if (widget.isTeacher) {
                  widget.onPageChanged?.call(page + 1);
                }
              }
            },
            onError: (error) {
              debugPrint('[PDFView] Error: $error');
              widget.onDiagnosticsUpdate?.call(renderError: error.toString());
              if (mounted) {
                setState(() => _errorMessage = 'Slides load nahi ho payi');
              }
            },
            onPageError: (page, error) {
              debugPrint('[PDFView] Page $page error: $error');
              widget.onDiagnosticsUpdate?.call(renderError: 'Page $page: $error');
            },
          ),
          if (!_isPdfReady)
            Container(
              color: AppColors.slate900,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.indigo400),
              ),
            ),
        ],
      );
    }

    // No PDF loaded yet
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.slate800,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.slate700),
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                color: AppColors.indigo400,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isTeacher ? 'Koi PDF select nahi hai' : 'Waiting for Teacher\'s Slides',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isTeacher
                  ? 'Apne device se PDF presentation chunein aur live class me padhayein'
                  : 'Teacher jab PDF present karenge, yahan real PDF pages display ho jayenge',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.slate400, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (widget.isTeacher)
              ElevatedButton.icon(
                onPressed: _pickLocalDocument,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Select PDF Document'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
