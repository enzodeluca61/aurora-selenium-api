class Match {
  final String? id;
  final String opponent;
  final DateTime date;
  final String time;
  final String location;
  final bool isHome;
  final bool isRest; // true se è una giornata di riposo
  final String? notes;
  final String? userId;
  final String matchType; // campionato, torneo, coppa, amichevole
  final String? auroraTeam; // squadra Aurora (es. JUNIORES)
  final int? goalsAurora; // goal Aurora
  final int? goalsOpponent; // goal avversari
  final bool includeInPlanning; // se includere nel planning
  final String? giornata; // giornata di campionato (es. "1A", "2R")

  Match({
    this.id,
    required this.opponent,
    required this.date,
    required this.time,
    required this.location,
    this.isHome = true,
    this.isRest = false,
    this.notes,
    this.userId,
    this.matchType = 'campionato',
    this.auroraTeam,
    this.goalsAurora,
    this.goalsOpponent,
    this.includeInPlanning = true,
    this.giornata,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'opponent': opponent,
      'date': date.toIso8601String(),
      'time': time,
      'location': location,
      'is_home': isHome,
      'is_rest': isRest,
      'user_id': userId,
      'match_type': matchType,
      'aurora_team': auroraTeam,
      'goals_aurora': goalsAurora,
      'goals_opponent': goalsOpponent,
      'include_in_planning': includeInPlanning,
      'giornata': giornata,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    // Solo aggiungere id se non è null (per gli update)
    if (id != null) {
      json['id'] = id;
    }
    
    // Solo aggiungere notes se non è null o vuoto
    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes;
    }
    
    return json;
  }

  factory Match.fromJson(Map<String, dynamic> json) {
    try {
      // Gestione sicura del campo giornata
      String? giornata;
      try {
        if (json['giornata'] != null) {
          giornata = json['giornata'].toString();
        }
      } catch (e) {
        // Se c'è un errore nel parsing di giornata, ignora e continua
        giornata = null;
      }

      return Match(
        id: json['id']?.toString(),
        opponent: json['opponent'] ?? '',
        date: DateTime.parse(json['date']),
        time: json['time'] ?? '',
        location: json['location'] ?? '',
        isHome: json['is_home'] ?? true,
        isRest: json['is_rest'] ?? false,
        notes: json['notes'],
        userId: json['user_id'],
        matchType: json['match_type'] ?? 'campionato',
        auroraTeam: json['aurora_team'],
        goalsAurora: json['goals_aurora'],
        goalsOpponent: json['goals_opponent'],
        includeInPlanning: json['include_in_planning'] ?? true,
        giornata: giornata,
      );
    } catch (e) {
      // Fallback in caso di errori gravi
      rethrow;
    }
  }

  Match copyWith({
    String? id,
    String? opponent,
    DateTime? date,
    String? time,
    String? location,
    bool? isHome,
    bool? isRest,
    String? notes,
    String? userId,
    String? matchType,
    String? auroraTeam,
    int? goalsAurora,
    int? goalsOpponent,
    bool? includeInPlanning,
    String? giornata,
  }) {
    return Match(
      id: id ?? this.id,
      opponent: opponent ?? this.opponent,
      date: date ?? this.date,
      time: time ?? this.time,
      location: location ?? this.location,
      isHome: isHome ?? this.isHome,
      isRest: isRest ?? this.isRest,
      notes: notes ?? this.notes,
      userId: userId ?? this.userId,
      matchType: matchType ?? this.matchType,
      auroraTeam: auroraTeam ?? this.auroraTeam,
      goalsAurora: goalsAurora ?? this.goalsAurora,
      goalsOpponent: goalsOpponent ?? this.goalsOpponent,
      includeInPlanning: includeInPlanning ?? this.includeInPlanning,
      giornata: giornata ?? this.giornata,
    );
  }
}