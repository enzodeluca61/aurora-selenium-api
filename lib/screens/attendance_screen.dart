import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../models/team_model.dart';
import '../services/attendance_service.dart';
import '../services/player_service.dart';
import '../services/team_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedMonth = DateTime.now();
  late AttendanceService _attendanceService;
  final Map<String, String> _attendanceData = {}; // Cache per i dati di presenza
  final ScrollController _horizontalScrollController = ScrollController(); // Controller per scroll sincronizzato
  final List<ScrollController> _playerScrollControllers = []; // Controller per ogni riga giocatore
  bool _isScrolling = false; // Flag per evitare loop di sincronizzazione
  String? _selectedTeam; // Team selezionato per il filtro

  @override
  void initState() {
    super.initState();
    _attendanceService = AttendanceService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playerService = context.read<PlayerService>();
      if (playerService.players.isEmpty && !playerService.isLoading) {
        playerService.loadPlayers();
      }
      _loadAttendanceForMonth();
      
      // Imposta la prima squadra come filtro predefinito
      if (playerService.players.isNotEmpty) {
        final teams = playerService.players
            .where((player) => player.teamCategory != null && player.teamCategory!.isNotEmpty)
            .map((player) => player.teamCategory)
            .toSet()
            .toList();
        // Ordina basandosi sul sort_order delle squadre nel TeamService
        final teamService = Provider.of<TeamService>(context, listen: false);
        teams.sort((a, b) {
          final teamA = teamService.teams.firstWhere((team) => team.category == a, orElse: () => Team(category: a!, sortOrder: 999));
          final teamB = teamService.teams.firstWhere((team) => team.category == b, orElse: () => Team(category: b!, sortOrder: 999));
          return teamA.sortOrder.compareTo(teamB.sortOrder);
        });
        if (teams.isNotEmpty) {
          _selectedTeam = teams.first;
        }
      }
    });
  }

  // Codici di presenza
  final Map<String, String> _attendanceCodes = {
    'P': 'Presente',
    'AI': 'Assenza Ingiustificata', 
    'AM': 'Ammalato',
    'AIN': 'Infortunato',
    'ASQ': 'Squalificato',
  };

  Future<void> _loadAttendanceForMonth() async {
    try {
      await _attendanceService.loadAttendanceForMonth(_selectedMonth);
      
      // Aggiorna la cache locale dal servizio
      _attendanceData.clear();
      for (final entry in _attendanceService.attendanceByDate.entries) {
        final dateKey = entry.key;
        for (final attendance in entry.value) {
          final cacheKey = '${attendance.playerId}_$dateKey';
          _attendanceData[cacheKey] = attendance.status.code;
        }
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nel caricamento delle presenze: $error'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _initializeScrollControllers(int playerCount) {
    // Inizializza i controller per ogni riga giocatore se necessario
    while (_playerScrollControllers.length < playerCount) {
      _playerScrollControllers.add(ScrollController());
    }
    // Rimuovi controller in eccesso
    while (_playerScrollControllers.length > playerCount) {
      _playerScrollControllers.removeLast().dispose();
    }
  }

  void _syncScrollPosition(double position) {
    if (_isScrolling) return;
    _isScrolling = true;
    
    // Sincronizza header
    if (_horizontalScrollController.hasClients && 
        (_horizontalScrollController.position.pixels - position).abs() > 1.0) {
      _horizontalScrollController.jumpTo(position.clamp(
        0.0, 
        _horizontalScrollController.position.maxScrollExtent
      ));
    }
    
    // Sincronizza tutte le righe giocatori
    for (final controller in _playerScrollControllers) {
      if (controller.hasClients && 
          (controller.position.pixels - position).abs() > 1.0) {
        controller.jumpTo(position.clamp(
          0.0, 
          controller.position.maxScrollExtent
        ));
      }
    }
    
    _isScrolling = false;
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    for (final controller in _playerScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Registro Presenze',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildMonthSelector(),
          _buildTeamFilter(),
          Expanded(
            child: Consumer<PlayerService>(
              builder: (context, playerService, child) {
                if (playerService.isLoading && playerService.players.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                return _buildAttendanceGrid(playerService);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
              });
              _loadAttendanceForMonth();
            },
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Text(
            DateFormat('MMMM yyyy', 'it_IT').format(_selectedMonth),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
              });
              _loadAttendanceForMonth();
            },
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamFilter() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Consumer<PlayerService>(
        builder: (context, playerService, child) {
          // Ottieni tutte le categorie team uniche
          final teams = playerService.players
              .map((player) => player.teamCategory)
              .where((category) => category != null && category.isNotEmpty)
              .toSet()
              .toList();
          // Ordina basandosi sul sort_order delle squadre nel TeamService
          final teamService = Provider.of<TeamService>(context, listen: false);
          teams.sort((a, b) {
            final teamA = teamService.teams.firstWhere((team) => team.category == a, orElse: () => Team(category: a!, sortOrder: 999));
            final teamB = teamService.teams.firstWhere((team) => team.category == b, orElse: () => Team(category: b!, sortOrder: 999));
            return teamA.sortOrder.compareTo(teamB.sortOrder);
          });
          
          // Imposta la prima squadra se _selectedTeam è null e ci sono squadre
          if (_selectedTeam == null && teams.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _selectedTeam = teams.first;
              });
            });
          }
          
          return DropdownButton<String?>(
            isExpanded: true,
            value: _selectedTeam,
            hint: const Text('Seleziona squadra', style: TextStyle(fontSize: 12)),
            underline: Container(),
            items: [
              ...teams.map((team) => DropdownMenuItem<String?>(
                value: team,
                child: Text(team!, style: const TextStyle(fontSize: 12)),
              )),
            ],
            onChanged: (String? newValue) {
              setState(() {
                _selectedTeam = newValue;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildAttendanceGrid(PlayerService playerService) {
    var players = playerService.players.toList();
    
    // Filtra per team se selezionato
    if (_selectedTeam != null) {
      players = players.where((player) => player.teamCategory == _selectedTeam).toList();
    }
    
    players.sort((a, b) => a.name.compareTo(b.name)); // Ordine alfabetico
    
    // Inizializza i controller per il numero di giocatori
    _initializeScrollControllers(players.length);
    
    // Calcola i giorni del mese
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Header con colonna fissa e parte scrollabile
          Container(
            height: 40,
            color: const Color(0xFF1E3A8A).withAlpha(26),
            child: Row(
              children: [
              // Colonna fissa del nome giocatore
              Container(
                width: 108,
                height: 40,
                padding: const EdgeInsets.all(4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: const Text(
                  '',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ),
              // Parte scrollabile con i giorni
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification && !_isScrolling) {
                      _syncScrollPosition(notification.metrics.pixels);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _horizontalScrollController,
                    child: Row(
                    children: List.generate(daysInMonth, (index) {
                      final day = index + 1;
                      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
                      final weekday = date.weekday;
                      final isWeekend = weekday == 6 || weekday == 7; // Sabato o Domenica
                      
                      // Nome del giorno abbreviato
                      const dayNames = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];
                      final dayLetter = dayNames[weekday - 1];
                      
                      return GestureDetector(
                        onTap: () => _markAllPlayersPresent(date),
                        child: Container(
                          width: 35,
                          height: 40,
                          padding: const EdgeInsets.all(2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isWeekend ? Colors.red[50] : Colors.white,
                            border: Border.all(color: Colors.grey[300]!, width: 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayLetter.toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 7,
                                  color: isWeekend ? Colors.red[800] : Colors.black,
                                ),
                              ),
                              Text(
                                day.toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 8,
                                  color: isWeekend ? Colors.red[800] : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
          // Lista giocatori con colonna fissa e parte scrollabile
          Expanded(
            child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: players.length,
            itemBuilder: (context, playerIndex) {
              final player = players[playerIndex];
              return SizedBox(
                height: 50,
                child: Row(
                  children: [
                    // Nome giocatore fisso
                    Container(
                      width: 108,
                      height: 50,
                      padding: const EdgeInsets.all(4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                        color: Colors.white,
                      ),
                      child: Text(
                        player.name.toUpperCase(),
                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Parte scrollabile con i giorni
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification && !_isScrolling) {
                            _syncScrollPosition(notification.metrics.pixels);
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _playerScrollControllers[playerIndex],
                          child: Row(
                          children: List.generate(daysInMonth, (dayIndex) {
                            final day = dayIndex + 1;
                            final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
                            final attendanceCode = _getAttendanceCode(player.id!, date);
                            final weekday = date.weekday;
                            final isWeekend = weekday == 6 || weekday == 7; // Sabato o Domenica
                            
                            return GestureDetector(
                              onTap: () => _showAttendanceDialog(player, date),
                              child: Container(
                                width: 35,
                                height: 50,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: attendanceCode.isEmpty 
                                      ? (isWeekend ? Colors.red[50] : Colors.white)
                                      : _getAttendanceColor(attendanceCode),
                                  border: Border.all(color: Colors.grey[300]!, width: 1),
                                ),
                                child: Text(
                                  attendanceCode,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: _getAttendanceTextColor(attendanceCode),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            ),
          ),
        ],
      ),
    );
  }

  String _getAttendanceCode(String playerId, DateTime date) {
    final key = '${playerId}_${DateFormat('yyyy-MM-dd').format(date)}';
    return _attendanceData[key] ?? '';
  }

  Future<void> _saveAttendance(String playerId, String playerName, DateTime date, String code) async {
    final key = '${playerId}_${DateFormat('yyyy-MM-dd').format(date)}';
    setState(() {
      _attendanceData[key] = code;
    });
    
    try {
      final status = AttendanceStatus.fromCode(code);
      // Salvando presenza
      
      final success = await _attendanceService.saveAttendance(date, playerId, status, null);
      
      if (!success) {
        // Rollback della cache locale se il salvataggio fallisce
        setState(() {
          _attendanceData.remove(key);
        });
        
        final errorMessage = _attendanceService.errorMessage ?? 'Errore sconosciuto nel salvataggio';
        // Errore nel salvataggio
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore nel salvataggio: $errorMessage'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        // Presenza salvata con successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Presenza salvata!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (error) {
      // Eccezione durante il salvataggio
      
      // Rollback della cache locale
      setState(() {
        _attendanceData.remove(key);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nel salvataggio: $error'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Color _getAttendanceColor(String code) {
    switch (code) {
      case 'P': return Colors.green[100]!;
      case 'AI': return Colors.red[100]!;
      case 'AM': return Colors.blue[100]!;
      case 'AIN': return Colors.purple[100]!;
      case 'ASQ': return Colors.grey[300]!;
      default: return Colors.white;
    }
  }

  Color _getAttendanceTextColor(String code) {
    switch (code) {
      case 'P': return Colors.green[800]!;
      case 'AI': return Colors.red[800]!;
      case 'AM': return Colors.blue[800]!;
      case 'AIN': return Colors.purple[800]!;
      case 'ASQ': return Colors.grey[800]!;
      default: return Colors.grey[600]!;
    }
  }

  Future<void> _markAllPlayersPresent(DateTime date) async {
    final playerService = context.read<PlayerService>();
    final players = playerService.players.toList();
    
    // Conferma dell'utente
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conferma'),
        content: Text(
          'Vuoi segnare tutti i giocatori come presenti per il ${DateFormat('dd/MM/yyyy').format(date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    
    if (shouldContinue != true) return;
    
    // Marca tutti i giocatori come presenti
    for (final player in players) {
      if (player.id != null) {
        await _saveAttendance(player.id!, player.name, date, 'P');
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tutti i giocatori sono stati segnati come presenti'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAttendanceDialog(player, DateTime date) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${player.name} - ${DateFormat('dd/MM/yyyy').format(date)}',
          style: const TextStyle(fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Seleziona il tipo di presenza:'),
            const SizedBox(height: 16),
            ..._attendanceCodes.entries.map((entry) {
              return Card(
                child: ListTile(
                  leading: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _getAttendanceColor(entry.key),
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getAttendanceTextColor(entry.key),
                      ),
                    ),
                  ),
                  title: Text(entry.value),
                  onTap: () async {
                    Navigator.pop(context);
                    await _saveAttendance(player.id!, player.name, date, entry.key);
                  },
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
  }

}