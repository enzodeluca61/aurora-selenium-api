class Player {
  final String? id;
  final String name;
  final DateTime? birthDate;
  final String? position;
  final int? jerseyNumber;
  final String? teamCategory;
  final bool isStaff;
  final String? userId;
  final String? matricola;
  final int? g;        // Giorno nascita (1-31)
  final int? m;        // Mese nascita (1-12)
  final int? a;        // Anno nascita
  final String? nrMatricola;  // Numero matricola
  final String? ci;    // Carta identità
  final String? rilasciata; // Data di rilascio documento

  Player({
    this.id,
    required this.name,
    this.birthDate,
    this.position,
    this.jerseyNumber,
    this.teamCategory,
    this.isStaff = false,
    this.userId,
    this.matricola,
    this.g,
    this.m,
    this.a,
    this.nrMatricola,
    this.ci,
    this.rilasciata,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'name': name,
      'birth_date': birthDate?.toIso8601String(),
      'position': position,
      'jersey_number': jerseyNumber,
      'team_category': teamCategory,
      'is_staff': isStaff,
      'user_id': userId,
      'matricola': matricola,
      'g': g,
      'm': m,
      'a': a,
      'nr_matricola': nrMatricola,
      'ci': ci,
      'rilasciata': rilasciata,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      birthDate: json['birth_date'] != null ? DateTime.parse(json['birth_date']) : null,
      position: json['position'],
      jerseyNumber: json['jersey_number'],
      teamCategory: json['team_category'],
      isStaff: json['is_staff'] ?? false,
      userId: json['user_id'],
      matricola: json['matricola'],
      g: json['g'],
      m: json['m'],
      a: json['a'],
      nrMatricola: json['nr_matricola'],
      ci: json['ci'],
      rilasciata: json['rilasciata'],
    );
  }

  Player copyWith({
    String? id,
    String? name,
    DateTime? birthDate,
    String? position,
    int? jerseyNumber,
    String? teamCategory,
    bool? isStaff,
    String? userId,
    String? matricola,
    int? g,
    int? m,
    int? a,
    String? nrMatricola,
    String? ci,
    String? rilasciata,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      position: position ?? this.position,
      jerseyNumber: jerseyNumber ?? this.jerseyNumber,
      teamCategory: teamCategory ?? this.teamCategory,
      isStaff: isStaff ?? this.isStaff,
      userId: userId ?? this.userId,
      matricola: matricola ?? this.matricola,
      g: g ?? this.g,
      m: m ?? this.m,
      a: a ?? this.a,
      nrMatricola: nrMatricola ?? this.nrMatricola,
      ci: ci ?? this.ci,
      rilasciata: rilasciata ?? this.rilasciata,
    );
  }
  
  // Getter per formattare la data di nascita come gg/mm/aa
  // Usa prima i campi separati G, M, A se disponibili, poi birthDate come fallback
  String get birthDateFormatted {
    // Se abbiamo i campi separati G, M, A
    if (g != null && m != null && a != null) {
      final day = g!.toString().padLeft(2, '0');
      final month = m!.toString().padLeft(2, '0');
      final year = (a! % 100).toString().padLeft(2, '0');
      return '$day/$month/$year';
    }
    // Fallback alla data unificata
    if (birthDate == null) return '';
    final day = birthDate!.day.toString().padLeft(2, '0');
    final month = birthDate!.month.toString().padLeft(2, '0');
    final year = (birthDate!.year % 100).toString().padLeft(2, '0');
    return '$day/$month/$year';
  }
  
  // Getter per numero matricola (usa prima nrMatricola, poi matricola come fallback)
  String? get effectiveMatricola => nrMatricola ?? matricola;
  
  // Getter per documento (matricola o carta identità)
  String? get effectiveDocument => effectiveMatricola ?? ci;
  
  // Getter per giorno nascita (priorità a g, poi birthDate)
  int? get effectiveDay => g ?? birthDate?.day;
  
  // Getter per mese nascita (priorità a m, poi birthDate)
  int? get effectiveMonth => m ?? birthDate?.month;
  
  // Getter per anno nascita (priorità a a, poi birthDate)
  int? get effectiveYear => a ?? birthDate?.year;
  
  // Getter per cognome e nome separati
  String get lastName {
    final parts = name.trim().split(' ');
    return parts.isNotEmpty ? parts.last : '';
  }
  
  String get firstName {
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return parts.sublist(0, parts.length - 1).join(' ');
    }
    return parts.isNotEmpty ? parts.first : '';
  }
}