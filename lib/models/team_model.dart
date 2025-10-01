class Team {
  final String? id;
  final String category; // categoria in maiuscolo (es. JUNIORES, ALLIEVI, etc.)
  final String? userId;
  final int sortOrder;
  final String? abbreviation; // abbreviazione a 3 lettere
  final String? year; // anno
  final String? girone; // girone di appartenenza

  Team({
    this.id,
    required this.category,
    this.userId,
    this.sortOrder = 0,
    this.abbreviation,
    this.year,
    this.girone,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'category': category,
      'user_id': userId,
      'sort_order': sortOrder,
      'created_at': DateTime.now().toIso8601String(),
    };

    // Solo aggiungere id se non è null (per gli update)
    if (id != null) {
      json['id'] = id;
    }

    if (abbreviation != null) {
      json['abbreviation'] = abbreviation;
    }

    if (year != null) {
      json['year'] = year;
    }

    if (girone != null) {
      json['girone'] = girone;
    }

    return json;
  }

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id']?.toString(),
      category: json['category'] ?? '', // teams table usa 'category'
      userId: json['user_id'],
      sortOrder: json['sort_order'] ?? 0,
      abbreviation: json['abbreviation'],
      year: json['year'],
      girone: json['girone'],
    );
  }

  Team copyWith({
    String? id,
    String? category,
    String? userId,
    int? sortOrder,
    String? abbreviation,
    String? year,
    String? girone,
  }) {
    return Team(
      id: id ?? this.id,
      category: category ?? this.category,
      userId: userId ?? this.userId,
      sortOrder: sortOrder ?? this.sortOrder,
      abbreviation: abbreviation ?? this.abbreviation,
      year: year ?? this.year,
      girone: girone ?? this.girone,
    );
  }
}