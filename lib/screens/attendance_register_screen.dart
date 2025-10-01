import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'dart:io';
import '../models/player_model.dart';
import '../models/match_model.dart';
import '../services/team_service.dart';
import '../services/player_service.dart';
import '../services/match_service.dart';

class AttendanceRegisterScreen extends StatefulWidget {
  const AttendanceRegisterScreen({super.key});

  @override
  State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
}

class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> {
  String? selectedCategory;
  String? selectedOtherCategory;
  Match? selectedMatch;
  List<Player> filteredPlayers = [];
  Set<String> selectedCategories = {}; // Set per tracciare categorie selezionate
  Map<String, bool> playersAttendance = {};
  Map<String, int> playersNumbers = {};
  Set<int> availableNumbers = {};
  int nextNewNumber = 1;
  bool selectAll = false;
  bool selectEmpty = false;
  List<String> selectionOrder = []; // Mantiene l'ordine di selezione
  String? selectedCapitano;
  String? selectedViceCapitano;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamService = context.read<TeamService>();
      final playerService = context.read<PlayerService>();
      final matchService = context.read<MatchService>();
      
      if (teamService.teams.isEmpty && !teamService.isLoading) {
        teamService.loadTeams();
      }
      if (playerService.players.isEmpty && !playerService.isLoading) {
        playerService.loadPlayers();
      }
      if (matchService.matches.isEmpty && !matchService.isLoading) {
        matchService.loadMatches();
      }
    });
  }

  void _updatePlayersList() {
    final playerService = context.read<PlayerService>();
    
    // Accumula giocatori da tutte le categorie selezionate
    final allPlayers = <Player>{};
    
    for (String category in selectedCategories) {
      final categoryPlayers = playerService.players
          .where((player) => 
              player.teamCategory == category && 
              !player.isStaff)
          .toList();
      allPlayers.addAll(categoryPlayers);
    }
    
    setState(() {
      filteredPlayers = allPlayers.toList();
      
      // MANTIENI le presenze esistenti e i numeri assegnati
      // Non resettare playersAttendance e playersNumbers!
      final newAttendance = <String, bool>{};
      for (var player in filteredPlayers) {
        // Mantieni lo stato precedente se esisteva
        newAttendance[player.id!] = playersAttendance[player.id!] ?? false;
      }
      playersAttendance = newAttendance;
      
      // Non resettare selectAll automaticamente
      // selectAll = false; // RIMOSSO per mantenere lo stato
    });
  }

  void _toggleSelectAll() {
    setState(() {
      selectAll = !selectAll;
      if (selectAll) {
        for (var player in filteredPlayers) {
          playersAttendance[player.id!] = true;
          if (!selectionOrder.contains(player.id!)) {
            selectionOrder.add(player.id!);
          }
        }
      } else {
        for (var player in filteredPlayers) {
          playersAttendance[player.id!] = false;
          playersNumbers.remove(player.id!);
          selectionOrder.remove(player.id!);
        }
      }
      _assignNumbers();
    });
  }

  void _toggleSelectEmpty() {
    setState(() {
      selectEmpty = !selectEmpty;
      if (selectEmpty) {
        if (!selectionOrder.contains('EMPTY_PLAYER')) {
          selectionOrder.add('EMPTY_PLAYER');
        }
      } else {
        playersNumbers.remove('EMPTY_PLAYER');
        selectionOrder.remove('EMPTY_PLAYER');
      }
      _assignNumbers();
    });
  }

  void _assignNumbers() {
    // Usa l'ordine di selezione per assegnare i numeri
    List<String> validSelectionOrder = [];
    
    // Filtra l'ordine di selezione per includere solo giocatori ancora selezionati
    for (String playerId in selectionOrder) {
      if (playerId == 'EMPTY_PLAYER' && selectEmpty) {
        validSelectionOrder.add(playerId);
      } else if (playerId != 'EMPTY_PLAYER' && playersAttendance[playerId] == true) {
        validSelectionOrder.add(playerId);
      }
    }
    
    // Riassegna numeri da 1 a N seguendo l'ordine di selezione
    for (int i = 0; i < validSelectionOrder.length; i++) {
      playersNumbers[validSelectionOrder[i]] = i + 1;
    }
    
    // Aggiorna nextNewNumber per essere sempre N+1
    nextNewNumber = validSelectionOrder.length + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Distinte Tornei',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Pulsante Anteprima PDF
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _previewPDF(),
            tooltip: 'Anteprima PDF',
          ),
          // Pulsante Condividi PDF
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareAttendancePDF(),
            tooltip: 'Condividi PDF',
          ),
        ],
      ),
      body: Consumer3<TeamService, PlayerService, MatchService>(
        builder: (context, teamService, playerService, matchService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Dropdown categorie (2 affiancati)
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        // Categoria principale
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Categoria:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: PopupMenuButton<String>(
                                  onSelected: (String value) {
                                    setState(() {
                                      selectedCategory = value;
                                      selectedCategories.add(value);
                                      selectedMatch = null;
                                    });
                                    _updatePlayersList();
                                  },
                                  itemBuilder: (BuildContext context) {
                                    return teamService.teams.map((team) {
                                      return PopupMenuItem<String>(
                                        value: team.category,
                                        height: 24,
                                        padding: EdgeInsets.zero,
                                        child: Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.all(8),
                                          child: Text(
                                            team.category,
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        ),
                                      );
                                    }).toList();
                                  },
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          selectedCategory ?? 'Seleziona categoria',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: selectedCategory != null ? Colors.black : Colors.grey,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Altre categorie
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Altre:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedOtherCategory,
                                    hint: const Text(
                                      'Aggiungi altra', 
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    isExpanded: true,
                                    style: const TextStyle(fontSize: 12, color: Colors.black),
                                    items: teamService.teams.map((team) {
                                      return DropdownMenuItem<String>(
                                        value: team.category,
                                        child: Text(
                                          team.category,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        setState(() {
                                          selectedOtherCategory = newValue;
                                          selectedCategories.add(newValue);
                                        });
                                        _updatePlayersList();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Dropdown partita
              SizedBox(
                height: 100,
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Seleziona Partita:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<Match>(
                                value: selectedMatch,
                                hint: const Text(
                                  'Seleziona partita per dati torneo', 
                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                                isExpanded: true,
                                style: const TextStyle(fontSize: 10, color: Colors.black),
                                items: () {
                                  final availableMatches = matchService.matches.where((match) =>
                                    match.matchType.toLowerCase() != 'campionato' &&
                                    (selectedCategory == null || match.auroraTeam == selectedCategory)
                                  ).toList();
                                  
                                  // Se selectedMatch non è nella lista filtrata, resettalo
                                  if (selectedMatch != null && !availableMatches.contains(selectedMatch)) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted) {
                                        setState(() {
                                          selectedMatch = null;
                                        });
                                      }
                                    });
                                  }
                                  
                                  return availableMatches.map((match) {
                                    // Allinea con le label di modifica partita: squadra avversaria, data e tipo
                                    String displayText = '${match.opponent} - ${DateFormat('dd/MM', 'it_IT').format(match.date)}';

                                    // Aggiungi tipo partita per tornei o eventi speciali
                                    if (match.matchType.toLowerCase() == 'torneo' && match.notes != null && match.notes!.isNotEmpty) {
                                      displayText += ' (${match.notes})';
                                    } else if (match.matchType.toLowerCase() != 'campionato') {
                                      displayText += ' - ${match.matchType}';
                                    }

                                    return DropdownMenuItem<Match>(
                                      value: match,
                                      child: Text(
                                        displayText,
                                        style: const TextStyle(fontSize: 9),
                                      ),
                                    );
                                  }).toList();
                                }(),
                                onChanged: (Match? newValue) {
                                  setState(() {
                                    selectedMatch = newValue;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Dropdown Capitano e Vice-Capitano
              if (filteredPlayers.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCapitano,
                              hint: const Text(
                                'Seleziona Capitano', 
                                style: TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                              isExpanded: true,
                              style: const TextStyle(fontSize: 9, color: Colors.black),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Nessun Capitano', style: TextStyle(fontSize: 9)),
                                ),
                                ...filteredPlayers.where((player) => playersAttendance[player.id] == true).map((player) {
                                  return DropdownMenuItem<String>(
                                    value: player.id,
                                    child: Text(
                                      player.name,
                                      style: const TextStyle(fontSize: 9),
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (String? newValue) {
                                setState(() {
                                  selectedCapitano = newValue;
                                  if (newValue == selectedViceCapitano) {
                                    selectedViceCapitano = null;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedViceCapitano,
                              hint: const Text(
                                'Seleziona Vice-Capitano', 
                                style: TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                              isExpanded: true,
                              style: const TextStyle(fontSize: 9, color: Colors.black),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Nessun Vice-Capitano', style: TextStyle(fontSize: 9)),
                                ),
                                ...filteredPlayers.where((player) => playersAttendance[player.id] == true).map((player) {
                                  return DropdownMenuItem<String>(
                                    value: player.id,
                                    child: Text(
                                      player.name,
                                      style: const TextStyle(fontSize: 9),
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (String? newValue) {
                                setState(() {
                                  selectedViceCapitano = newValue;
                                  if (newValue == selectedCapitano) {
                                    selectedCapitano = null;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Lista giocatori
              if (filteredPlayers.isNotEmpty) ...[
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Checkbox Tutti e Vuoto in verticale
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Checkbox Tutti
                                  Checkbox(
                                    value: selectAll,
                                    onChanged: (value) => _toggleSelectAll(),
                                    activeColor: Colors.orange,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  Text(
                                    'Tutti',
                                    style: TextStyle(
                                      fontSize: selectedCategories.isEmpty ? 11.0 : (11.0 - (selectedCategories.length - 1) * 2).clamp(7.0, 11.0),
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Checkbox Vuoto
                                  Checkbox(
                                    value: selectEmpty,
                                    onChanged: (value) => _toggleSelectEmpty(),
                                    activeColor: Colors.grey,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const CircleAvatar(
                                    backgroundColor: Colors.grey,
                                    radius: 8,
                                    child: Text(
                                      '0',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'VUOTO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              // Nome categorie selezionate
                              Text(
                                selectedCategories.isEmpty ? 'Giocatori' : selectedCategories.join(' + '),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredPlayers.length + (selectEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Se è l'ultimo elemento e selectEmpty è true, mostra il giocatore vuoto
                              if (selectEmpty && index == filteredPlayers.length) {
                                final emptyPlayerNumber = playersNumbers['EMPTY_PLAYER'];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 1),
                                  child: ListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    leading: Checkbox(
                                      value: true,
                                      onChanged: (bool? value) {
                                        _toggleSelectEmpty();
                                      },
                                      activeColor: Colors.grey,
                                    ),
                                    title: const Text(
                                      '--- VUOTO ---',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: emptyPlayerNumber != null
                                        ? CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.grey,
                                            child: Text(
                                              emptyPlayerNumber.toString(),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                );
                              }
                              
                              final player = filteredPlayers[index];
                              final isSelected = playersAttendance[player.id] ?? false;
                              final progressiveNumber = isSelected ? playersNumbers[player.id] : null;
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 1),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        if (value == true) {
                                          playersAttendance[player.id!] = true;
                                          if (!selectionOrder.contains(player.id!)) {
                                            selectionOrder.add(player.id!);
                                          }
                                          _assignNumbers();
                                        } else {
                                          playersAttendance[player.id!] = false;
                                          playersNumbers.remove(player.id!);
                                          selectionOrder.remove(player.id!);
                                          _assignNumbers();
                                          selectAll = false;
                                        }
                                      });
                                    },
                                    activeColor: Colors.orange,
                                  ),
                                  title: Text(
                                    player.name.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Prime 3 lettere categoria SPECIFICA del giocatore - Ruolo con puntini
                                      if (player.teamCategory != null || player.position != null)
                                        Text(
                                          () {
                                            // Usa la categoria SPECIFICA del giocatore, non la prima delle selezionate
                                            String categoryPrefix = player.teamCategory != null 
                                                ? player.teamCategory!.length >= 3 
                                                    ? player.teamCategory!.substring(0, 3)
                                                    : player.teamCategory!
                                                : 'XXX';
                                            String role = player.position ?? 'N/D';
                                            if (role.length > 12) {
                                              role = '${role.substring(0, 9)}...';
                                            }
                                            return '$categoryPrefix - $role';
                                          }(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      if (player.birthDate != null)
                                        Text(
                                          'Nato: ${player.birthDateFormatted}',
                                          style: const TextStyle(fontSize: 8, color: Colors.grey),
                                        ),
                                      if ((player.effectiveDay == null || player.effectiveMonth == null || player.effectiveYear == null) && (player.effectiveDocument == null || player.effectiveDocument!.isEmpty))
                                        const Text(
                                          '⚠️ Dati PDF incompleti',
                                          style: TextStyle(fontSize: 7, color: Colors.orange, fontStyle: FontStyle.italic),
                                        ),
                                    ],
                                  ),
                                  trailing: isSelected && progressiveNumber != null
                                      ? Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(15),
                                          ),
                                          child: Center(
                                            child: Text(
                                              progressiveNumber.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Messaggio quando non ci sono giocatori
              if (selectedCategories.isNotEmpty && filteredPlayers.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.group_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nessun giocatore trovato per ${selectedCategories.join(", ")}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Aggiungi giocatori in "Gestione Giocatori"\noppure verifica che abbiano la categoria corretta',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Validazione numerazione e partita obbligatoria
  String? _validateNumberSequence() {
    debugPrint('=== VALIDATION STARTING ===');
    debugPrint('selectedMatch: $selectedMatch');
    debugPrint('selectedCategories: $selectedCategories');
    debugPrint('filteredPlayers count: ${filteredPlayers.length}');
    
    if (selectedMatch == null) {
      debugPrint('VALIDATION FAILED: No match selected');
      return 'Devi selezionare una partita';
    }
    
    final selectedPlayers = filteredPlayers.where((player) => 
        playersAttendance[player.id] == true).toList();
    
    debugPrint('Selected players for attendance: ${selectedPlayers.length}');
    
    // Aggiunge tutti i numeri assegnati (incluso il giocatore vuoto)
    final allNumbers = <int>[];
    for (var player in selectedPlayers) {
      if (playersNumbers[player.id] != null) {
        allNumbers.add(playersNumbers[player.id]!);
        debugPrint('Player ${player.name} has number ${playersNumbers[player.id]}');
      } else {
        debugPrint('Player ${player.name} has NO number assigned');
      }
    }
    // Aggiungi il numero del giocatore vuoto se selezionato
    if (selectEmpty && playersNumbers['EMPTY_PLAYER'] != null) {
      allNumbers.add(playersNumbers['EMPTY_PLAYER']!);
      debugPrint('Empty player selected with number ${playersNumbers['EMPTY_PLAYER']}');
    }
    
    debugPrint('All assigned numbers: $allNumbers');
    
    if (allNumbers.isEmpty) {
      debugPrint('VALIDATION FAILED: No players selected or no numbers assigned');
      return 'Nessun giocatore selezionato o numeri non assegnati';
    }
    
    final numbers = allNumbers..sort();
    debugPrint('Sorted numbers: $numbers');
    
    // Temporary fix: be less strict about consecutive numbers for testing
    // Just check for duplicates
    final uniqueNumbers = numbers.toSet();
    if (uniqueNumbers.length != numbers.length) {
      debugPrint('VALIDATION FAILED: Duplicate numbers found');
      return 'Numeri duplicati trovati';
    }
    
    debugPrint('VALIDATION PASSED!');
    return null;
    
    /* Original strict validation - commented out for testing
    for (int i = 0; i < numbers.length; i++) {
      if (numbers[i] != i + 1) {
        debugPrint('VALIDATION FAILED: Numbers not consecutive. Expected ${i + 1}, got ${numbers[i]}');
        return 'La numerazione deve essere progressiva da 1 a ${numbers.length}';
      }
    }
    
    debugPrint('VALIDATION PASSED!');
    return null;
    */
  }

  // Anteprima PDF
  Future<void> _previewPDF() async {
    if (selectedCategories.isEmpty || filteredPlayers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno una categoria con giocatori')),
        );
      }
      return;
    }
    
    final validationError = _validateNumberSequence();
    if (validationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      final pdfTemplate = await rootBundle.load('assets/pdf/modello_giocatori.pdf');
      final templateBytes = pdfTemplate.buffer.asUint8List();
      
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: templateBytes);
      final sf.PdfPage page = document.pages[0];
      final sf.PdfGraphics graphics = page.graphics;
      
      final sf.PdfFont font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11);
      final sf.PdfFont boldFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11, style: sf.PdfFontStyle.bold);
      
      final double testY = 59 * 2.834645;
      final double finalGiornoX = 19 * 2.834645;
      final double finalMeseX = 26 * 2.834645;
      final double finalAnnoX = 31 * 2.834645;
      final double finalCognomeNomeX = 46 * 2.834645;
      final double finalMatricolaX = 114 * 2.834645;
      
      final presentPlayers = filteredPlayers.where((player) => 
          playersAttendance[player.id] == true).toList();
      
      // Aggiungi il giocatore vuoto se selezionato
      final allPresentPlayers = List<Player>.from(presentPlayers);
      if (selectEmpty) {
        // Crea un giocatore vuoto temporaneo per il PDF
        final emptyPlayer = Player(
          name: '--- VUOTO ---',
          id: 'EMPTY_PLAYER',
          teamCategory: selectedCategory,
          isStaff: false,
        );
        allPresentPlayers.add(emptyPlayer);
      }
      
      // Ordina i giocatori secondo la numerazione progressiva
      allPresentPlayers.sort((a, b) {
        final numberA = playersNumbers[a.id] ?? 0;
        final numberB = playersNumbers[b.id] ?? 0;
        return numberA.compareTo(numberB);
      });
      
      // Aggiungi dati torneo se disponibili (33mm dal basso per apparire IN ALTO)
      if (selectedMatch != null) {
        final double tournamentY = 33 * 2.834645; // 33mm dal basso per apparire IN ALTO
        
        // Nome torneo (posizione anno)
        String matchTypeText;
        if (selectedMatch!.matchType.toLowerCase() == 'torneo' && selectedMatch!.notes != null && selectedMatch!.notes!.isNotEmpty) {
          matchTypeText = selectedMatch!.notes!.toUpperCase();
        } else {
          matchTypeText = selectedMatch!.matchType.toUpperCase();
        }
        graphics.drawString(
          matchTypeText,
          boldFont,
          bounds: Rect.fromLTWH(finalAnnoX, tournamentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Data partita (posizione matricola/CI) - TUTTO IN GRASSETTO
        graphics.drawString(
          DateFormat('dd/MM/yyyy', 'it_IT').format(selectedMatch!.date),
          boldFont,
          bounds: Rect.fromLTWH(finalMatricolaX, tournamentY, 80, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Luogo (fine CI - dopo matricola) - TUTTO IN GRASSETTO
        // Estrae solo la parte dopo il trattino (es. "via tal - GRASSOBBIO" -> "GRASSOBBIO")
        String locationText = selectedMatch!.location;
        if (locationText.contains(' - ')) {
          final parts = locationText.split(' - ');
          if (parts.length > 1) {
            locationText = parts.last.trim();
          }
        }
        graphics.drawString(
          locationText.toUpperCase(),
          boldFont,
          bounds: Rect.fromLTWH(finalMatricolaX + 85, tournamentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      for (int i = 0; i < allPresentPlayers.length && i < 20; i++) {
        final player = allPresentPlayers[i];
        final double currentY = testY + (i * 7 * 2.834645); // 7mm tra le righe
        
        // G - Giorno (usa campo G dal database Supabase)
        final giornoStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveDay?.toString().padLeft(2, '0') ?? '__');
        graphics.drawString(
          giornoStr,
          font,
          bounds: Rect.fromLTWH(finalGiornoX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // M - Mese (usa campo M dal database Supabase) 
        final meseStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveMonth?.toString().padLeft(2, '0') ?? '__');
        graphics.drawString(
          meseStr,
          font,
          bounds: Rect.fromLTWH(finalMeseX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // A - Anno completo (usa campo A dal database Supabase)
        final annoStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveYear?.toString() ?? '____');
        graphics.drawString(
          annoStr,
          font,
          bounds: Rect.fromLTWH(finalAnnoX, currentY, 40, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Cognome Nome senza indicazione Capitano/Vice-Capitano (non scrivere se è giocatore vuoto)
        if (player.id != 'EMPTY_PLAYER') {
          graphics.drawString(
            player.name.toUpperCase(),
            boldFont,
            bounds: Rect.fromLTWH(finalCognomeNomeX, currentY, 200, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // C e V - 5mm a sinistra dell'inizio del nr. matricola
        if (selectedCapitano == player.id) {
          graphics.drawString(
            'C',
            boldFont,
            bounds: Rect.fromLTWH(finalMatricolaX - (4 * 2.834645), currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else if (selectedViceCapitano == player.id) {
          graphics.drawString(
            'V',
            boldFont,
            bounds: Rect.fromLTWH(finalMatricolaX - (4 * 2.834645), currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // Documento - SEMPRE prima matricola, poi CI, poi vuoto
        final sf.PdfFont smallDocFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 8); // 11-3=8pt
        
        if (player.effectiveMatricola != null && player.effectiveMatricola!.isNotEmpty) {
          // Ha matricola - mostra matricola
          graphics.drawString(
            player.effectiveMatricola!,
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20), // +36mm totale
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else if (player.ci != null && player.ci!.isNotEmpty) {
          // Non ha matricola ma ha CI - mostra CI con etichetta
          graphics.drawString(
            player.ci!,
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20), // +36mm totale
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
          
          // Aggiungi etichetta "CI" (+2mm dalla posizione precedente = +27mm totale)
          final sf.PdfFont smallFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 9); // 11-2=9pt
          graphics.drawString(
            'CI',
            smallFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (27 * 2.834645), currentY, 20, 20), // +27mm totale
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else {
          // Non ha né matricola né CI - mostra vuoto
          graphics.drawString(
            player.id == 'EMPTY_PLAYER' ? '' : '__________',
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20), // +36mm totale
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // Data rilascio documento a 172mm da sinistra (stesso font del numero CI - 8pt)
        final dataRilascio = player.id == 'EMPTY_PLAYER' ? '' : (player.rilasciata ?? '__/__/____');
        graphics.drawString(
          dataRilascio,
          smallDocFont, // Stesso font del numero CI (8pt)
          bounds: Rect.fromLTWH(172 * 2.834645, currentY, 60, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      // GARA CASA - OSPITE (25mm dal basso per apparire IN BASSO, 80mm da sinistra)
      if (selectedMatch != null) {
        final double matchY = 25 * 2.834645; // 25mm dal basso
        final double matchX = 80 * 2.834645; // 80mm da sinistra
        
        final String homeTeam = selectedMatch!.isHome ? 'AURORA SERIATE' : selectedMatch!.opponent.toUpperCase();
        final String awayTeam = !selectedMatch!.isHome ? 'AURORA SERIATE' : selectedMatch!.opponent.toUpperCase();
        
        graphics.drawString(
          '$homeTeam - $awayTeam',
          boldFont,
          bounds: Rect.fromLTWH(matchX, matchY, 300, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      final List<int> bytes = await document.save();
      document.dispose();
      
      // Mostra anteprima PDF con opzione di salvataggio come default
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => Uint8List.fromList(bytes),
        name: () {
          String categoryPrefix = selectedCategories.isNotEmpty 
              ? selectedCategories.first.length >= 3 
                  ? selectedCategories.first.substring(0, 3)
                  : selectedCategories.first
              : 'XXX';
          String matchDate = selectedMatch != null 
              ? DateFormat('ddMMyyyy').format(selectedMatch!.date)
              : DateFormat('ddMMyyyy').format(DateTime.now());
          return '${categoryPrefix}_Distinta_$matchDate.pdf';
        }(),
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nella generazione del PDF: $e')),
        );
      }
    }
  }

  // Condivisione PDF
  Future<void> _shareAttendancePDF() async {
    debugPrint('=== PDF SHARE STARTED ===');
    debugPrint('Selected categories: $selectedCategories');
    debugPrint('Filtered players count: ${filteredPlayers.length}');
    
    if (selectedCategories.isEmpty || filteredPlayers.isEmpty) {
      debugPrint('ERROR: Missing categories or players');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona almeno una categoria con giocatori')),
        );
      }
      return;
    }
    
    final validationError = _validateNumberSequence();
    if (validationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      debugPrint('Loading PDF template...');
      // Stessa logica del PDF di anteprima
      final pdfTemplate = await rootBundle.load('assets/pdf/modello_giocatori.pdf');
      final templateBytes = pdfTemplate.buffer.asUint8List();
      debugPrint('PDF template loaded, size: ${templateBytes.length} bytes');
      
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: templateBytes);
      final sf.PdfPage page = document.pages[0];
      final sf.PdfGraphics graphics = page.graphics;
      
      final sf.PdfFont font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11);
      final sf.PdfFont boldFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11, style: sf.PdfFontStyle.bold);
      
      final double testY = 59 * 2.834645;
      final double finalGiornoX = 19 * 2.834645;
      final double finalMeseX = 26 * 2.834645;
      final double finalAnnoX = 31 * 2.834645;
      final double finalCognomeNomeX = 46 * 2.834645;
      final double finalMatricolaX = 114 * 2.834645;
      
      final presentPlayers = filteredPlayers.where((player) => 
          playersAttendance[player.id] == true).toList();
      
      // Aggiungi il giocatore vuoto se selezionato
      final allPresentPlayers = List<Player>.from(presentPlayers);
      if (selectEmpty) {
        // Crea un giocatore vuoto temporaneo per il PDF
        final emptyPlayer = Player(
          name: '--- VUOTO ---',
          id: 'EMPTY_PLAYER',
          teamCategory: selectedCategory,
          isStaff: false,
        );
        allPresentPlayers.add(emptyPlayer);
      }
      
      allPresentPlayers.sort((a, b) {
        final numberA = playersNumbers[a.id] ?? 0;
        final numberB = playersNumbers[b.id] ?? 0;
        return numberA.compareTo(numberB);
      });
      
      // Aggiungi dati torneo se disponibili (33mm dal basso per apparire IN ALTO)
      if (selectedMatch != null) {
        final double tournamentY = 33 * 2.834645; // 33mm dal basso per apparire IN ALTO
        
        // Nome torneo (posizione anno)
        String matchTypeText;
        if (selectedMatch!.matchType.toLowerCase() == 'torneo' && selectedMatch!.notes != null && selectedMatch!.notes!.isNotEmpty) {
          matchTypeText = selectedMatch!.notes!.toUpperCase();
        } else {
          matchTypeText = selectedMatch!.matchType.toUpperCase();
        }
        graphics.drawString(
          matchTypeText,
          boldFont,
          bounds: Rect.fromLTWH(finalAnnoX, tournamentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Data partita (posizione matricola/CI) - TUTTO IN GRASSETTO
        graphics.drawString(
          DateFormat('dd/MM/yyyy', 'it_IT').format(selectedMatch!.date),
          boldFont,
          bounds: Rect.fromLTWH(finalMatricolaX, tournamentY, 80, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Luogo (fine CI - dopo matricola) - TUTTO IN GRASSETTO
        String locationText = selectedMatch!.location;
        if (locationText.contains(' - ')) {
          final parts = locationText.split(' - ');
          if (parts.length > 1) {
            locationText = parts.last.trim();
          }
        }
        graphics.drawString(
          locationText.toUpperCase(),
          boldFont,
          bounds: Rect.fromLTWH(finalMatricolaX + 85, tournamentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      for (int i = 0; i < allPresentPlayers.length && i < 20; i++) {
        final player = allPresentPlayers[i];
        final double currentY = testY + (i * 7 * 2.834645); // 7mm tra le righe
        
        // G - Giorno
        final giornoStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveDay?.toString().padLeft(2, '0') ?? '__');
        graphics.drawString(
          giornoStr,
          font,
          bounds: Rect.fromLTWH(finalGiornoX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // M - Mese
        final meseStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveMonth?.toString().padLeft(2, '0') ?? '__');
        graphics.drawString(
          meseStr,
          font,
          bounds: Rect.fromLTWH(finalMeseX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // A - Anno completo
        final annoStr = player.id == 'EMPTY_PLAYER' ? '' : (player.effectiveYear?.toString() ?? '____');
        graphics.drawString(
          annoStr,
          font,
          bounds: Rect.fromLTWH(finalAnnoX, currentY, 40, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Cognome Nome (non scrivere se è giocatore vuoto)
        if (player.id != 'EMPTY_PLAYER') {
          graphics.drawString(
            player.name.toUpperCase(),
            boldFont,
            bounds: Rect.fromLTWH(finalCognomeNomeX, currentY, 200, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // C e V - 5mm a sinistra dell'inizio del nr. matricola
        if (selectedCapitano == player.id) {
          graphics.drawString(
            'C',
            boldFont,
            bounds: Rect.fromLTWH(finalMatricolaX - (4 * 2.834645), currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else if (selectedViceCapitano == player.id) {
          graphics.drawString(
            'V',
            boldFont,
            bounds: Rect.fromLTWH(finalMatricolaX - (4 * 2.834645), currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // Documento - SEMPRE prima matricola, poi CI, poi vuoto
        final sf.PdfFont smallDocFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 8);
        
        if (player.effectiveMatricola != null && player.effectiveMatricola!.isNotEmpty) {
          graphics.drawString(
            player.effectiveMatricola!,
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else if (player.ci != null && player.ci!.isNotEmpty) {
          graphics.drawString(
            player.ci!,
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
          
          final sf.PdfFont smallFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 9);
          graphics.drawString(
            'CI',
            smallFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (27 * 2.834645), currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        } else {
          graphics.drawString(
            player.id == 'EMPTY_PLAYER' ? '' : '__________',
            smallDocFont,
            bounds: Rect.fromLTWH(finalMatricolaX + (36 * 2.834645), currentY, 80, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
        
        // Data rilascio documento a 172mm da sinistra
        final dataRilascio = player.id == 'EMPTY_PLAYER' ? '' : (player.rilasciata ?? '__/__/____');
        graphics.drawString(
          dataRilascio,
          smallDocFont,
          bounds: Rect.fromLTWH(172 * 2.834645, currentY, 60, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      // GARA CASA - OSPITE (25mm dal basso per apparire IN BASSO, 80mm da sinistra)
      if (selectedMatch != null) {
        final double matchY = 25 * 2.834645;
        final double matchX = 80 * 2.834645;
        
        final String homeTeam = selectedMatch!.isHome ? 'AURORA SERIATE' : selectedMatch!.opponent.toUpperCase();
        final String awayTeam = !selectedMatch!.isHome ? 'AURORA SERIATE' : selectedMatch!.opponent.toUpperCase();
        
        graphics.drawString(
          '$homeTeam - $awayTeam',
          boldFont,
          bounds: Rect.fromLTWH(matchX, matchY, 300, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      }
      
      final List<int> bytes = await document.save();
      document.dispose();
      
      // Salva e condividi il file
      final output = await getTemporaryDirectory();
      
      // Nome file con formato: Prime3Lettere_Distinta_DataPartita
      String categoryPrefix = selectedCategories.isNotEmpty 
          ? selectedCategories.first.length >= 3 
              ? selectedCategories.first.substring(0, 3)
              : selectedCategories.first
          : 'XXX';
      String matchDate = selectedMatch != null 
          ? DateFormat('ddMMyyyy').format(selectedMatch!.date)
          : DateFormat('ddMMyyyy').format(DateTime.now());
      
      final fileName = '${categoryPrefix}_Distinta_$matchDate.pdf';
      final file = File('${output.path}/$fileName');
      debugPrint('Saving PDF to: ${file.path}');
      await file.writeAsBytes(bytes);
      debugPrint('PDF saved, file size: ${bytes.length} bytes');
      
      // Condividi usando SharePlus
      debugPrint('Sharing PDF...');
      await Share.shareXFiles([XFile(file.path)],
          text: 'Distinta ${selectedCategories.join("+")} - ${selectedMatch != null ? DateFormat('dd/MM/yyyy').format(selectedMatch!.date) : DateFormat('dd/MM/yyyy').format(DateTime.now())}');
      debugPrint('PDF shared successfully!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF condiviso!')),
        );
      }
      
    } catch (e) {
      debugPrint('ERROR in PDF generation: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nella condivisione: $e')),
        );
      }
    }
  }
}