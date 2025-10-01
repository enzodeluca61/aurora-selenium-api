enum AttendanceStatus {
  present('P', 'Presente', 'green'),
  absent('AG', 'Assenza Giustificata', 'orange'),
  absentUnexcused('AI', 'Assenza Ingiustificata', 'red'),
  sick('AM', 'Ammalato', 'blue'),
  injured('AIN', 'Infortunato', 'purple'),
  suspended('ASQ', 'Squalificato', 'grey');

  const AttendanceStatus(this.code, this.label, this.color);
  
  final String code;
  final String label;
  final String color;

  static AttendanceStatus fromCode(String code) {
    return AttendanceStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => AttendanceStatus.absent,
    );
  }
}

class Attendance {
  final String? id;
  final String playerId;
  final DateTime date;
  final AttendanceStatus status;
  final String? notes;

  Attendance({
    this.id,
    required this.playerId,
    required this.date,
    required this.status,
    this.notes,
  });

  Map<String, dynamic> toJson({bool includeId = false}) {
    final json = {
      'player_id': playerId,
      'date': date.toIso8601String().split('T')[0], // Only date part
      'status': status.code,
      'notes': notes,
    };
    
    if (includeId && id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id']?.toString(),
      playerId: json['player_id']?.toString() ?? '',
      date: DateTime.parse(json['date']),
      status: AttendanceStatus.fromCode(json['status'] ?? 'AG'),
      notes: json['notes'],
    );
  }
}