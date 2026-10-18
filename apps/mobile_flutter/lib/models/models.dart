import 'package:flutter/material.dart';
export 'slide_deck_model.dart';

class UserSession {
  final String id;
  final String name;
  final String email;
  final String role; // 'student' | 'teacher'
  final String batchOrDept;
  final String avatar;

  const UserSession({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.batchOrDept,
    this.avatar = 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=100&h=100&fit=crop',
  });

  UserSession copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? batchOrDept,
    String? avatar,
  }) {
    return UserSession(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      batchOrDept: batchOrDept ?? this.batchOrDept,
      avatar: avatar ?? this.avatar,
    );
  }
}

class CourseItem {
  final String id;
  final String title;
  final String subject;
  final String instructor;
  final int progress;
  final String image;
  final String description;

  const CourseItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.instructor,
    required this.progress,
    required this.image,
    this.description = '',
  });
}

class LiveClassItem {
  final String id;
  final String title;
  final String teacher;
  final String subject;
  final String time;
  final bool isLive;
  final int enrolledCount;

  const LiveClassItem({
    required this.id,
    required this.title,
    required this.teacher,
    required this.subject,
    required this.time,
    required this.isLive,
    this.enrolledCount = 34,
  });
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String message;
  final String timestamp;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.timestamp,
  });
}

class DoubtItem {
  final String id;
  final String studentName;
  final String studentId;
  final String question;
  final String timestamp;
  final bool isResolved;

  const DoubtItem({
    required this.id,
    required this.studentName,
    required this.studentId,
    required this.question,
    required this.timestamp,
    this.isResolved = false,
  });

  DoubtItem copyWith({
    String? id,
    String? studentName,
    String? studentId,
    String? question,
    String? timestamp,
    bool? isResolved,
  }) {
    return DoubtItem(
      id: id ?? this.id,
      studentName: studentName ?? this.studentName,
      studentId: studentId ?? this.studentId,
      question: question ?? this.question,
      timestamp: timestamp ?? this.timestamp,
      isResolved: isResolved ?? this.isResolved,
    );
  }
}

class ParticipantItem {
  final String id;
  final String name;
  final String role;
  final String rollNo;
  final String avatar;
  final bool isHandRaised;
  final bool isMicOn;
  final bool isVideoOn;

  const ParticipantItem({
    required this.id,
    required this.name,
    required this.role,
    required this.rollNo,
    this.avatar = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop',
    this.isHandRaised = false,
    this.isMicOn = false,
    this.isVideoOn = true,
  });

  ParticipantItem copyWith({
    String? id,
    String? name,
    String? role,
    String? rollNo,
    String? avatar,
    bool? isHandRaised,
    bool? isMicOn,
    bool? isVideoOn,
  }) {
    return ParticipantItem(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      rollNo: rollNo ?? this.rollNo,
      avatar: avatar ?? this.avatar,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      isMicOn: isMicOn ?? this.isMicOn,
      isVideoOn: isVideoOn ?? this.isVideoOn,
    );
  }
}

class PresentationPage {
  final int pageNumber;
  final String title;
  final String subtitle;
  final List<String> points;
  final String formula;
  final String diagramUrl;

  const PresentationPage({
    required this.pageNumber,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.formula,
    required this.diagramUrl,
  });
}

class DocumentItem {
  final String id;
  final String title;
  final String fileName;
  final String author;
  final String type; // 'PPT Presentation' | 'PDF Document'
  final List<PresentationPage> slides;

  const DocumentItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.author,
    required this.type,
    required this.slides,
  });
}

class DrawingPoint {
  final Offset point;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  const DrawingPoint({
    required this.point,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });
}
