class Training {
  final String? id;
  final String teamCategory; // categoria squadra
  final int weekday; // 1=lunedì, 2=martedì, ..., 5=venerdì
  final String startTime; // es. "18:00"
  final String endTime; // es. "19:30"
  final String fieldCode; // sigla campo
  final DateTime weekStart; // inizio settimana (lunedì)
  final String? userId;
  final bool hasGoalkeeper; // se include allenamento portieri

  Training({
    this.id,
    required this.teamCategory,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.fieldCode,
    required this.weekStart,
    this.userId,
    this.hasGoalkeeper = false,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'team_category': teamCategory,
      'weekday': weekday,
      'start_time': startTime,
      'end_time': endTime,
      'field_code': fieldCode,
      'week_start': weekStart.toIso8601String().split('T')[0],
      'user_id': userId,
      'is_portieri': hasGoalkeeper,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    // Includi sempre l'ID se esiste
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  factory Training.fromJson(Map<String, dynamic> json) {
    return Training(
      id: json['id']?.toString(),
      teamCategory: json['team_category'] ?? '',
      weekday: json['weekday'] ?? 1,
      startTime: json['start_time'] ?? '18:00',
      endTime: json['end_time'] ?? '19:30',
      fieldCode: json['field_code'] ?? '',
      weekStart: DateTime.parse(json['week_start']),
      userId: json['user_id'],
      hasGoalkeeper: json['is_portieri'] ?? false,
    );
  }

  Training copyWith({
    String? id,
    bool clearId = false,
    String? teamCategory,
    int? weekday,
    String? startTime,
    String? endTime,
    String? fieldCode,
    DateTime? weekStart,
    String? userId,
    bool? hasGoalkeeper,
  }) {
    return Training(
      id: clearId ? null : (id ?? this.id),
      teamCategory: teamCategory ?? this.teamCategory,
      weekday: weekday ?? this.weekday,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      fieldCode: fieldCode ?? this.fieldCode,
      weekStart: weekStart ?? this.weekStart,
      userId: userId ?? this.userId,
      hasGoalkeeper: hasGoalkeeper ?? this.hasGoalkeeper,
    );
  }

  String get weekdayName {
    switch (weekday) {
      case 1: return 'Lunedì';
      case 2: return 'Martedì';
      case 3: return 'Mercoledì';
      case 4: return 'Giovedì';
      case 5: return 'Venerdì';
      default: return 'Lunedì';
    }
  }
}