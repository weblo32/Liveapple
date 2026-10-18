class SlideDeckModel {
  final String deckId;
  final String? classId;
  final bool isOpen;
  final String fileName;
  final String title;
  final int totalPages;
  final int currentPage;
  final String? fileHash;
  final String? url;
  final String? streamUrl;
  final String stage;

  const SlideDeckModel({
    required this.deckId,
    this.classId,
    this.isOpen = true,
    required this.fileName,
    required this.title,
    required this.totalPages,
    this.currentPage = 1,
    this.fileHash,
    this.url,
    this.streamUrl,
    this.stage = 'SLIDES',
  });

  factory SlideDeckModel.fromJson(Map<String, dynamic> json) {
    // Contract mapping handles totalPages vs pageCount vs total_pages, deckId vs id vs fileKey
    final rawDeckId = json['deckId'] ?? json['id'] ?? json['fileKey'] ?? '';
    final rawFileName = json['fileName'] ?? json['title'] ?? 'Document Presentation';
    final rawTotalPages = (json['totalPages'] ?? json['pageCount'] ?? json['total_pages'] as num?)?.toInt() ?? 1;
    final rawCurrentPage = (json['currentPage'] ?? json['page'] as num?)?.toInt() ?? 1;
    final rawUrl = json['url'] ?? json['streamUrl'] ?? json['fileUrl'] ?? json['path'];

    return SlideDeckModel(
      deckId: rawDeckId.toString(),
      classId: json['classId']?.toString(),
      isOpen: json['isOpen'] as bool? ?? true,
      fileName: rawFileName.toString(),
      title: (json['title'] ?? rawFileName).toString(),
      totalPages: rawTotalPages > 0 ? rawTotalPages : 1,
      currentPage: rawCurrentPage > 0 ? rawCurrentPage : 1,
      fileHash: json['fileHash']?.toString(),
      url: rawUrl?.toString(),
      streamUrl: (json['streamUrl'] ?? rawUrl)?.toString(),
      stage: (json['stage'] ?? json['mode'] ?? 'SLIDES').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'classId': classId,
    'isOpen': isOpen,
    'fileName': fileName,
    'title': title,
    'totalPages': totalPages,
    'currentPage': currentPage,
    'page': currentPage,
    'fileHash': fileHash,
    'url': url,
    'streamUrl': streamUrl,
    'stage': stage,
  };
}
