import 'package:flutter/material.dart';

enum MatchStatus {
  notStarted,   // Non iniziata (grigio)
  inProgress,   // In corso (rosso)
  finished,     // Finita (nero)
  postponed,    // Rinviata (arancione)
}

class MatchResult {
  final String? id;
  final String homeTeam;
  final String awayTeam;
  final int homeScore;
  final int awayScore;
  final DateTime matchDate;
  final String? championship;
  final String? category; // U21, U19, ecc.
  final String? round; // Giornata
  final String? venue;
  final String? userId;
  final int? homePosition; // Posizione in classifica squadra di casa
  final int? awayPosition; // Posizione in classifica squadra ospite
  final MatchStatus status;

  MatchResult({
    this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeScore,
    required this.awayScore,
    required this.matchDate,
    this.championship,
    this.category,
    this.round,
    this.venue,
    this.userId,
    this.homePosition,
    this.awayPosition,
    this.status = MatchStatus.notStarted,
  });

  // Getter per determinare il risultato
  String get result {
    if (homeScore > awayScore) {
      return 'Casa';
    } else if (awayScore > homeScore) {
      return 'Fuori';
    } else {
      return 'Pareggio';
    }
  }

  // Getter per il punteggio formattato
  String get score => '$homeScore - $awayScore';

  // Getter per determinare se Aurora Seriate ha vinto
  bool get isAuroraWin {
    final auroraAtHome = homeTeam.toLowerCase().contains('aurora');
    final auroraAway = awayTeam.toLowerCase().contains('aurora');

    if (auroraAtHome && homeScore > awayScore) return true;
    if (auroraAway && awayScore > homeScore) return true;
    return false;
  }

  // Getter per determinare se è un pareggio di Aurora
  bool get isAuroraDraw {
    final isAuroraPlaying = homeTeam.toLowerCase().contains('aurora') ||
                           awayTeam.toLowerCase().contains('aurora');
    return isAuroraPlaying && homeScore == awayScore;
  }

  // Getter per determinare automaticamente lo stato della partita
  MatchStatus get autoStatus {
    final now = DateTime.now();
    final matchStart = matchDate;
    final matchEnd = matchDate.add(const Duration(minutes: 95)); // 90' + 5' recupero

    // Se la partita è rinviata (punteggio speciale o note)
    if (homeScore == 0 && awayScore == 0 && venue?.toLowerCase().contains('rinv') == true) {
      return MatchStatus.postponed;
    }

    // Se la partita è finita (dopo l'orario di fine stimato)
    if (now.isAfter(matchEnd)) {
      return MatchStatus.finished;
    }

    // Se la partita è in corso (dopo l'orario di inizio)
    if (now.isAfter(matchStart) && now.isBefore(matchEnd)) {
      return MatchStatus.inProgress;
    }

    // Altrimenti non è ancora iniziata
    return MatchStatus.notStarted;
  }

  // Getter per il colore dello stato
  Color get statusColor {
    switch (status) {
      case MatchStatus.notStarted:
        return const Color(0xFF9E9E9E); // Grigio
      case MatchStatus.inProgress:
        return const Color(0xFFE53935); // Rosso
      case MatchStatus.finished:
        return const Color(0xFF212121); // Nero
      case MatchStatus.postponed:
        return const Color(0xFFFF9800); // Arancione
    }
  }

  // Getter per il testo dello stato
  String get statusText {
    switch (status) {
      case MatchStatus.notStarted:
        return 'Non iniziata';
      case MatchStatus.inProgress:
        return 'In corso';
      case MatchStatus.finished:
        return 'Finita';
      case MatchStatus.postponed:
        return 'Rinviata';
    }
  }

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    MatchStatus status = MatchStatus.notStarted;
    if (json['status'] != null) {
      switch (json['status']) {
        case 'in_progress':
          status = MatchStatus.inProgress;
          break;
        case 'finished':
          status = MatchStatus.finished;
          break;
        case 'postponed':
          status = MatchStatus.postponed;
          break;
        default:
          status = MatchStatus.notStarted;
      }
    }

    return MatchResult(
      id: json['id']?.toString(),
      homeTeam: json['home_team'] ?? '',
      awayTeam: json['away_team'] ?? '',
      homeScore: json['home_score'] ?? 0,
      awayScore: json['away_score'] ?? 0,
      matchDate: DateTime.parse(json['match_date']),
      championship: json['championship'],
      category: json['category'],
      round: json['round'],
      venue: json['venue'],
      userId: json['user_id'],
      homePosition: json['home_position'],
      awayPosition: json['away_position'],
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    String statusString;
    switch (status) {
      case MatchStatus.inProgress:
        statusString = 'in_progress';
        break;
      case MatchStatus.finished:
        statusString = 'finished';
        break;
      case MatchStatus.postponed:
        statusString = 'postponed';
        break;
      default:
        statusString = 'not_started';
    }

    return {
      if (id != null) 'id': id,
      'home_team': homeTeam,
      'away_team': awayTeam,
      'home_score': homeScore,
      'away_score': awayScore,
      'match_date': matchDate.toIso8601String(),
      'championship': championship,
      'category': category,
      'round': round,
      'venue': venue,
      'home_position': homePosition,
      'away_position': awayPosition,
      'status': statusString,
      if (userId != null) 'user_id': userId,
    };
  }

  MatchResult copyWith({
    String? id,
    String? homeTeam,
    String? awayTeam,
    int? homeScore,
    int? awayScore,
    DateTime? matchDate,
    String? championship,
    String? category,
    String? round,
    String? venue,
    String? userId,
    int? homePosition,
    int? awayPosition,
    MatchStatus? status,
  }) {
    return MatchResult(
      id: id ?? this.id,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      matchDate: matchDate ?? this.matchDate,
      championship: championship ?? this.championship,
      category: category ?? this.category,
      round: round ?? this.round,
      venue: venue ?? this.venue,
      userId: userId ?? this.userId,
      homePosition: homePosition ?? this.homePosition,
      awayPosition: awayPosition ?? this.awayPosition,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'MatchResult{homeTeam: $homeTeam, awayTeam: $awayTeam, score: $score, date: $matchDate}';
  }
}