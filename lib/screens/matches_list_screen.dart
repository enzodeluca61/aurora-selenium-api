import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart'; // Added
import 'package:share_plus/share_plus.dart'; // Added
import 'dart:io'; // Added
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_model.dart';
import '../services/match_service.dart';
import '../services/field_service.dart';
import '../services/team_service.dart';
import '../models/field_model.dart';
import '../models/team_model.dart';
import '../widgets/match_form_dialog.dart';
import '../services/instagram_results_service.dart';
import '../services/instagram_weekend_service.dart';
import '../widgets/instagram_results_preview_widget.dart';

class MatchesListScreen extends StatefulWidget {
  const MatchesListScreen({super.key});

  @override
  State<MatchesListScreen> createState() => _MatchesListScreenState();
}

class _MatchesListScreenState extends State<MatchesListScreen> {
  DateTime _currentWeekStart = DateTime.now();
  List<Match>? _optimizedWeeklyMatches;
  bool _isLoadingWeeklyMatches = false;
  bool _showOnlyAgoristiche = true; // Default selezionato

  // Cache globale per i loghi per migliorare le performance
  static final Map<String, pw.MemoryImage?> _logoCache = {};
  
  @override
  void initState() {
    super.initState();
    
    // Imposta la settimana attuale, ma se è domenica va alla settimana successiva
    final now = DateTime.now();
    _currentWeekStart = _getWeekStart(now);

    // Se oggi è domenica (weekday = 7), sposta alla settimana successiva
    if (now.weekday == 7) {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    }
    
    // Load weekly matches with optimized loading
    _loadOptimizedWeeklyMatches();

    // Carica i campi se non sono già stati caricati
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldService = context.read<FieldService>();

      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields();
      }
    });
  }

  // Load optimized weekly matches
  Future<void> _loadOptimizedWeeklyMatches() async {
    if (_isLoadingWeeklyMatches) return;

    setState(() {
      _isLoadingWeeklyMatches = true;
    });

    try {
      final matchService = context.read<MatchService>();
      final weeklyMatches = await matchService.loadWeeklyMatches(_currentWeekStart);

      if (mounted) {
        setState(() {
          _optimizedWeeklyMatches = weeklyMatches;
          _isLoadingWeeklyMatches = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingWeeklyMatches = false;
        });
      }
    }
  }

  DateTime _getWeekStart(DateTime date) {
    final dayOfWeek = date.weekday;
    return DateTime(date.year, date.month, date.day - (dayOfWeek - 1));
  }

  /// Determina se una squadra è agonistica
  bool _isAgoristicTeam(String? auroraTeam) {
    if (auroraTeam == null || auroraTeam.isEmpty) return false;

    final team = auroraTeam.toUpperCase();

    // Squadre agonistiche (categorie senior e giovanili agonistiche)
    const agonistiche = [
      'PRIMA SQUADRA',
      'JUNIORES',
      'JUNIORES NAZIONALE',
      'JUNIORES REGIONALE',
      'ALLIEVI REGIONALI',
      'ALLIEVI ELITE',
      'PRIMA',
      'SECONDA',
      'TERZA',
      'SENIOR',
      'U21',
      'U19',
      'U18',
      'U17',
      'U16',
      'U15',
      'U14',
      'UNDER 21',
      'UNDER 19',
      'UNDER 18',
      'UNDER 17',
      'UNDER 16',
      'UNDER 15',
      'UNDER 14',
    ];

    // Escludi squadre di promozione
    if (team.contains('PROMOZIONE')) {
      return false;
    }

    // Controlla se la squadra è nelle categorie agonistiche
    for (final categoria in agonistiche) {
      if (team.contains(categoria)) {
        return true;
      }
    }

    // Tutte le altre sono considerate attività di base
    return false;
  }

  List<Match> _getMatchesForWeek(List<Match> matches) {
    final weekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day, 0, 0, 0);
    final weekEnd = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day + 6, 23, 59, 59);

    var filteredMatches = matches.where((match) {
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndDate = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);

      final isInWeek = (matchDate.isAtSameMomentAs(weekStartDate) || matchDate.isAfter(weekStartDate)) &&
                       (matchDate.isAtSameMomentAs(weekEndDate) || matchDate.isBefore(weekEndDate));

      // Filtra per agonistiche se la checkbox è selezionata
      if (_showOnlyAgoristiche) {
        return isInWeek && _isAgoristicTeam(match.auroraTeam);
      }

      return isInWeek;
    }).toList();

    return filteredMatches;
  }

  /// Ottiene TUTTE le partite della settimana senza filtro AGO (per weekend results)
  List<Match> _getAllMatchesForWeek(List<Match> matches) {
    final weekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day, 0, 0, 0);
    final weekEnd = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day + 6, 23, 59, 59);

    return matches.where((match) {
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndDate = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);

      return (matchDate.isAtSameMomentAs(weekStartDate) || matchDate.isAfter(weekStartDate)) &&
             (matchDate.isAtSameMomentAs(weekEndDate) || matchDate.isBefore(weekEndDate));
    }).toList();
  }

  // Funzione helper per formattare l'orario in formato HH:MM
  String _formatTime(String time) {
    // Rimuove secondi e altri caratteri non necessari, mantiene solo hh:mm
    final cleanTime = time.replaceAll(RegExp(r'[^0-9:]+'), '');
    if (cleanTime.contains(':')) {
      final parts = cleanTime.split(':');
      if (parts.length >= 2) {
        return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
      }
    }
    return cleanTime.isEmpty ? time : cleanTime;
  }

  List<Match> _getMatchesForWeekPDF(List<Match> matches) {
    final weekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day, 0, 0, 0);
    final weekEnd = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day + 6, 23, 59, 59);

    // Prima filtra le partite esistenti
    List<Match> filteredMatches = matches.where((match) {
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final weekEndDate = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);

      final isInWeek = (matchDate.isAtSameMomentAs(weekStartDate) || matchDate.isAfter(weekStartDate)) &&
                       (matchDate.isAtSameMomentAs(weekEndDate) || matchDate.isBefore(weekEndDate));

      // Filtra per settimana E per includeInPlanning E per agonistiche se selezionato
      bool passesFilters = isInWeek && match.includeInPlanning;

      if (_showOnlyAgoristiche) {
        passesFilters = passesFilters && _isAgoristicTeam(match.auroraTeam);
      }

      return passesFilters;
    }).toList();
    
    print('=== FILTRO PARTITE SETTIMANA ===');
    print('Partite totali nel sistema: ${matches.length}');
    print('Partite filtrate per settimana: ${filteredMatches.length}');
    print('Settimana: $weekStart - $weekEnd');
    for (int i = 0; i < filteredMatches.length; i++) {
      final match = filteredMatches[i];
      print('${i+1}. ${match.opponent} - ${match.date} ${_formatTime(match.time)} - Planning: ${match.includeInPlanning}');
    }
    print('===============================');
    
    return filteredMatches;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'WEEKLY MATCHES',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 13,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.article, color: Colors.white),
            onPressed: () => _previewExtendedPDF(),
            tooltip: 'Weekly Matches PDF',
          ),
          IconButton(
            icon: const Icon(Icons.image, color: Colors.white),
            onPressed: () => _showInstagramResultsPreview(),
            tooltip: 'Anteprima Risultati Instagram',
          ),
          IconButton(
            icon: const Icon(Icons.weekend, color: Colors.white),
            onPressed: () => _showInstagramWeekendPreview(),
            tooltip: 'Anteprima Risultati Weekend',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Container principale con selettore settimana e checkbox AGO
            Container(
              margin: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Selettore settimana
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withAlpha(51),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
                        _optimizedWeeklyMatches = null; // Clear cache
                      });
                      _loadOptimizedWeeklyMatches(); // Load new week
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)))}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
                              _optimizedWeeklyMatches = null; // Clear cache
                            });
                            _loadOptimizedWeeklyMatches(); // Load new week
                          },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Checkbox AGO fissa a destra
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A8A), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _showOnlyAgoristiche,
                          onChanged: (value) {
                            setState(() {
                              _showOnlyAgoristiche = value ?? true;
                              _optimizedWeeklyMatches = null; // Clear cache
                            });
                            _loadOptimizedWeeklyMatches(); // Reload matches
                          },
                          activeColor: const Color(0xFF1E3A8A),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        const Text(
                          'AGO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Lista partite
            Expanded(
              child: Consumer2<MatchService, FieldService>(
                builder: (context, matchService, fieldService, child) {
                  if (kDebugMode) {
                    print('Consumer rebuilding: MatchService has ${matchService.matches.length} matches');
                  }

                  // Show loading indicator while loading weekly matches
                  if (_isLoadingWeeklyMatches && _optimizedWeeklyMatches == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Always use fresh data from MatchService to ensure reactivity
                  final filteredMatches = _getMatchesForWeek(matchService.matches);

                  // Update the optimized cache for performance
                  if (_optimizedWeeklyMatches == null ||
                      _optimizedWeeklyMatches!.length != filteredMatches.length) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _optimizedWeeklyMatches = filteredMatches;
                        });
                      }
                    });
                  }

          if (filteredMatches.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sports_soccer,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nessuna partita programmata\nper questa settimana',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Partite settimana: ${filteredMatches.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }


          return ListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: _buildMatchList(filteredMatches, fieldService.fields).length,
            itemBuilder: (context, index) {
              return _buildMatchList(filteredMatches, fieldService.fields)[index];
            },
          );
        },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMatchList(List<Match> matches, List<Field> fields) {
    final List<Widget> widgets = [];
    
    // Ordina le partite per data e poi per orario
    final sortedMatches = List<Match>.from(matches)..sort((a, b) {
      final dateComparison = a.date.compareTo(b.date);
      if (dateComparison != 0) return dateComparison;
      return a.time.compareTo(b.time);
    });
    
    DateTime? currentDate;
    
    for (final match in sortedMatches) {
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      
      // Non mostrare più header delle date e separatori
      if (currentDate == null || !_isSameDay(currentDate, matchDate)) {
        currentDate = matchDate;
      }
      
      // Aggiungi la partita
      widgets.add(_buildCompactMatchItem(match, fields));
    }

    return widgets;
  }
  
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && 
           date1.month == date2.month && 
           date1.day == date2.day;
  }


  Widget _buildCompactMatchItem(Match match, List<Field> fields) {
    return Container(
      height: 110,
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: () => _showEditMatchDialog(match),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: _getMatchTypeColor(match.matchType),
                  width: 6,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
              // Prima riga: risultato - squadra A - logo A - orario - logo B - squadra B - risultato
              Row(
                children: [
                  // Risultato squadra A (sinistra)
                  Container(
                    width: 20,
                    child: Text(
                      match.isHome 
                          ? (match.goalsAurora?.toString() ?? '-')
                          : (match.goalsOpponent?.toString() ?? '-'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: (match.goalsAurora != null && match.goalsOpponent != null)
                            ? _getResultColor(match.goalsAurora!, match.goalsOpponent!)
                            : Colors.grey[600]!,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  const SizedBox(width: 4),
                  
                  // Nome squadra A
                  Expanded(
                    flex: 3,
                    child: Text(
                      match.isHome
                          ? (match.auroraTeam ?? 'AURORA')
                          : match.opponent,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: match.isHome ? Colors.lightBlue : Colors.black,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  const SizedBox(width: 14),
                  
                  // Giorno e orario centrati con checkbox sotto
                  Container(
                    width: 35,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('dd/MM', 'it_IT').format(match.date),
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E3A8A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          _formatTime(match.time),
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E3A8A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Transform.scale(
                          scale: 0.6,
                          child: Checkbox(
                            value: match.includeInPlanning,
                            onChanged: (value) => _togglePlanningInclusion(match, value ?? false),
                            activeColor: const Color(0xFF1E3A8A),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 14),
                  
                  // Nome squadra B
                  Expanded(
                    flex: 3,
                    child: Text(
                      !match.isHome
                          ? (match.auroraTeam ?? 'AURORA')
                          : match.opponent,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: !match.isHome ? Colors.lightBlue : Colors.black,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  const SizedBox(width: 4),
                  
                  // Risultato squadra B (destra)
                  Container(
                    width: 20,
                    child: Text(
                      !match.isHome 
                          ? (match.goalsAurora?.toString() ?? '-')
                          : (match.goalsOpponent?.toString() ?? '-'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: (match.goalsAurora != null && match.goalsOpponent != null)
                            ? _getResultColor(match.goalsAurora!, match.goalsOpponent!)
                            : Colors.grey[600]!,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 1),
              
              // Seconda riga: evento a sinistra e campo a destra
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Evento a sinistra
                  Text(
                    _formatMatchTypeForDisplay(match),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Campo a destra
                  Expanded(
                    child: Text(
                      _getLocationDisplay(match, fields),
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchListItem(Match match) {
    final matchTypeMap = {
      'campionato': 'Campionato',
      'torneo': 'Torneo',
      'coppa': 'Coppa',
      'amichevole': 'Amichevole',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showResultDialog(match),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prima riga: Data e Ora
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${DateFormat('dd.MM.yy', 'it_IT').format(match.date)} - ore ${_formatTime(match.time)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getTypeColor(match.matchType),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      () {
                        final baseType = matchTypeMap[match.matchType] ?? 'Campionato';
                        
                        // Per TORNEO: mostra direttamente le note invece di "TORNEO"
                        if (match.matchType.toLowerCase() == 'torneo' && 
                            match.notes != null && match.notes!.isNotEmpty) {
                          return match.notes!.trim();
                        }
                        
                        // Per COPPA: mostra direttamente le note (come TORNEO)
                        if (match.matchType.toLowerCase() == 'coppa' && 
                            match.notes != null && match.notes!.isNotEmpty) {
                          return match.notes!.trim();
                        }
                        
                        return baseType;
                      }(),
                      style: const TextStyle(
                        fontSize: 10, // Ridotto per fare spazio alle note
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2, // Permette 2 righe
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              
              // Seconda riga: Squadra di casa
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: match.isHome ? Colors.red : Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        match.isHome
                            ? (match.auroraTeam ?? 'AURORA')
                            : match.opponent,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      match.isHome 
                          ? (match.goalsAurora?.toString() ?? '-')
                          : (match.goalsOpponent?.toString() ?? '-'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: (match.goalsAurora != null && match.goalsOpponent != null)
                            ? _getResultColor(match.goalsAurora!, match.goalsOpponent!)
                            : Colors.grey[600]!,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Terza riga: Squadra ospite  
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: !match.isHome ? Colors.red : Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !match.isHome
                            ? (match.auroraTeam ?? 'AURORA')
                            : match.opponent,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      !match.isHome 
                          ? (match.goalsAurora?.toString() ?? '-')
                          : (match.goalsOpponent?.toString() ?? '-'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: (match.goalsAurora != null && match.goalsOpponent != null)
                            ? _getResultColor(match.goalsAurora!, match.goalsOpponent!)
                            : Colors.grey[600]!,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              
              // Quarta riga: Campo e indicatori
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicatore tipo partita a sinistra
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _getMatchTypeColor(match.matchType),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _getMatchTypeLetter(match.matchType),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_formatMatchTypeForDisplay(match)} - ${match.location}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (match.goalsAurora == null || match.goalsOpponent == null)
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: const Color(0xFF1E3A8A),
                    ),
                ],
              ),
              
              // Note (se presenti)
              if (match.notes != null && match.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.note,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.notes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'campionato':
        return const Color(0xFF1E3A8A); // Blu
      case 'coppa':
        return Colors.red[600]!; // Rosso
      case 'torneo':
        return Colors.orange[600]!; // Arancione
      case 'amichevole':
        return Colors.green[600]!; // Verde
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getResultColor(int auroraGoals, int opponentGoals) {
    if (auroraGoals > opponentGoals) {
      return Colors.green[600]!; // Vittoria
    } else if (auroraGoals == opponentGoals) {
      return Colors.orange[600]!; // Pareggio
    } else {
      return Colors.red[600]!; // Sconfitta
    }
  }

  Color _getMatchTypeColor(String matchType) {
    switch (matchType.toLowerCase()) {
      case 'campionato': return Colors.green;
      case 'coppa': return Colors.blue;
      case 'torneo': return Colors.orange;
      case 'amichevole': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Future<void> _togglePlanningInclusion(Match match, bool includeInPlanning) async {
    final matchService = context.read<MatchService>();

    // Aggiornamento ottimistico: aggiorna immediatamente l'UI
    final updatedMatch = match.copyWith(includeInPlanning: includeInPlanning);
    matchService.updateMatchLocally(updatedMatch);

    try {
      // Prova ad aggiornare la partita nel database
      final success = await matchService.updateMatch(updatedMatch);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              includeInPlanning
                  ? 'Partita inclusa nel planning'
                  : 'Partita esclusa dal planning',
            ),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Se fallisce l'aggiornamento del database, mostra messaggio di fallback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aggiornamento locale: ${includeInPlanning ? "Inclusa" : "Esclusa"} dal planning',
            ),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      // In caso di errore, mostra messaggio di errore ma mantieni l'aggiornamento locale
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Salvataggio locale: ${includeInPlanning ? "Inclusa" : "Esclusa"} dal planning',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  String _getMatchTypeLetter(String matchType) {
    switch (matchType.toLowerCase()) {
      case 'campionato': return 'C';
      case 'coppa': return 'C';
      case 'torneo': return 'T';
      case 'amichevole': return 'A';
      default: return 'M';
    }
  }

  String _getMatchTypeDisplayName(String? matchType) {
    // Se il tipo partita è nullo o vuoto, restituisce 'CAMPIONATO' come default
    final type = matchType ?? 'campionato';
    if (type.isEmpty) return 'CAMPIONATO';

    switch (type.toLowerCase()) {
      case 'campionato':
        return 'CAMPIONATO';
      case 'amichevole':
        return 'AMICHEVOLE';
      case 'coppa_italia':
        return 'COPPA ITALIA';
      case 'coppa_lombardia':
        return 'COPPA LOMBARDIA';
      case 'torneo':
        return 'TORNEO';
      case 'coppa':
        return 'COPPA';
      default:
        return type.toUpperCase();
    }
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _getLocationDisplay(Match match, List<Field> fields) {
    // Se è fuori casa, mostra sempre l'indirizzo completo
    if (!match.isHome) {
      return match.location;
    }
    
    // Se è in casa, cerca il campo che corrisponde all'indirizzo
    // Normalizza gli indirizzi rimuovendo spazi extra e newline
    final matchLocation = match.location.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    
    for (final field in fields) {
      final fieldAddress = field.address.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      
      // Confronto esatto
      if (fieldAddress == matchLocation) {
        return field.name;
      }
      
      // Confronto parziale - se l'indirizzo della partita contiene quello del campo
      if (matchLocation.contains(fieldAddress) || fieldAddress.contains(matchLocation)) {
        return field.name;
      }
    }
    
    // Se non trova corrispondenza, mostra l'indirizzo originale
    return match.location;
  }

  String _getPDFLocationText(Match match, List<Field> availableFields) {
    // Per partite in casa, cerca il nome del campo
    if (match.isHome) {
      final matchLocation = match.location.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      for (final field in availableFields) {
        final fieldAddress = field.address.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (fieldAddress == matchLocation || 
            matchLocation.contains(fieldAddress) || 
            fieldAddress.contains(matchLocation)) {
          return field.name;
        }
      }
    }
    return match.location;
  }

  void _showEditMatchDialog(Match match) {
    showDialog(
      context: context,
      builder: (context) => MatchFormDialog(
        selectedDate: match.date,
        match: match,
        onSave: (updatedMatch) async {
          final matchService = context.read<MatchService>();
          final success = await matchService.updateMatch(updatedMatch);
          if (success && mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Partita aggiornata con successo'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Errore nell\'aggiornamento della partita'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onDelete: () async {
          final matchService = context.read<MatchService>();
          final success = await matchService.deleteMatch(match.id!);
          if (success && mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Partita eliminata con successo'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Errore nell\'eliminazione della partita'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showResultDialog(Match match) {
    final auroraController = TextEditingController(
      text: match.goalsAurora?.toString() ?? '',
    );
    final opponentController = TextEditingController(
      text: match.goalsOpponent?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Risultato Partita',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                Row(
                  children: [
                    // Squadra di casa (sempre a sinistra)
                    Expanded(
                      child: Container(
                        height: 40, // Altezza fissa per il nome più padding
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          match.isHome ? (match.auroraTeam ?? 'Aurora') : match.opponent,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Squadra ospite (sempre a destra)
                    Expanded(
                      child: Container(
                        height: 40, // Altezza fissa per il nome più padding
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          !match.isHome ? (match.auroraTeam ?? 'Aurora') : match.opponent,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // TextBox casa
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextFormField(
                          controller: match.isHome ? auroraController : opponentController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '0',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // TextBox ospite
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextFormField(
                          controller: !match.isHome ? auroraController : opponentController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '0',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla', style: TextStyle(fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final matchService = context.read<MatchService>();

              final auroraText = auroraController.text.trim();
              final opponentText = opponentController.text.trim();
              
              final auroraGoals = auroraText.isEmpty ? 0 : int.tryParse(auroraText);
              final opponentGoals = opponentText.isEmpty ? 0 : int.tryParse(opponentText);
              
              if (auroraGoals != null && auroraGoals >= 0 && 
                  opponentGoals != null && opponentGoals >= 0) {
                final updatedMatch = match.copyWith(
                  goalsAurora: auroraGoals,
                  goalsOpponent: opponentGoals,
                );
                
                final success = await matchService.updateMatch(updatedMatch);
                
                navigator.pop();
                if (success) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Risultato salvato con successo!')),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Errore nel salvare il risultato'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Inserisci numeri validi per i goal'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Salva', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _cleanTeamNameForLogo(String teamName) {
    return teamName
        // Rimuove i suffissi con eventuali spazi prima
        .replaceAll(RegExp(r'\s*SQ\.A\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*SQ\.B\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*SQ_A\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*SQ_B\s*$', caseSensitive: false), '')
        // Rimuove anche varianti nel mezzo della stringa
        .replaceAll(RegExp(r'\s*SQ\.A\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s*SQ\.B\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s*SQ_A\s*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s*SQ_B\s*', caseSensitive: false), ' ')
        // Pulisce spazi multipli e trim finale
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<pw.MemoryImage?> _loadTeamLogo(String teamName) async {
    try {
      final cleanTeamName = _cleanTeamNameForLogo(teamName);

      // Controlla prima nella cache
      if (_logoCache.containsKey(cleanTeamName)) {
        debugPrint('Logo trovato nella cache per: $cleanTeamName');
        return _logoCache[cleanTeamName];
      }

      debugPrint('=== LOGO LOADING DEBUG ===');
      debugPrint('Input nome originale: "$teamName"');
      debugPrint('Dopo _cleanTeamNameForLogo: "$cleanTeamName"');

      // Normalizza il nome della squadra per il filename (mantieni spazi e punti)
      var normalizedName = cleanTeamName
          .toLowerCase()
          .replaceAll('/', '')
          .replaceAll('-', '')
          .replaceAll('à', 'a')
          .replaceAll('è', 'e')
          .replaceAll('ì', 'i')
          .replaceAll('ò', 'o')
          .replaceAll('ù', 'u');

      // Pulisce ancora le varianti normalizzate di SQ.A/SQ.B
      normalizedName = normalizedName
          .replaceAll('sqa', '')
          .replaceAll('sqb', '')
          .trim();

      debugPrint('Nome finale normalizzato: "$normalizedName"');
      debugPrint('=========================');

      // Cerca il nome della squadra in tutte le varianti di case con suffisso .png
      final extensions = ['png'];
      final nameVariations = [
        normalizedName, // nome pulito e normalizzato (minuscolo)
        normalizedName.toUpperCase(), // nome in maiuscolo
        _toTitleCase(normalizedName), // nome con iniziali maiuscole
      ];
      
      for (final variation in nameVariations) {
        for (final ext in extensions) {
          try {
            final fileName = '$variation.$ext';
            debugPrint('Provando: $fileName');
            
            // Prima prova con URL pubblico
            final publicUrl = Supabase.instance.client.storage
                .from('loghi')
                .getPublicUrl(fileName);
            
            debugPrint('URL pubblico generato: $publicUrl');
            
            var response = await http.get(Uri.parse(publicUrl)).timeout(
              const Duration(seconds: 3),
              onTimeout: () => http.Response('', 408), // Timeout response
            );
            debugPrint('Response status URL pubblico per $fileName: ${response.statusCode}');
            
            // Se l'URL pubblico fallisce (400), prova con URL firmato
            if (response.statusCode != 200) {
              try {
                debugPrint('URL pubblico fallito, provando con URL firmato...');
                final signedUrl = await Supabase.instance.client.storage
                    .from('loghi')
                    .createSignedUrl(fileName, 60); // 60 secondi di validità
                
                debugPrint('URL firmato generato: $signedUrl');
                response = await http.get(Uri.parse(signedUrl)).timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => http.Response('', 408),
                );
                debugPrint('Response status URL firmato per $fileName: ${response.statusCode}');
              } catch (signedError) {
                debugPrint('Errore URL firmato per $fileName: $signedError');
              }
            }
            
            // Se abbiamo una risposta di successo, usiamo l'immagine
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              debugPrint('✅ Logo trovato: $fileName');
              return pw.MemoryImage(response.bodyBytes);
            }
            
            // Ultimo tentativo: download diretto dal bucket
            if (response.statusCode != 200) {
              try {
                debugPrint('Tentativo download diretto per $fileName...');
                final bytes = await Supabase.instance.client.storage
                    .from('loghi')
                    .download(fileName);
                
                if (bytes.isNotEmpty) {
                  debugPrint('✅ Logo scaricato direttamente: $fileName');
                  final logo = pw.MemoryImage(bytes);
                  // Salva nella cache
                  _logoCache[cleanTeamName] = logo;
                  return logo;
                }
              } catch (downloadError) {
                debugPrint('Errore download diretto per $fileName: $downloadError');
              }
            }
          } catch (e) {
            debugPrint('Errore per $variation.$ext: $e');
            continue;
          }
        }
      }
      
      debugPrint('❌ Nessun logo trovato per $teamName');
      // Salva anche il null nella cache per evitare ricerche ripetute
      _logoCache[cleanTeamName] = null;
      return null; // Nessun logo trovato
    } catch (e) {
      debugPrint('Errore generale nel caricamento logo per $teamName: $e');
      // Salva anche l'errore nella cache
      final cleanTeamNameForCache = _cleanTeamNameForLogo(teamName);
      _logoCache[cleanTeamNameForCache] = null;
      return null;
    }
  }

  Future<void> _previewExtendedPDF() async {
    // Mostra popup di caricamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(178),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final matchService = context.read<MatchService>();
      final fieldService = context.read<FieldService>();
      final fields = fieldService.fields;
      final filteredMatches = _getMatchesForWeekPDF(matchService.matches)
        ..sort((a, b) {
          final dateCompare = a.date.compareTo(b.date);
          if (dateCompare != 0) return dateCompare;
          return a.time.compareTo(b.time);
        });

      // Load logo
      final logoData = await rootBundle.load('assets/images/aurora_logo.png');
      final logo = pw.MemoryImage(logoData.buffer.asUint8List());

      // Precarica i loghi per tutte le partite in parallelo
      final Map<String, pw.MemoryImage?> teamLogos = {};
      final Set<String> uniqueTeams = {};

      // Raccogli tutti i nomi delle squadre uniche
      for (final match in filteredMatches) {
        final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
        final awayTeam = !match.isHome ? 'AURORA SERIATE' : match.opponent;
        uniqueTeams.add(homeTeam);
        uniqueTeams.add(awayTeam);
      }

      // Carica tutti i loghi in parallelo con timeout globale di 8 secondi
      try {
        final futures = uniqueTeams.map((teamName) => _loadTeamLogo(teamName)).toList();
        final results = await Future.wait(futures, eagerError: false).timeout(
          const Duration(seconds: 8),
          onTimeout: () => List.filled(uniqueTeams.length, null),
        );

        // Associa i risultati alle squadre
        int index = 0;
        for (final teamName in uniqueTeams) {
          final cleanTeamName = _cleanTeamNameForLogo(teamName);
          teamLogos[cleanTeamName] = results[index];
          index++;
        }
      } catch (e) {
        debugPrint('Timeout o errore nel caricamento loghi: $e');
        // Continua senza loghi se il caricamento fallisce
      }

    // Carica gli sfondi per le due pagine
    final agonisticaBackground = await _loadAssetImage('assets/images/weekend_match_ago.jpg');
    final attivitaBaseBackground = await _loadAssetImage('assets/images/weekend_match_adb.jpg');

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );

    // Dividi le partite in categorie agonistiche e attività di base
    final agonisticheTeams = ['PRIMA', 'PROMOZIONE', 'U21', 'U19', 'U18', 'U17', 'U16', 'U15', 'U14'];
    final agonisticheMatches = filteredMatches.where((match) {
      final auroraTeam = match.auroraTeam?.toUpperCase() ?? '';
      return agonisticheTeams.any((team) => auroraTeam.contains(team));
    }).toList();

    final attivitaBaseMatches = filteredMatches.where((match) {
      final auroraTeam = match.auroraTeam?.toUpperCase() ?? '';
      return !agonisticheTeams.any((team) => auroraTeam.contains(team));
    }).toList();

    // Prima pagina - AGONISTICA
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 14),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // Sfondo per agonistica
              pw.Positioned.fill(
                child: pw.Image(agonisticaBackground, fit: pw.BoxFit.cover),
              ),
              // Contenuto
              pw.Column(
                children: [
                  // Spazio iniziale senza titolo
                  pw.SizedBox(height: 80), // Spazio iniziale

                  // Matches list agonistiche
                  if (agonisticheMatches.isEmpty)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 16),
                      child: pw.Text(
                        'Nessuna partita agonistica programmata',
                        style: const pw.TextStyle(fontSize: 18),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                  else
                    ...(_buildExtendedPDFMatchList(agonisticheMatches, fields, teamLogos)),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Seconda pagina - ATTIVITÀ DI BASE
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 14),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // Sfondo per attività di base
              pw.Positioned.fill(
                child: pw.Image(attivitaBaseBackground, fit: pw.BoxFit.cover),
              ),
              // Contenuto
              pw.Column(
                children: [
                  // Spazio iniziale senza titolo
                  pw.SizedBox(height: 80), // Spazio iniziale

                  // Matches list attività di base
                  if (attivitaBaseMatches.isEmpty)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 16),
                      child: pw.Text(
                        'Nessuna partita di attività di base programmata',
                        style: const pw.TextStyle(fontSize: 18),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                  else
                    ...(_buildExtendedPDFMatchList(attivitaBaseMatches, fields, teamLogos)),
                ],
              ),
            ],
          );
        },
      ),
    );

      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      // Calcola titolo dinamico con date delle partite
      String title = 'Weekly Matches';
      if (filteredMatches.isNotEmpty) {
        final firstDate = filteredMatches.first.date;
        final lastDate = filteredMatches.last.date;
        final firstDateStr = DateFormat('dd.MM', 'it_IT').format(firstDate);
        final lastDateStr = DateFormat('dd.MM', 'it_IT').format(lastDate);
        title = 'Weekly Matches $firstDateStr - $lastDateStr';
      }

      // Anteprima PDF
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: const Color(0xFF1E3A8A),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: PdfPreview(
              build: (format) async => await pdf.save(),
              actions: const [],
              canChangePageFormat: false,
              canChangeOrientation: false,
              pdfFileName: 'partite_settimana_esteso_${DateFormat('ddMMyy', 'it_IT').format(_currentWeekStart)}.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      // Chiudi popup in caso di errore
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante il caricamento: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _previewWeeklyPDF() async {
    // Mostra popup di caricamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(178),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final matchService = context.read<MatchService>();
      final fieldService = context.read<FieldService>();
      final fields = fieldService.fields;
      final filteredMatches = _getMatchesForWeekPDF(matchService.matches)
        ..sort((a, b) {
          final dateCompare = a.date.compareTo(b.date);
          if (dateCompare != 0) return dateCompare;
          return a.time.compareTo(b.time);
        });

      // Load logo
      final logoData = await rootBundle.load('assets/images/aurora_logo.png');
      final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    
    // Prima testiamo il bucket per vedere che file sono disponibili
    try {
      final files = await Supabase.instance.client.storage
          .from('loghi')
          .list();
      debugPrint('File disponibili nel bucket loghi:');
      for (final file in files) {
        debugPrint('- ${file.name}');
      }
    } catch (e) {
      debugPrint('Errore nel listare i file del bucket: $e');
    }
    
    // Precarica i loghi per tutte le partite in parallelo
    final Map<String, pw.MemoryImage?> teamLogos = {};
    final Set<String> uniqueTeams = {};

    // Raccogli tutti i nomi delle squadre uniche
    for (final match in filteredMatches) {
      final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
      final awayTeam = !match.isHome ? 'AURORA SERIATE' : match.opponent;
      uniqueTeams.add(homeTeam);
      uniqueTeams.add(awayTeam);
    }

    // Carica tutti i loghi in parallelo con timeout globale di 8 secondi
    try {
      final futures = uniqueTeams.map((teamName) => _loadTeamLogo(teamName)).toList();
      final results = await Future.wait(futures, eagerError: false).timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.filled(uniqueTeams.length, null),
      );

      // Associa i risultati alle squadre
      int index = 0;
      for (final teamName in uniqueTeams) {
        final cleanTeamName = _cleanTeamNameForLogo(teamName);
        teamLogos[cleanTeamName] = results[index];
        index++;
      }
    } catch (e) {
      debugPrint('Timeout o errore nel caricamento loghi: $e');
      // Continua senza loghi se il caricamento fallisce
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );

    // Calcola quante partite possono entrare in una pagina (con loghi 100x100 e card da 45px)
    const int matchesPerPage = 16;
    final List<List<Match>> pageGroups = [];
    
    for (int i = 0; i < filteredMatches.length; i += matchesPerPage) {
      pageGroups.add(filteredMatches.sublist(i, 
        i + matchesPerPage > filteredMatches.length ? filteredMatches.length : i + matchesPerPage));
    }
    
    // Se non ci sono partite, crea comunque una pagina
    if (pageGroups.isEmpty) {
      pageGroups.add([]);
    }

    // Genera una pagina per ogni gruppo
    for (int pageIndex = 0; pageIndex < pageGroups.length; pageIndex++) {
      final pageMatches = pageGroups[pageIndex];
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Margini ridotti per più spazio
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // Header with logos - solo sulla prima pagina o ridotto nelle altre
                if (pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 12, bottom: 6), // Ridotta ulteriormente distanza bordo superiore
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo sinistro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                        // Titolo centrale
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'LE PARTITE DEL WEEKEND',
                                style: pw.TextStyle(
                                  fontSize: 20,
                                  color: PdfColors.blue800,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        // Logo destro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                      ],
                    ),
                  )
                else
                  // Header ridotto per le pagine successive
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Text(
                      'Weekly Matches (cont.) - ${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yyyy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)))}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.blue800,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                // Matches list per questa pagina
                if (pageMatches.isEmpty && pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 30),
                    child: pw.Text(
                      'Nessuna partita programmata per questa settimana',
                      style: const pw.TextStyle(fontSize: 18),
                      textAlign: pw.TextAlign.center,
                    ),
                  )
                else
                  ...(_buildPDFMatchListWithLogos(pageMatches, teamLogos)),
                
                // Numerazione pagine rimossa per ottimizzare spazio
              ],
            );
          },
        ),
      );
    }

      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      // Anteprima senza stampa usando PdfPreview
      Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'Anteprima PDF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF1E3A8A),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: PdfPreview(
            build: (format) async => await pdf.save(),
            actions: const [], // Rimuove tutti i pulsanti di azione
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: 'partite_settimana_${DateFormat('ddMMyy', 'it_IT').format(_currentWeekStart)}.pdf',
          ),
        ),
      ),
    );
    } catch (e) {
      // Chiudi popup in caso di errore
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante il caricamento: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _generateWeeklyPDF() async {
    final matchService = context.read<MatchService>();
    final filteredMatches = _getMatchesForWeekPDF(matchService.matches)
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.time.compareTo(b.time);
      });

    // Load logo
    final logoData = await rootBundle.load('assets/images/aurora_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );

    // Calcola quante partite possono entrare in una pagina (con loghi 100x100 e card da 45px)
    const int matchesPerPage = 16; // Ridotto per sezioni giorni più alte
    final List<List<Match>> pageGroups = [];
    
    for (int i = 0; i < filteredMatches.length; i += matchesPerPage) {
      pageGroups.add(filteredMatches.sublist(i, 
        i + matchesPerPage > filteredMatches.length ? filteredMatches.length : i + matchesPerPage));
    }
    
    // Se non ci sono partite, crea comunque una pagina
    if (pageGroups.isEmpty) {
      pageGroups.add([]);
    }
    
    // Debug: mostra quanti gruppi sono stati creati
    debugPrint('PDF: Creati ${pageGroups.length} gruppi di partite, totale partite: ${filteredMatches.length}');
    debugPrint('PDF: Partite per pagina: $matchesPerPage');
    for (int i = 0; i < pageGroups.length; i++) {
      debugPrint('PDF: Pagina ${i + 1} ha ${pageGroups[i].length} partite');
    }

    // Genera una pagina per ogni gruppo
    for (int pageIndex = 0; pageIndex < pageGroups.length; pageIndex++) {
      final pageMatches = pageGroups[pageIndex];
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Margini ridotti per più spazio // Margini aumentati per stampa
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // Header with logos - solo sulla prima pagina o ridotto nelle altre
                if (pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 12, bottom: 6), // Ridotta ulteriormente distanza bordo superiore
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo sinistro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                        // Titolo centrale
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'LE PARTITE DEL WEEKEND',
                                style: pw.TextStyle(
                                  fontSize: 24,
                                  color: PdfColors.blue800,
                                  fontWeight: pw.FontWeight.bold, // Grassetto e maiuscolo
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        // Logo destro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                      ],
                    ),
                  )
                else
                  // Header ridotto per le pagine successive
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Text(
                      'Weekly Matches (cont.) - ${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yyyy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)))}',
                      style: pw.TextStyle(
                        fontSize: 18, // +2 punti
                        color: PdfColors.blue800,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                // Matches list per questa pagina
                if (pageMatches.isEmpty && pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 30),
                    child: pw.Text(
                      'Nessuna partita programmata per questa settimana',
                      style: const pw.TextStyle(fontSize: 18), // +2 punti
                      textAlign: pw.TextAlign.center,
                    ),
                  )
                else ...[
                  pw.SizedBox(height: 90), // Spazio aggiuntivo prima delle partite (circa 3cm)
                  ...(_buildPDFMatchList(pageMatches)),
                ],
                
                // Numerazione pagine rimossa per ottimizzare spazio
                
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  List<pw.Widget> _buildPDFMatchListWithLogos(List<Match> matches, Map<String, pw.MemoryImage?> teamLogos) {
    final List<pw.Widget> widgets = [];
    String? currentDate;

    for (final match in matches) {
      final matchDate = DateFormat('EEEE dd MMMM', 'it_IT').format(match.date)
          .replaceAll('lunedì', 'lunedi')
          .replaceAll('martedì', 'martedi')
          .replaceAll('mercoledì', 'mercoledi')
          .replaceAll('giovedì', 'giovedi')
          .replaceAll('venerdì', 'venerdi');
      
      // Add date header if different from previous
      if (currentDate != matchDate) {
        currentDate = matchDate;
        widgets.add(
          pw.Container(
            width: double.infinity,
            height: 12 * 2.83, // Altezza fissa 1,2cm (12mm) per le righe blu
            margin: const pw.EdgeInsets.only(top: 4, bottom: 2),
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [PdfColors.blue800, PdfColors.blue700],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              matchDate.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 16, // Aumentato per maggiore visibilità
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2, // Spaziatura caratteri per grassetto più forte
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }
      
      // Add match item with fixed height layout
      widgets.add(
        pw.Container(
          width: double.infinity,
          height: 45,
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.blue200, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Row(
              children: [
                // Squadra A
                pw.Expanded(
                  flex: 30,
                  child: pw.Text(
                    match.isHome ? 'AURORA SERIATE' : match.opponent,
                    style: pw.TextStyle(
                      fontSize: match.isHome ? 13 : 12,
                      color: match.isHome ? PdfColors.red : PdfColors.black,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.left,
                    maxLines: 1,
                  ),
                ),

                // Trattino centrale
                pw.Expanded(
                  flex: 10,
                  child: pw.Text(
                    '-',
                    style: pw.TextStyle(
                      fontSize: 20,
                      color: PdfColors.grey800,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                // Squadra B
                pw.Expanded(
                  flex: 30,
                  child: pw.Text(
                    !match.isHome ? 'AURORA SERIATE' : match.opponent,
                    style: pw.TextStyle(
                      fontSize: !match.isHome ? 13 : 12,
                      color: !match.isHome ? PdfColors.red : PdfColors.black,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                    maxLines: 1,
                  ),
                ),

                // Orario
                pw.Expanded(
                  flex: 20,
                  child: pw.Text(
                    _formatTime(match.time),
                    style: pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.blue900,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  pw.Widget _buildTeamLogo(String teamName, Map<String, pw.MemoryImage?> teamLogos) {
    final cleanTeamName = _cleanTeamNameForLogo(teamName);
    final logo = teamLogos[cleanTeamName];
    if (logo != null) {
      return pw.Container(
        width: teamName == 'AURORA SERIATE' ? 85 : 80, // Loghi Aurora ancora più grandi, altri aumentati ulteriormente
        height: teamName == 'AURORA SERIATE' ? 85 : 80, // Loghi Aurora ancora più grandi, altri aumentati ulteriormente
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
    } else {
      // Se non c'è logo, restituisce spazio vuoto
      return pw.Container(
        width: teamName == 'AURORA SERIATE' ? 85 : 80,
        height: teamName == 'AURORA SERIATE' ? 85 : 80,
      );
    }
  }

  pw.Widget _buildCompactTeamLogo(String teamName, Map<String, pw.MemoryImage?> teamLogos) {
    final cleanTeamName = _cleanTeamNameForLogo(teamName);
    final logo = teamLogos[cleanTeamName];

    if (logo != null) {
      return pw.Image(logo, fit: pw.BoxFit.contain);
    } else {
      // Se non c'è logo, restituisce spazio vuoto
      return pw.Container();
    }
  }

  List<pw.Widget> _buildPDFMatchList(List<Match> matches) {
    final List<pw.Widget> widgets = [];
    String? currentDate;

    for (final match in matches) {
      final matchDate = DateFormat('EEEE dd MMMM', 'it_IT').format(match.date)
          .replaceAll('lunedì', 'lunedi')
          .replaceAll('martedì', 'martedi')
          .replaceAll('mercoledì', 'mercoledi')
          .replaceAll('giovedì', 'giovedi')
          .replaceAll('venerdì', 'venerdi');

      // Add date header if different from previous
      if (currentDate != matchDate) {
        currentDate = matchDate;
        widgets.add(
          pw.Container(
            width: double.infinity,
            height: 12 * 2.83,
            margin: const pw.EdgeInsets.only(top: 18, bottom: 2), // Ridotto di 0.5cm
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [PdfColors.blue800, PdfColors.blue700],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              matchDate.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 16,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }

      // Add match item - versione semplificata
      widgets.add(
        pw.Container(
          width: double.infinity,
          height: 45,
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.blue200, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Row(
              children: [
                // Squadra A
                pw.Expanded(
                  flex: 35,
                  child: pw.Text(
                    match.isHome ? 'AURORA SERIATE' : match.opponent,
                    style: pw.TextStyle(
                      fontSize: match.isHome ? 13 : 12,
                      color: match.isHome ? PdfColors.red : PdfColors.black,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.left,
                    maxLines: 1,
                  ),
                ),

                // Trattino centrale
                pw.Expanded(
                  flex: 10,
                  child: pw.Text(
                    '-',
                    style: pw.TextStyle(
                      fontSize: 20,
                      color: PdfColors.grey800,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                // Squadra B
                pw.Expanded(
                  flex: 35,
                  child: pw.Text(
                    !match.isHome ? 'AURORA SERIATE' : match.opponent,
                    style: pw.TextStyle(
                      fontSize: !match.isHome ? 13 : 12,
                      color: !match.isHome ? PdfColors.red : PdfColors.black,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                    maxLines: 1,
                  ),
                ),

                // Orario
                pw.Expanded(
                  flex: 20,
                  child: pw.Text(
                    _formatTime(match.time),
                    style: pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.blue900,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  String _getMatchTypeText(String type) {
    switch (type.toLowerCase()) {
      case 'campionato': return 'Campionato';
      case 'coppa': return 'Coppa';
      case 'torneo': return 'Torneo';
      case 'amichevole': return 'Amichevole';
      default: return type;
    }
  }

  PdfColor _getPDFTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'campionato': return PdfColors.green700;
      case 'coppa': return PdfColors.blue700;
      case 'torneo': return PdfColors.orange700;
      case 'amichevole': return PdfColors.purple700;
      default: return PdfColors.grey700;
    }
  }

  String _getMatchTypeInitial(String type) {
    switch (type.toLowerCase()) {
      case 'campionato': return 'C';
      case 'coppa': return 'C';
      case 'torneo': return 'T';
      case 'amichevole': return 'A';
      default: return 'M';
    }
  }

  String _getFieldName(String fieldCode) {
    try {
      final fieldService = context.read<FieldService>();
      final field = fieldService.fields.firstWhere(
        (field) => field.code == fieldCode,
      );
      return field.name; // Solo il nome, senza codice
    } catch (e) {
      return fieldCode; // Fallback al codice se non trovato
    }
  }

  pw.Widget _buildAuroraText(String text, double fontSize) {
    return pw.RichText(
      text: pw.TextSpan(
        text: text,
        style: pw.TextStyle(
          fontSize: fontSize - 2,
          color: PdfColors.blue900,
        ),
      ),
      textAlign: pw.TextAlign.left,
    );
  }

  pw.Widget _buildBoldText(String text, double fontSize, PdfColor color, {pw.TextAlign? textAlign}) {
    return pw.RichText(
      text: pw.TextSpan(
        text: text,
        style: pw.TextStyle(
          fontSize: fontSize,
          color: color,
        ),
      ),
      textAlign: textAlign ?? pw.TextAlign.left,
    );
  }

  pw.Widget _buildMatchTypeIcon(String type) {
    final color = _getPDFTypeColor(type);
    final initial = _getMatchTypeInitial(type);
    
    // Icone ingrandite e distintive per ogni tipo
    switch (type.toLowerCase()) {
      case 'campionato':
        // Cerchio più grande per campionato
        return pw.Container(
          width: 22,
          height: 22,
          decoration: pw.BoxDecoration(
            color: color,
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: PdfColors.white, width: 1),
          ),
          child: pw.Center(
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      
      case 'coppa':
        // Quadrato ruotato (diamante) per coppa
        return pw.Transform.rotate(
          angle: 0.785398, // 45 gradi
          child: pw.Container(
            width: 16,
            height: 16,
            decoration: pw.BoxDecoration(
              color: color,
              border: pw.Border.all(color: PdfColors.white, width: 1),
            ),
            child: pw.Transform.rotate(
              angle: -0.785398, // raddrizza il testo
              child: pw.Center(
                child: pw.Text(
                  initial,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      
      case 'torneo':
        // Quadrato per torneo
        return pw.Container(
          width: 20,
          height: 20,
          decoration: pw.BoxDecoration(
            color: color,
            border: pw.Border.all(color: PdfColors.white, width: 1),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Center(
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      
      case 'amichevole':
        // Esagono simulato con bordi arrotondati per amichevole
        return pw.Container(
          width: 20,
          height: 20,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.white, width: 1),
          ),
          child: pw.Center(
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      
      default:
        // Cerchio default
        return pw.Container(
          width: 20,
          height: 20,
          decoration: pw.BoxDecoration(
            color: color,
            shape: pw.BoxShape.circle,
          ),
          child: pw.Center(
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
    }
  }

  Future<void> _sendPdfToWhatsApp() async {
    final matchService = context.read<MatchService>();
    final filteredMatches = _getMatchesForWeekPDF(matchService.matches)
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.time.compareTo(b.time);
      });

    // Load logo
    final logoData = await rootBundle.load('assets/images/aurora_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );

    // Calcola quante partite possono entrare in una pagina (con loghi 100x100 e card da 45px)
    const int matchesPerPage = 16; // Ridotto per sezioni giorni più alte
    final List<List<Match>> pageGroups = [];
    
    for (int i = 0; i < filteredMatches.length; i += matchesPerPage) {
      pageGroups.add(filteredMatches.sublist(i, 
        i + matchesPerPage > filteredMatches.length ? filteredMatches.length : i + matchesPerPage));
    }
    
    // Se non ci sono partite, crea comunque una pagina
    if (pageGroups.isEmpty) {
      pageGroups.add([]);
    }
    
    // Debug: mostra quanti gruppi sono stati creati
    debugPrint('PDF: Creati ${pageGroups.length} gruppi di partite, totale partite: ${filteredMatches.length}');
    debugPrint('PDF: Partite per pagina: $matchesPerPage');
    for (int i = 0; i < pageGroups.length; i++) {
      debugPrint('PDF: Pagina ${i + 1} ha ${pageGroups[i].length} partite');
    }

    // Genera una pagina per ogni gruppo
    for (int pageIndex = 0; pageIndex < pageGroups.length; pageIndex++) {
      final pageMatches = pageGroups[pageIndex];
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Margini ridotti per più spazio // Margini aumentati per stampa
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // Header with logos - solo sulla prima pagina o ridotto nelle altre
                if (pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 12, bottom: 6), // Ridotta ulteriormente distanza bordo superiore
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo sinistro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                        // Titolo centrale
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'LE PARTITE DEL WEEKEND',
                                style: pw.TextStyle(
                                  fontSize: 24,
                                  color: PdfColors.blue800,
                                  fontWeight: pw.FontWeight.bold, // Grassetto e maiuscolo
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        // Logo destro
                        pw.Container(
                          width: 35,
                          height: 35,
                          child: pw.Image(logo),
                        ),
                      ],
                    ),
                  )
                else
                  // Header ridotto per le pagine successive
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Text(
                      'Weekly Matches (cont.) - ${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yyyy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)))}',
                      style: pw.TextStyle(
                        fontSize: 18, // +2 punti
                        color: PdfColors.blue800,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                // Matches list per questa pagina
                if (pageMatches.isEmpty && pageIndex == 0)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 30),
                    child: pw.Text(
                      'Nessuna partita programmata per questa settimana',
                      style: const pw.TextStyle(fontSize: 18), // +2 punti
                      textAlign: pw.TextAlign.center,
                    ),
                  )
                else ...[
                  pw.SizedBox(height: 90), // Spazio aggiuntivo prima delle partite (circa 3cm)
                  ...(_buildPDFMatchList(pageMatches)),
                ],
                
                // Numerazione pagine rimossa per ottimizzare spazio
                
              ],
            );
          },
        ),
      );
    }

    try {
      // Get the temporary directory
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/partite_settimana_${DateFormat('ddMMyy', 'it_IT').format(_currentWeekStart)}.pdf');
      
      // Write the PDF to the file
      await file.writeAsBytes(await pdf.save());

      // Share the file using share_plus
      await Share.shareXFiles([XFile(file.path)], text: 'Weekly Matches!');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generato e condiviso!')),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nella generazione o condivisione del PDF: $e')),
      );
    }
  }

  // Calcola l'altezza dinamica delle card usando la formula specifica
  // HT = 29,7cm (altezza totale foglio)
  // M = 2cm (margini totali)
  // RB = (nr righe blu dei giorni) * 1,2cm 
  // RP = nr card delle gare
  // AD = HT - M - RB (altezza disponibile)
  // Altezza dinamica card = AD / RP
  double _calculateDynamicCardHeight(List<Match> matches) {
    const double HT = 297; // 29,7cm in mm - altezza totale foglio A4
    const double M = 5; // 0,5cm in mm - margini reali totali
    const double headerHeight = 60; // Header reale misurato
    const double blueRowHeight = 14; // 1,4cm in mm - altezza reale ogni riga blu (giorno)
    
    // Conta le righe blu (giorni unici)
    Set<String> uniqueDates = {};
    for (var match in matches) {
      final dateKey = '${match.date.year}-${match.date.month}-${match.date.day}';
      uniqueDates.add(dateKey);
    }
    
    final int RB_count = uniqueDates.length; // Numero righe blu
    final double RB = RB_count * blueRowHeight; // Spazio totale righe blu
    final int RP = matches.length; // Numero card delle gare
    
    // Calcola altezza disponibile: AD = HT - M - Header - RB
    final double AD = HT - M - headerHeight - RB;
    
    // Per l'altezza dinamica, usiamo il calcolo per pagina, non per tutte le partite
    final int maxMatchesPerPage = _calculateMaxMatchesPerPage(matches, true);
    
    // Calcola quante partite ci sono effettivamente in questa chiamata 
    final int matchesThisCalculation = matches.length > maxMatchesPerPage ? maxMatchesPerPage : matches.length;
    
    // Calcola altezza dinamica per ogni card: AD / RP (per questa pagina)
    final double dynamicCardHeight = matchesThisCalculation > 0 ? AD / matchesThisCalculation : 0;
    
    // Debug: stampa i valori calcolati
    print('=== CALCOLO ALTEZZA DINAMICA ===');
    print('Partite totali (RP): $RP');
    print('Max partite per pagina: $maxMatchesPerPage');
    print('Partite in questo calcolo: $matchesThisCalculation');
    print('Giorni unici (RB_count): $RB_count');
    print('Spazio righe blu (RB): ${RB}mm');
    print('Altezza disponibile (AD): ${AD}mm');
    print('Altezza card dinamica: ${dynamicCardHeight}mm (${dynamicCardHeight/10}cm)');
    print('===============================');
    
    // Usa l'altezza calcolata dalla formula senza limitazioni artificiali
    return dynamicCardHeight;
  }

  // Calcola quante partite possono entrare in una pagina A4
  int _calculateMaxMatchesPerPage(List<Match> matches, [bool isFirstPage = true]) {
    const double HT = 297; // 29,7cm in mm - altezza totale foglio A4
    const double M = 5; // 0,5cm in mm - margini reali totali
    final double headerHeight = isFirstPage ? 60 : 30; // Header reale misurato
    const double blueRowHeight = 14; // 1,4cm in mm - altezza reale ogni riga blu (giorno)
    
    // Conta giorni unici per stimare spazio righe blu
    Set<String> uniqueDates = {};
    for (var match in matches) {
      final dateKey = '${match.date.year}-${match.date.month}-${match.date.day}';
      uniqueDates.add(dateKey);
    }
    
    final double RB = uniqueDates.length * blueRowHeight; // Spazio totale righe blu
    
    // Calcola altezza disponibile per le card: AD = HT - M - Header - RB
    final double AD = HT - M - headerHeight - RB;
    
    int result;
    // Calcola sempre quante partite possono entrare, senza limitazioni artificiali
    const double minCardHeight = 12; // Altezza minima ulteriormente ridotta
    int maxMatches = (AD / minCardHeight).floor();
    result = maxMatches > 0 ? maxMatches : 1;
    
    // Se abbiamo poche partite (≤ 10), assicurati che entrino tutte in una pagina
    if (matches.length <= 10 && matches.length > result) {
      // Forza tutte le partite in una pagina calcolando l'altezza dinamica
      result = matches.length;
    }
    
    // Debug per il calcolo delle pagine
    print('=== CALCOLO MAX PARTITE PER PAGINA ===');
    print('Prima pagina: $isFirstPage');
    print('Altezza header: ${headerHeight}mm');
    print('Altezza disponibile: ${AD}mm');
    print('Partite totali: ${matches.length}');
    print('Max partite per pagina: $result');
    print('======================================');
    
    return result;
  }

  // Crea i gruppi di partite per pagina in modo dinamico
  List<List<Match>> _createDynamicPageGroups(List<Match> matches) {
    if (matches.isEmpty) return [[]];
    
    print('=== IMPAGINAZIONE DINAMICA ===');
    print('Partite ricevute: ${matches.length}');
    
    final List<List<Match>> pageGroups = [];
    int currentIndex = 0;
    int pageNumber = 0;
    
    while (currentIndex < matches.length) {
      pageNumber++;
      final bool isFirstPage = pageNumber == 1;
      final int matchesForThisPage = _calculateMaxMatchesPerPage(matches, isFirstPage);
      
      final int endIndex = (currentIndex + matchesForThisPage > matches.length) 
          ? matches.length 
          : currentIndex + matchesForThisPage;
      
      pageGroups.add(matches.sublist(currentIndex, endIndex));
      currentIndex = endIndex;
      
      print('Pagina $pageNumber (prima: $isFirstPage): partite ${currentIndex - (endIndex - currentIndex) + 1}-$endIndex (max: $matchesForThisPage)');
    }
    
    print('==============================');
    
    return pageGroups;
  }

  // Calcola l'altezza totale della pagina PDF in base al contenuto
  double _calculateDynamicPageHeight(List<Match> matches) {
    const double baseHeight = 297; // A4 height in mm (minimo)
    
    // Usa sempre A4 per ora, l'altezza dinamica è per le card, non per la pagina
    return baseHeight;
  }

  List<pw.Widget> _buildExtendedPDFMatchList(List<Match> matches, List<Field> fields, Map<String, pw.MemoryImage?> teamLogos) {
    final List<pw.Widget> widgets = [];
    String? currentDate;

    // Calcola l'altezza dinamica delle card con minimo più alto
    final double dynamicCardHeight = _calculateDynamicCardHeight(matches);
    // Altezza minima per card
    final double minCardHeight = 17; // 1.7cm per card - ridotta distanza minima
    final double adjustedCardHeight = dynamicCardHeight < minCardHeight ? minCardHeight : dynamicCardHeight;
    // Converti da mm a punti PDF (1mm = ~2.83 punti)
    final double cardHeightInPoints = adjustedCardHeight * 2.83;

    // Calcola dimensione loghi dinamica in base all'altezza card
    // Altezza minima loghi: 50px - 20% = 40px
    final double minLogoSize = 40;
    // Massima dimensione logo: 60px
    final double maxLogoSize = 60;
    // Calcola dimensione logo proporzionale all'altezza card (circa 70% dell'altezza)
    final double dynamicLogoSize = (cardHeightInPoints * 0.7).clamp(minLogoSize, maxLogoSize);
    // Altezza fissa per le righe blu: aumentata a 1.0cm = 10mm = ~28 punti
    const double blueRowHeightInPoints = 10 * 2.83;

    // AGGIUNGE SPAZIO INIZIALE DI 1.5CM ALL'INIZIO
    widgets.add(pw.SizedBox(height: 42)); // 1.5cm = 42 punti (ridotto di 0.5cm)

    for (final match in matches) {
      final matchDate = DateFormat('EEEE dd MMMM', 'it_IT').format(match.date)
          .replaceAll('lunedì', 'lunedi')
          .replaceAll('martedì', 'martedi')
          .replaceAll('mercoledì', 'mercoledi')
          .replaceAll('giovedì', 'giovedi')
          .replaceAll('venerdì', 'venerdi');

      // Add date header if different from previous
      if (currentDate != matchDate) {
        currentDate = matchDate;
        widgets.add(
          pw.Container(
            width: double.infinity,
            height: blueRowHeightInPoints, // Altezza ridotta a 0.8cm
            margin: const pw.EdgeInsets.all(0), // Tutti i giorni attaccati, spazio iniziale gestito sopra
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 12), // Padding ridotto
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [PdfColors.blue800, PdfColors.blue700],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              matchDate.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 16, // Font giorni aumentato
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.0,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }

      // Determina se è un giorno infrasettimanale per questa specifica partita
      final isWeekday = currentDate!.toLowerCase().contains('lunedi') ||
                        currentDate!.toLowerCase().contains('martedi') ||
                        currentDate!.toLowerCase().contains('mercoledi') ||
                        currentDate!.toLowerCase().contains('giovedi') ||
                        currentDate!.toLowerCase().contains('venerdi');

      // Add match item - 7 colonne su 2 righe
      widgets.add(
        pw.Container(
          width: double.infinity,
          height: cardHeightInPoints,
          margin: const pw.EdgeInsets.all(0), // MARGINI AZZERATI PER DEBUG
          decoration: pw.BoxDecoration(
            // Nessun colore di sfondo - completamente trasparente
            border: pw.Border.all(color: PdfColors.white.shade(0.6), width: 1), // Bordo bianco semitrasparente
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Row(
            children: [
              // Logo A all'inizio della card (sinistra) - spostato verso il bordo
              pw.Container(
                width: 70, // Area più ampia per centrare il logo
                height: 50,
                margin: const pw.EdgeInsets.only(right: 4), // Ridotto margine per spostare verso il bordo
                child: pw.Center(
                  child: pw.Container(
                    width: dynamicLogoSize,
                    height: dynamicLogoSize,
                    child: _buildCompactTeamLogo(match.isHome ? 'AURORA SERIATE' : match.opponent, teamLogos),
                  ),
                ),
              ),

              // Contenuto centrale
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    // Riga principale centrata sull'orario
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Squadra A (categoria se Aurora) - larghezza fissa per centrare
                        pw.Container(
                          width: 178, // Larghezza ottimizzata per nomi lunghi
                          child: pw.Text(
                            match.isHome ? (match.auroraTeam ?? 'AURORA') : match.opponent,
                            style: pw.TextStyle(
                              fontSize: 16, // Font uguale per tutte le squadre
                              color: match.isHome ? PdfColors.red : PdfColors.black,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.right,
                            maxLines: 2, // Permetti 2 righe se necessario
                          ),
                        ),

                        // Orario al centro - elemento principale per centratura
                        pw.Container(
                          width: 60, // Larghezza fissa per centrare perfettamente
                          child: pw.Text(
                            _formatTime(match.time),
                            style: pw.TextStyle(
                              fontSize: 16, // Font orario aumentato
                              color: PdfColors.blue900,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),

                        // Squadra B (categoria se Aurora) - larghezza fissa per centrare
                        pw.Container(
                          width: 178, // Larghezza ottimizzata per nomi lunghi
                          child: pw.Text(
                            !match.isHome ? (match.auroraTeam ?? 'AURORA') : match.opponent,
                            style: pw.TextStyle(
                              fontSize: 16, // Font uguale per tutte le squadre
                              color: !match.isHome ? PdfColors.red : PdfColors.black,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.left,
                            maxLines: 2, // Permetti 2 righe se necessario
                          ),
                        ),
                      ],
                    ),

                    // Riga sotto: Tipo partita e indirizzo centrati
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 2),
                      child: pw.RichText(
                        textAlign: pw.TextAlign.center,
                        maxLines: 2,
                        text: pw.TextSpan(
                          children: [
                            // Tipo partita: nero, non corsivo, maiuscolo
                            pw.TextSpan(
                              text: _formatMatchTypeForDisplay(match),
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.black,
                                fontWeight: pw.FontWeight.normal,
                                fontStyle: pw.FontStyle.normal,
                              ),
                            ),
                            // Spazio più ampio intorno al trattino
                            pw.TextSpan(
                              text: '  -  ',
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.black,
                                fontWeight: pw.FontWeight.normal,
                                fontStyle: pw.FontStyle.normal,
                              ),
                            ),
                            // Indirizzo: grigio, corsivo, solo iniziali maiuscole
                            pw.TextSpan(
                              text: _toTitleCase(_getFieldNameOrAddress(match.location, fields)),
                              style: pw.TextStyle(
                                fontSize: 14,
                                color: PdfColors.grey700,
                                fontWeight: pw.FontWeight.normal,
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Logo B alla fine della card (destra) - spostato verso il bordo
              pw.Container(
                width: 70, // Area più ampia per centrare il logo
                height: 50,
                margin: const pw.EdgeInsets.only(left: 4), // Ridotto margine per spostare verso il bordo
                child: pw.Center(
                  child: pw.Container(
                    width: dynamicLogoSize,
                    height: dynamicLogoSize,
                    child: _buildCompactTeamLogo(!match.isHome ? 'AURORA SERIATE' : match.opponent, teamLogos),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  /// Costruisce la lista partite con spazio equo tra sabato e domenica
  List<pw.Widget> _buildExtendedPDFMatchListWithSpacing(List<Match> matches, List<Field> fields, Map<String, pw.MemoryImage?> teamLogos) {
    final List<pw.Widget> widgets = [];

    // Separa le partite per giorno
    final Map<int, List<Match>> matchesByWeekday = {};
    for (final match in matches) {
      final weekday = match.date.weekday;
      if (!matchesByWeekday.containsKey(weekday)) {
        matchesByWeekday[weekday] = [];
      }
      matchesByWeekday[weekday]!.add(match);
    }

    // Ordina i giorni
    final sortedWeekdays = matchesByWeekday.keys.toList()..sort();

    // Per ogni giorno della settimana
    for (int i = 0; i < sortedWeekdays.length; i++) {
      final weekday = sortedWeekdays[i];
      final dayMatches = matchesByWeekday[weekday]!;

      // Se non è il primo giorno, aggiungi spazio equo
      if (i > 0) {
        widgets.add(pw.Spacer()); // Spazio flessibile tra i giorni
      }

      // Costruisci le partite del giorno
      final dayWidgets = _buildExtendedPDFMatchList(dayMatches, fields, teamLogos);
      widgets.addAll(dayWidgets);

      // Se non è l'ultimo giorno, aggiungi spazio equo
      if (i < sortedWeekdays.length - 1) {
        widgets.add(pw.Spacer()); // Spazio flessibile tra i giorni
      }
    }

    return widgets;
  }

  PdfColor _getPDFResultColor(int auroraGoals, int opponentGoals) {
    if (auroraGoals > opponentGoals) {
      return PdfColors.green600; // Vittoria
    } else if (auroraGoals == opponentGoals) {
      return PdfColors.orange600; // Pareggio
    } else {
      return PdfColors.red600; // Sconfitta
    }
  }

  String _getEventName(Match match) {
    // Per tornei: usa il nome dal campo note se disponibile
    if (match.matchType.toLowerCase() == 'torneo' &&
        match.notes != null && match.notes!.isNotEmpty) {
      return match.notes!.trim();
    }

    // Per coppe: usa il nome dal campo note se disponibile
    if (match.matchType.toLowerCase() == 'coppa' &&
        match.notes != null && match.notes!.isNotEmpty) {
      return match.notes!.trim();
    }

    // Per campionato e amichevoli: usa il nome standard
    final matchTypeMap = {
      'campionato': 'Campionato',
      'amichevole': 'Amichevole',
    };
    return matchTypeMap[match.matchType] ?? match.matchType;
  }

  String _formatMatchTypeForDisplay(Match match) {
    if (match.matchType.toLowerCase() == 'campionato' && match.giornata != null && match.giornata!.isNotEmpty) {
      // Prova a trovare il girone della squadra
      try {
        final teamService = context.read<TeamService>();
        final team = teamService.teams.where((t) => t.category == match.auroraTeam).firstOrNull;
        final gironeText = team?.girone != null && team!.girone!.isNotEmpty ? ' (${team.girone})' : '';
        return '${match.giornata} CAMPIONATO$gironeText';
      } catch (e) {
        // Se non riesce a accedere al context, ritorna senza girone
        return '${match.giornata} CAMPIONATO';
      }
    }
    return match.matchType.toUpperCase();
  }

  String _getYearFromCategory(String category) {
    // Mappa le categorie agli anni di nascita approssimativi
    final currentYear = DateTime.now().year;
    final yearMap = {
      'U12': (currentYear - 12).toString(),
      'U14': (currentYear - 14).toString(),
      'U15': (currentYear - 15).toString(),
      'U16': (currentYear - 16).toString(),
      'U17': (currentYear - 17).toString(),
      'U18': (currentYear - 18).toString(),
      'U19': (currentYear - 19).toString(),
      'Prima Squadra': currentYear.toString(),
    };

    return yearMap[category] ?? (currentYear - 16).toString();
  }

  String _getFieldAbbreviation(String location, List<Field> fields) {
    // Cerca il campo corrispondente nella lista dei campi
    final field = fields.firstWhere(
      (f) => f.name.toLowerCase() == location.toLowerCase(),
      orElse: () => Field(id: '', name: location, address: '', code: ''),
    );

    // Restituisce i primi 3 caratteri del nome del campo
    return field.name.length >= 3 ? field.name.substring(0, 3).toUpperCase() : field.name.toUpperCase();
  }

  String _getFieldAddress(String location, List<Field> fields) {
    // Cerca il campo corrispondente nella lista dei campi
    final field = fields.firstWhere(
      (f) => f.name.toLowerCase() == location.toLowerCase(),
      orElse: () => Field(id: '', name: location, address: 'N/A', code: ''),
    );

    // Restituisce un indirizzo abbreviato (prime 15 caratteri)
    return field.address.length > 15 ? '${field.address.substring(0, 12)}...' : field.address;
  }

  String _getFieldNameOrAddress(String location, List<Field> fields) {
    // Cerca il campo corrispondente nella lista dei campi
    final field = fields.firstWhere(
      (f) => f.name.toLowerCase() == location.toLowerCase(),
      orElse: () => Field(id: '', name: location, address: '', code: ''),
    );

    // Se ha un indirizzo, lo usa, altrimenti usa il nome del campo
    if (field.address.isNotEmpty && field.address != 'N/A') {
      return field.address.length > 60 ? '${field.address.substring(0, 57)}...' : field.address;
    } else {
      return field.name;
    }
  }



  pw.Widget _buildExtendedTeamLogo(String teamName, Map<String, pw.MemoryImage?> teamLogos) {
    final cleanTeamName = _cleanTeamNameForLogo(teamName);
    final logo = teamLogos[cleanTeamName];
    if (logo != null) {
      return pw.Container(
        width: teamName == 'AURORA SERIATE' ? 65 : 60, // Aurora più grande, altri aumentati
        height: teamName == 'AURORA SERIATE' ? 65 : 60, // Aurora più grande, altri aumentati
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
    } else {
      // Se non c'è logo, restituisce spazio vuoto
      return pw.Container(
        width: teamName == 'AURORA SERIATE' ? 65 : 60,
        height: teamName == 'AURORA SERIATE' ? 65 : 60,
      );
    }
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  // Helper per ottenere abbreviazione e anno della squadra Aurora dalla categoria
  Map<String, String?> _getTeamInfo(String? auroraTeamCategory) {
    if (auroraTeamCategory == null) return {'abbreviation': null, 'year': null};

    try {
      final teamService = context.read<TeamService>();
      final teams = teamService.teams;

      // Cerca la squadra che corrisponde alla categoria Aurora
      final matchingTeam = teams.firstWhere(
        (team) => team.category.toLowerCase() == auroraTeamCategory.toLowerCase(),
        orElse: () => Team(category: ''), // Team vuoto se non trovato
      );

      if (matchingTeam.category.isNotEmpty) {
        return {
          'abbreviation': matchingTeam.abbreviation,
          'year': matchingTeam.year,
        };
      }
    } catch (e) {
      debugPrint('Errore nel recupero info squadra: $e');
    }

    return {'abbreviation': null, 'year': null};
  }

  /// Mostra l'anteprima dei risultati per Instagram
  void _showInstagramResultsPreview() async {
    final matchService = context.read<MatchService>();
    final teamService = context.read<TeamService>();
    final allMatches = matchService.matches;
    final teams = teamService.teams;

    // Calcola date di inizio e fine settimana
    final weekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
    final weekEnd = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day + 6);

    // Filtra le partite con la stessa logica del Week Match (usando il filtro AGO se selezionato)
    final filteredMatches = _getMatchesForWeek(allMatches);

    // Mostra popup di caricamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Genera l'immagine direttamente con le partite filtrate
      final imageBytes = await InstagramResultsService.generateResultsJpg(
        matches: filteredMatches,
        startDate: weekStart,
        endDate: weekEnd,
        teams: teams,
      );

      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      // Mostra l'anteprima direttamente con le partite filtrate
      await InstagramResultsService.showImagePreview(
        context,
        imageBytes,
        filteredMatches,
        weekStart,
        weekEnd,
        teams,
      );
    } catch (e) {
      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nella generazione dell\'immagine: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Mostra l'anteprima dei risultati del weekend per Instagram
  void _showInstagramWeekendPreview() async {
    final matchService = context.read<MatchService>();
    final teamService = context.read<TeamService>();
    final allMatches = matchService.matches;
    final teams = teamService.teams;

    // Calcola date di inizio e fine settimana
    final weekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
    final weekEnd = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day + 6);

    // Per weekend results, mostra TUTTE le partite senza filtro AGO
    final filteredMatches = _getAllMatchesForWeek(allMatches);

    // Mostra popup di caricamento
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Genera l'immagine weekend direttamente con le partite filtrate
      final imageBytes = await InstagramWeekendService.generateWeekendResultsJpg(
        matches: filteredMatches,
        startDate: weekStart,
        endDate: weekEnd,
        teams: teams,
      );

      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      // Mostra l'anteprima weekend direttamente con le partite filtrate
      await InstagramWeekendService.showWeekendImagePreview(
        context,
        imageBytes,
        filteredMatches,
        weekStart,
        weekEnd,
        teams,
      );
    } catch (e) {
      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nella generazione dell\'immagine weekend: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Funzione helper per caricare immagini da assets
  Future<pw.ImageProvider> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }
}