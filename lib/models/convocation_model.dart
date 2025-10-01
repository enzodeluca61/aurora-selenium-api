class Convocation {
  final String? id;
  final String? matchId;
  final String playerId;
  final String playerName;
  final bool isConvocated;
  final DateTime? convocatedAt;
  final String? userId;
  final String? notes;
  final String? meetingTime; // Orario di ritrovo
  final String? equipment; // Dotazione richiesta

  Convocation({
    this.id,
    this.matchId,
    required this.playerId,
    required this.playerName,
    this.isConvocated = false,
    this.convocatedAt,
    this.userId,
    this.notes,
    this.meetingTime,
    this.equipment,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'player_id': playerId,
      'player_name': playerName,
      'is_convocated': isConvocated,
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    if (id != null) {
      json['id'] = id;
    }
    
    if (matchId != null) {
      json['match_id'] = matchId;
    }
    
    if (convocatedAt != null) {
      json['convocated_at'] = convocatedAt!.toIso8601String();
    }
    
    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes;
    }
    
    if (meetingTime != null && meetingTime!.isNotEmpty) {
      json['meeting_time'] = meetingTime;
    }
    
    if (equipment != null && equipment!.isNotEmpty) {
      json['equipment'] = equipment;
    }
    
    return json;
  }

  factory Convocation.fromJson(Map<String, dynamic> json) {
    return Convocation(
      id: json['id']?.toString(),
      matchId: json['match_id']?.toString(),
      playerId: json['player_id'] ?? '',
      playerName: json['player_name'] ?? '',
      isConvocated: json['is_convocated'] ?? false,
      convocatedAt: json['convocated_at'] != null 
          ? DateTime.parse(json['convocated_at'])
          : null,
      userId: json['user_id'],
      notes: json['notes'],
      meetingTime: json['meeting_time'],
      equipment: json['equipment'],
    );
  }

  Convocation copyWith({
    String? id,
    String? matchId,
    String? playerId,
    String? playerName,
    bool? isConvocated,
    DateTime? convocatedAt,
    String? userId,
    String? notes,
    String? meetingTime,
    String? equipment,
  }) {
    return Convocation(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      isConvocated: isConvocated ?? this.isConvocated,
      convocatedAt: convocatedAt ?? this.convocatedAt,
      userId: userId ?? this.userId,
      notes: notes ?? this.notes,
      meetingTime: meetingTime ?? this.meetingTime,
      equipment: equipment ?? this.equipment,
    );
  }
}