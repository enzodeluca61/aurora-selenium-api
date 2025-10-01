import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../models/player_model.dart';
import '../models/match_model.dart';
import '../models/convocation_model.dart';
import '../services/team_service.dart';
import '../services/player_service.dart';
import '../services/match_service.dart';
import '../services/convocation_service.dart';

class ConvocationsScreen extends StatefulWidget {
  const ConvocationsScreen({super.key});

  @override
  State<ConvocationsScreen> createState() => _ConvocationsScreenState();
}

class _ConvocationsScreenState extends State<ConvocationsScreen> {
  String? selectedCategory;
  String? selectedMatchId;
  Match? selectedMatch;
  String? selectedOtherCategory;
  String meetingTime = '';
  String equipment = '';
  int meetingHour = 15; // Ora di default
  int meetingMinute = 30; // Minuti di default (08:30 come default)
  List<Player> filteredPlayers = [];
  Map<String, bool> playersAttendance = {};
  Map<String, int> playersNumbers = {}; // Mappa giocatore -> numero progressivo
  Set<int> availableNumbers = {}; // Numeri liberi da riutilizzare
  int nextNewNumber = 1; // Prossimo numero nuovo da assegnare
  bool selectAll = false;
  

  @override
  void initState() {
    super.initState();
    // Inizializza l'orario con i valori di default (15:30)
    meetingTime = '${meetingHour.toString().padLeft(2, '0')}:${meetingMinute.toString().padLeft(2, '0')}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamService = context.read<TeamService>();
      final playerService = context.read<PlayerService>();
      final matchService = context.read<MatchService>();
      final convocationService = context.read<ConvocationService>();
      
      if (teamService.teams.isEmpty && !teamService.isLoading) {
        teamService.loadTeams();
      }
      if (playerService.players.isEmpty && !playerService.isLoading) {
        playerService.loadPlayers();
      }
      if (matchService.matches.isEmpty && !matchService.isLoading) {
        matchService.loadMatches();
      }
      if (convocationService.convocations.isEmpty && !convocationService.isLoading) {
        convocationService.loadConvocations();
      }
    });
  }

  void _updatePlayersList() {
    if (selectedCategory == null) {
      setState(() {
        filteredPlayers = [];
        playersAttendance = {};
      });
      return;
    }

    debugPrint('=== UPDATING PLAYERS LIST ===');
    debugPrint('Selected category: "$selectedCategory"');

    final playerService = context.read<PlayerService>();
    debugPrint('Total players in service: ${playerService.players.length}');
    
    if (playerService.players.isNotEmpty) {
      debugPrint('Sample players categories:');
      for (var i = 0; i < playerService.players.length && i < 5; i++) {
        final p = playerService.players[i];
        debugPrint('  "${p.name}" -> category: "${p.teamCategory}", isStaff: ${p.isStaff}');
      }
    }
    
    // Filtra giocatori per categoria selezionata (esclude staff)
    List<Player> players = playerService.players
        .where((player) => 
            player.teamCategory == selectedCategory && 
            !player.isStaff)
        .toList();
    
    // Aggiungi giocatori di altre categorie se selezionato
    if (selectedOtherCategory != null) {
      final otherPlayers = playerService.players
          .where((player) => 
              player.teamCategory == selectedOtherCategory && 
              !player.isStaff &&
              !players.any((p) => p.id == player.id)) // Evita duplicati
          .toList();
      players.addAll(otherPlayers);
    }
    
    // Ordina i giocatori: prima categoria principale, poi altra categoria
    players.sort((a, b) {
      if (a.teamCategory == selectedCategory && b.teamCategory != selectedCategory) {
        return -1; // a viene prima (categoria principale)
      } else if (a.teamCategory != selectedCategory && b.teamCategory == selectedCategory) {
        return 1; // b viene prima (categoria principale)
      } else {
        return a.name.compareTo(b.name); // Ordine alfabetico all'interno della stessa categoria
      }
    });
    
    debugPrint('Found ${players.length} players for category "$selectedCategory"');

    setState(() {
      filteredPlayers = players;
      _loadExistingConvocations(players);
    });
  }

  void _loadExistingConvocations(List<Player> players) {
    final convocationService = context.read<ConvocationService>();
    
    // Initialize all checkboxes as unselected first
    playersAttendance = {
      for (var player in players) player.id!: false
    };
    playersNumbers = {};
    availableNumbers = {};
    nextNewNumber = 1;
    selectAll = false;

    // Non caricare automaticamente le convocazioni esistenti
    // Tutti i giocatori rimangono non selezionati

    // Update nextNewNumber
    nextNewNumber = 1;
    
    // Check if all players are selected
    final totalPlayers = players.length;
    final selectedPlayers = playersAttendance.values.where((selected) => selected).length;
    selectAll = totalPlayers > 0 && selectedPlayers == totalPlayers;
  }

  void _toggleSelectAll() {
    setState(() {
      selectAll = !selectAll;
      if (selectAll) {
        // Controlla se si superano i 20 atleti
        if (filteredPlayers.length > 20) {
          selectAll = false; // Reset dello stato
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossibile selezionare tutti: ${filteredPlayers.length} atleti superano il limite di 20'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return; // Non procedere con la selezione
        }
        
        // Seleziona tutti assegnando numeri progressivi
        int currentNumber = 1;
        for (var player in filteredPlayers) {
          playersAttendance[player.id!] = true;
          playersNumbers[player.id!] = currentNumber++;
          _saveConvocation(player, true);
        }
      } else {
        // Deseleziona tutti e resetta numerazione
        for (var player in filteredPlayers) {
          playersAttendance[player.id!] = false;
          _saveConvocation(player, false);
        }
        playersNumbers = {};
        availableNumbers = {};
        nextNewNumber = 1;
      }
    });
  }

  Future<void> _saveConvocation(Player player, bool isConvocated) async {
    final convocationService = context.read<ConvocationService>();
    
    // Find existing convocation for this player and match
    final existingConvocation = convocationService.convocations
        .where((c) => c.playerId == player.id! && c.matchId == selectedMatchId)
        .firstOrNull;

    if (existingConvocation != null) {
      // Update existing convocation
      final updatedConvocation = existingConvocation.copyWith(
        isConvocated: isConvocated,
        convocatedAt: isConvocated ? DateTime.now() : null,
        meetingTime: meetingTime.isNotEmpty ? meetingTime : null,
        equipment: equipment.isNotEmpty ? equipment : null,
      );
      await convocationService.updateConvocation(updatedConvocation);
    } else if (isConvocated) {
      // Create new convocation only if player is being convocated
      final newConvocation = Convocation(
        playerId: player.id!,
        playerName: player.name,
        matchId: selectedMatchId,
        isConvocated: isConvocated,
        convocatedAt: DateTime.now(),
        meetingTime: meetingTime.isNotEmpty ? meetingTime : null,
        equipment: equipment.isNotEmpty ? equipment : null,
      );
      await convocationService.addConvocation(newConvocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Convocazioni',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (selectedCategory != null && selectedMatchId != null && filteredPlayers.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.article, color: Colors.white),
              onPressed: () => _previewConvocationPDF(),
              tooltip: 'Anteprima Convocazione',
            ),
          ],
        ],
      ),
      body: Consumer4<TeamService, PlayerService, MatchService, ConvocationService>(
        builder: (context, teamService, playerService, matchService, convocationService, child) {
          if (teamService.isLoading && teamService.teams.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (teamService.teams.isEmpty) {
            return const Center(
              child: Text(
                'Nessuna categoria disponibile',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Dropdown per selezionare categoria e altra categoria
                Row(
                  children: [
                    // Categoria principale
                    Expanded(
                      flex: 1,
                      child: InkWell(
                        onTap: () {}, // Will be handled by PopupMenuButton
                        child: Container(
                          height: 56, // Altezza fissa per uniformità
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Categoria principale *',
                              prefixIcon: Icon(Icons.group, size: 20),
                              border: OutlineInputBorder(),
                              labelStyle: TextStyle(fontSize: 10),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          child: PopupMenuButton<String>(
                            onSelected: (String value) {
                              setState(() {
                                selectedCategory = value;
                                selectedMatchId = null;
                                selectedMatch = null;
                                selectedOtherCategory = null; // Reset altre categorie
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
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    child: Text(
                                      team.category,
                                      style: const TextStyle(fontSize: 10, height: 1.0),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
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
                                      fontSize: 10,
                                      color: selectedCategory != null ? Colors.black : Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Altra categoria
                    Expanded(
                      flex: 1,
                      child: InkWell(
                        onTap: () {}, // Will be handled by PopupMenuButton
                        child: Container(
                          height: 56, // Altezza fissa per uniformità
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Altra categoria',
                              prefixIcon: Icon(Icons.group_add, size: 20),
                              border: OutlineInputBorder(),
                              labelStyle: TextStyle(fontSize: 10),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              fillColor: selectedMatchId == null ? Colors.grey.shade100 : null,
                              filled: selectedMatchId == null,
                            ),
                          child: PopupMenuButton<String>(
                            onSelected: selectedMatchId == null ? null : (String value) {
                              setState(() {
                                selectedOtherCategory = value;
                              });
                              _updatePlayersList();
                            },
                            itemBuilder: (BuildContext context) {
                              if (selectedMatchId == null) return [];
                              return teamService.teams
                                  .where((team) => team.category != selectedCategory)
                                  .map((team) {
                                return PopupMenuItem<String>(
                                  value: team.category,
                                  height: 24,
                                  padding: EdgeInsets.zero,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    child: Text(
                                      team.category,
                                      style: const TextStyle(fontSize: 10, height: 1.0),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                );
                              }).toList();
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedOtherCategory ?? 'Opzionale',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: selectedOtherCategory != null ? Colors.black : Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Dropdown per selezionare la partita (mostrato solo se categoria è selezionata)
                if (selectedCategory != null) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {}, // Will be handled by PopupMenuButton
                    child: Container(
                      height: 56, // Altezza fissa per uniformità
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Partita *',
                          prefixIcon: Icon(Icons.sports_soccer, size: 20),
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(fontSize: 10),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      child: PopupMenuButton<String>(
                        onSelected: (String value) {
                          setState(() {
                            selectedMatchId = value;
                            selectedMatch = matchService.matches.firstWhere(
                              (match) => match.id == value,
                              orElse: () => matchService.matches.first,
                            );

                            // Calcola automaticamente l'orario di convocazione (orario partita - 90 minuti)
                            if (selectedMatch != null && selectedMatch!.time.isNotEmpty) {
                              final matchTime = selectedMatch!.time;
                              final parts = matchTime.split(':');
                              if (parts.length == 2) {
                                final matchHour = int.tryParse(parts[0]) ?? 15;
                                final matchMinute = int.tryParse(parts[1]) ?? 0;

                                // Sottrae 90 minuti
                                final matchDateTime = DateTime(2023, 1, 1, matchHour, matchMinute);
                                final convocationDateTime = matchDateTime.subtract(const Duration(minutes: 90));

                                meetingTime = '${convocationDateTime.hour.toString().padLeft(2, '0')}:${convocationDateTime.minute.toString().padLeft(2, '0')}';
                                meetingHour = convocationDateTime.hour;
                                meetingMinute = convocationDateTime.minute;
                              }
                            }
                          });
                        },
                        itemBuilder: (BuildContext context) {
                          return matchService.matches
                              .where((match) {
                                // Filtra per categoria
                                final categoryMatch = match.auroraTeam == selectedCategory || match.auroraTeam == null;
                                // Filtra per data (solo da oggi in avanti)
                                final today = DateTime.now();
                                final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
                                final todayDate = DateTime(today.year, today.month, today.day);
                                final futureMatch = matchDate.isAfter(todayDate) || matchDate.isAtSameMomentAs(todayDate);

                                return categoryMatch && futureMatch;
                              })
                              .map((match) {
                                  String matchText;
                                  if (match.isHome) {
                                    // Partita in casa: AS vs AVVERSARIO
                                    matchText = '${DateFormat('dd/MM').format(match.date)} AS vs ${match.opponent.toUpperCase()}';
                                  } else {
                                    // Partita in trasferta: AVVERSARIO vs AS
                                    matchText = '${DateFormat('dd/MM').format(match.date)} ${match.opponent.toUpperCase()} vs AS';
                                  }
                                  
                            return PopupMenuItem<String>(
                              value: match.id,
                              height: 24,
                              padding: EdgeInsets.zero,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                child: Text(
                                  matchText,
                                  style: const TextStyle(fontSize: 10, height: 1.0),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            );
                          }).toList();
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedMatchId != null
                                  ? (() {
                                      final match = matchService.matches.firstWhere(
                                        (m) => m.id == selectedMatchId,
                                        orElse: () => matchService.matches.first,
                                      );
                                      return match.isHome
                                        ? '${DateFormat('dd/MM').format(match.date)} AS vs ${match.opponent.toUpperCase()}'
                                        : '${DateFormat('dd/MM').format(match.date)} ${match.opponent.toUpperCase()} vs AS';
                                    })()
                                  : 'Seleziona partita',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: selectedMatchId != null ? Colors.black : Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                        ),
                    ),
                  ),
                ],

                  const SizedBox(height: 6),

                  // Campi per orario ritrovo e dotazione (mostrati solo se partita è selezionata)
                  if (selectedMatchId != null) ...[
                    Card(
                      elevation: 2,
                      child: Container(
                        constraints: const BoxConstraints(
                          maxHeight: 120, // Altezza ridotta per evitare overflow
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 16.0), // Padding ridotto
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dettagli Convocazione:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => _showTimePickerDialog(),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                top: -8,
                                                left: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  color: Colors.white,
                                                  child: const SizedBox.shrink(),
                                                ),
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    meetingTime.isNotEmpty ? meetingTime : 'Seleziona orario',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: meetingTime.isNotEmpty ? Colors.black : Colors.grey,
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.access_time,
                                                    color: Colors.blue,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: InkWell(
                                        onTap: () => _showEquipmentDialog(),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                top: -8,
                                                left: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  color: Colors.white,
                                                  child: const SizedBox.shrink(),
                                                ),
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      equipment.isNotEmpty ? equipment : 'Inserisci dotazione',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                        color: equipment.isNotEmpty ? Colors.black : Colors.grey,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.sports_soccer,
                                                    color: Colors.green,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                const SizedBox(height: 6),

                // Listbox giocatori con checkbox (mostrato solo se categoria e partita sono selezionate)
                if (selectedCategory != null && selectedMatchId != null && filteredPlayers.isNotEmpty) ...[
                  Expanded( // Expanded al posto di SizedBox per usare tutto lo spazio disponibile
                    child: Card(
                      elevation: 2,
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Padding ridotto
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Giocatori',
                                    style: const TextStyle(
                                      fontSize: 14, // Font size ridotto
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: selectAll,
                                      onChanged: (value) => _toggleSelectAll(),
                                      activeColor: Colors.green,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const Text(
                                      'Tutti',
                                      style: TextStyle(
                                        fontSize: 11, // Font size ancora più piccolo
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: filteredPlayers.length,
                              itemBuilder: (context, index) {
                                final player = filteredPlayers[index];
                                final isSelected = playersAttendance[player.id] ?? false;
                                final progressiveNumber = isSelected ? playersNumbers[player.id] : null;
                                
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 2), // Margini ridotti
                                  child: ListTile(
                                    leading: Checkbox(
                                      value: isSelected,
                                      onChanged: (bool? value) {
                                        setState(() {
                                          if (value == true) {
                                            // Controlla se si superano i 20 atleti
                                            final currentSelected = playersAttendance.values.where((selected) => selected == true).length;
                                            if (currentSelected >= 20) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Massimo 20 atleti consentiti per la convocazione'),
                                                  backgroundColor: Colors.red,
                                                  duration: Duration(seconds: 3),
                                                ),
                                              );
                                              return; // Non permettere la selezione
                                            }
                                            
                                            // Seleziona giocatore e assegna numero
                                            playersAttendance[player.id!] = true;
                                            
                                            int numberToAssign;
                                            if (availableNumbers.isNotEmpty) {
                                              // Riutilizza il numero più piccolo disponibile
                                              final sortedAvailable = availableNumbers.toList()..sort();
                                              numberToAssign = sortedAvailable.first;
                                              availableNumbers.remove(numberToAssign);
                                            } else {
                                              // Assegna il prossimo numero nuovo
                                              numberToAssign = nextNewNumber++;
                                            }
                                            
                                            playersNumbers[player.id!] = numberToAssign;
                                            _saveConvocation(player, true);
                                          } else {
                                            // Deseleziona giocatore e libera il numero
                                            playersAttendance[player.id!] = false;
                                            final freedNumber = playersNumbers[player.id!];
                                            playersNumbers.remove(player.id!);
                                            
                                            // Aggiungi il numero liberato ai disponibili
                                            if (freedNumber != null) {
                                              availableNumbers.add(freedNumber);
                                            }
                                            
                                            selectAll = false;
                                            _saveConvocation(player, false);
                                          }
                                        });
                                      },
                                      activeColor: Colors.green,
                                    ),
                                    title: Text(
                                      player.name.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Badge categoria se diversa da quella principale
                                        if (player.teamCategory != selectedCategory) ...[
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.blue.shade300, width: 0.5),
                                            ),
                                            child: Text(
                                              player.teamCategory ?? '',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.blue.shade700,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                        ],
                                        // Ruolo giocatore
                                        if (player.position != null && player.position!.isNotEmpty)
                                          Text(
                                            player.position!,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.blue,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: isSelected && progressiveNumber != null
                                        ? Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: Colors.green,
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
                                    dense: true,
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
                if (selectedCategory != null && selectedMatchId != null && filteredPlayers.isEmpty)
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
                            'Nessun giocatore trovato per \$selectedCategory',
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

                // Messaggio quando categoria è selezionata ma partita no
                if (selectedCategory != null && selectedMatchId == null)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sports_soccer,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Seleziona una partita per continuare',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Scegli la partita per cui vuoi creare la convocazione',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Rinumera automaticamente i giocatori selezionati in sequenza
  String? _validateNumberSequence() {
    final selectedPlayers = filteredPlayers.where((player) => 
        playersAttendance[player.id] == true).toList();
    
    if (selectedPlayers.isEmpty) {
      return 'Nessun giocatore selezionato';
    }
    
    // Ordina i giocatori selezionati per il loro numero attuale
    selectedPlayers.sort((a, b) {
      final numberA = playersNumbers[a.id] ?? 0;
      final numberB = playersNumbers[b.id] ?? 0;
      return numberA.compareTo(numberB);
    });
    
    // Rinumera automaticamente in sequenza 1, 2, 3...
    for (int i = 0; i < selectedPlayers.length; i++) {
      playersNumbers[selectedPlayers[i].id!] = i + 1;
    }
    
    // Reset dei numeri disponibili e nextNewNumber
    availableNumbers.clear();
    nextNewNumber = selectedPlayers.length + 1;
    
    return null; // Tutto ok dopo la rinumerazione
  }

  // Anteprima PDF convocazione con il nuovo layout
  Future<void> _previewConvocationPDF() async {
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
      await _generateConvocationPDFDocument();
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

  // Genera documento PDF convocazione
  Future<void> _generateConvocationPDFDocument() async {
    if (selectedCategory == null || selectedMatchId == null || selectedMatch == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona categoria e partita')),
        );
      }
      return;
    }
    
    // Valida numerazione progressiva
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
      // Crea nuovo documento PDF
      final sf.PdfDocument document = sf.PdfDocument();
      final sf.PdfPage page = document.pages.add();
      final sf.PdfGraphics graphics = page.graphics;
      
      // Definisci font
      final sf.PdfFont headerFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 24, style: sf.PdfFontStyle.bold);
      final sf.PdfFont titleFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 16, style: sf.PdfFontStyle.bold);
      final sf.PdfFont boldFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10, style: sf.PdfFontStyle.bold);
      final sf.PdfFont boldItalicFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 9, style: sf.PdfFontStyle.bold);
      final sf.PdfFont normalFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 9);
      final sf.PdfFont playerNameFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10, style: sf.PdfFontStyle.bold);
      
      // Colori
      final blackBrush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));
      final blueBrush = sf.PdfSolidBrush(sf.PdfColor(0, 100, 200));
      
      // Margini: 1cm = 28.35 punti, 0.5cm = 14.175 punti, 0.3cm = 8.5 punti, 0.2cm = 5.67 punti, 0.1cm = 2.84 punti
      const double topMargin = 2.84; // 0.1cm dall'alto
      const double leftMargin = 28.35; // 1cm da sinistra
      const double rightMargin = 500;
      
      double currentY = topMargin;
      
      // Carica e disegna il logo Aurora a sinistra e a destra
      try {
        final logoData = await rootBundle.load('assets/images/aurora_logo.png');
        final logoImage = sf.PdfBitmap(logoData.buffer.asUint8List());
        
        // Disegna logo a sinistra: 55x70 punti (proporzioni corrette)
        graphics.drawImage(
          logoImage,
          Rect.fromLTWH(leftMargin, currentY, 55, 70),
        );
        
        // Disegna logo a destra: 55x70 punti (proporzioni corrette)
        graphics.drawImage(
          logoImage,
          Rect.fromLTWH(rightMargin - 55, currentY, 55, 70),
        );
      } catch (e) {
        print('Errore caricamento logo: $e');
      }
      
      // Titolo CONVOCAZIONE al centro, sulla stessa linea del logo
      const String convocationTitle = 'CONVOCAZIONE';
      final sf.PdfStringFormat centerFormat = sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center);
      graphics.drawString(
        convocationTitle,
        headerFont,
        bounds: Rect.fromLTWH(leftMargin, currentY + 20, rightMargin - leftMargin, 30), // Centrato verticalmente con loghi più alti
        brush: blueBrush,
        format: centerFormat,
      );
      
      currentY += 45; // Spazio dopo i loghi (aumentato di 5px)
      
      // Categoria in blu grassetto sotto CONVOCAZIONE - interlinea minima
      graphics.drawString(
        selectedCategory!.toUpperCase(),
        titleFont,
        bounds: Rect.fromLTWH(leftMargin, currentY, rightMargin - leftMargin, 25),
        brush: blueBrush,
        format: centerFormat,
      );
      
      currentY += 25; // Spazio ridotto tra categoria e squadre
      
      // Squadra vs Squadra - rispetta casa/trasferta (senza categoria)
      String matchTitle;
      if (selectedMatch!.isHome) {
        // Aurora gioca in casa
        matchTitle = 'AURORA SERIATE 1967 vs ${selectedMatch!.opponent.toUpperCase()}';
      } else {
        // Aurora gioca in trasferta
        matchTitle = '${selectedMatch!.opponent.toUpperCase()} vs AURORA SERIATE 1967';
      }
      
      graphics.drawString(
        matchTitle,
        titleFont,
        bounds: Rect.fromLTWH(leftMargin, currentY, rightMargin - leftMargin, 25), // Altezza per singola riga
        brush: blackBrush,
        format: centerFormat,
      );
      
      currentY += 32; // Spazio tra squadre e tabella info
      
      // Informazioni partita in tabella senza bordi a due colonne
      final sf.PdfFont infoFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12, style: sf.PdfFontStyle.bold);
      const double labelColumnWidth = 140;
      const double valueColumnStart = leftMargin + labelColumnWidth + 10;
      const double infoRowHeight = 17;
      
      final List<Map<String, String>> matchInfo = [
        {'label': 'Giorno:', 'value': DateFormat('EEEE dd MMMM yyyy', 'it_IT').format(selectedMatch!.date).toUpperCase()},
        {'label': 'Orario di ritrovo:', 'value': meetingTime.isNotEmpty ? meetingTime : 'Da definire'},
        {'label': 'Orario inizio gara:', 'value': _formatTime(selectedMatch!.time)},
        {'label': 'Indirizzo del campo:', 'value': selectedMatch!.location},
        {'label': 'Dotazione:', 'value': equipment.isNotEmpty ? equipment.toUpperCase() : 'DIVISA COMPLETA'},
      ];
      
      for (Map<String, String> info in matchInfo) {
        // Altezza dinamica per la riga dotazione
        double currentRowHeight = infoRowHeight;
        if (info['label'] == 'Dotazione:') {
          currentRowHeight = infoRowHeight * 3; // Tripla altezza per la dotazione
        }
        
        // Prima colonna - etichetta
        graphics.drawString(
          info['label']!,
          infoFont,
          bounds: Rect.fromLTWH(leftMargin, currentY, labelColumnWidth, currentRowHeight),
          brush: blackBrush,
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.left),
        );
        
        // Seconda colonna - valore con text wrapping per dotazione
        final sf.PdfStringFormat valueFormat = sf.PdfStringFormat(
          alignment: sf.PdfTextAlignment.left,
          lineAlignment: sf.PdfVerticalAlignment.top,
        );
        
        graphics.drawString(
          info['value']!,
          infoFont,
          bounds: Rect.fromLTWH(valueColumnStart, currentY, rightMargin - valueColumnStart, currentRowHeight),
          brush: blackBrush,
          format: valueFormat,
        );
        
        currentY += currentRowHeight;
      }
      
      currentY += 5; // Spazio dimezzato prima della tabella atleti
      
      // Tabella giocatori - allineata a sinistra con Note allargata
      const double rowHeight = 25; // Altezza righe tabella atleti aumentata
      const double numberWidth = 40;
      const double nameWidth = 180; // Colonna nome
      final double noteWidth = rightMargin - leftMargin - numberWidth - nameWidth; // Note fino al margine destro
      const double tableLeftMargin = 28.35; // Allineata a sinistra (stesso del leftMargin)
      
      final double totalTableWidth = numberWidth + nameWidth + noteWidth;
      
      // Header tabella
      graphics.drawRectangle(
        brush: sf.PdfSolidBrush(sf.PdfColor(230, 230, 230)),
        bounds: Rect.fromLTWH(tableLeftMargin, currentY, totalTableWidth, rowHeight),
      );
      
      // Bordi header
      graphics.drawRectangle(
        pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(tableLeftMargin, currentY, numberWidth, rowHeight),
      );
      graphics.drawRectangle(
        pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(tableLeftMargin + numberWidth, currentY, nameWidth, rowHeight),
      );
      graphics.drawRectangle(
        pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + nameWidth, currentY, noteWidth, rowHeight),
      );
      
      // Testo header
      graphics.drawString(
        'Nr.',
        boldFont,
        bounds: Rect.fromLTWH(tableLeftMargin + 5, currentY + 5, numberWidth - 10, rowHeight - 10),
        brush: blackBrush,
        format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
      );
      graphics.drawString(
        'Cognome e Nome',
        boldFont,
        bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + 5, currentY + 5, nameWidth - 10, rowHeight - 10),
        brush: blackBrush,
        format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
      );
      graphics.drawString(
        'Note',
        boldFont,
        bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + nameWidth + 5, currentY + 5, noteWidth - 10, rowHeight - 10),
        brush: blackBrush,
        format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
      );
      
      currentY += rowHeight;
      
      // Righe giocatori (tutti i giocatori, ordinati per numerazione)
      final presentPlayers = filteredPlayers.where((player) => 
          playersAttendance[player.id] == true).toList();
      final absentPlayers = filteredPlayers.where((player) => 
          playersAttendance[player.id] != true).toList();
      
      // Ordina presentPlayers per numerazione
      presentPlayers.sort((a, b) {
        final numberA = playersNumbers[a.id] ?? 0;
        final numberB = playersNumbers[b.id] ?? 0;
        return numberA.compareTo(numberB);
      });
      
      // Ordina absentPlayers per nome
      absentPlayers.sort((a, b) => a.name.compareTo(b.name));
      
      // Solo i giocatori convocati, poi righe vuote fino a 20
      final maxRows = 20;
      final playersToShow = presentPlayers;
      
      for (int i = 0; i < playersToShow.length; i++) {
        final player = playersToShow[i];
        final isConvocated = playersAttendance[player.id] == true;
        final progressiveNumber = isConvocated ? playersNumbers[player.id] : null;
        
        // Bordi cella
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin, currentY, numberWidth, rowHeight),
        );
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin + numberWidth, currentY, nameWidth, rowHeight),
        );
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + nameWidth, currentY, noteWidth, rowHeight),
        );
        
        // Numero progressivo
        graphics.drawString(
          progressiveNumber?.toString() ?? '',
          normalFont,
          bounds: Rect.fromLTWH(tableLeftMargin + 5, currentY + 5, numberWidth - 10, rowHeight - 10),
          brush: blackBrush,
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Nome giocatore
        graphics.drawString(
          player.name.toUpperCase(),
          playerNameFont,
          bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + 5, currentY + 5, nameWidth - 10, rowHeight - 10),
          brush: blackBrush,
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.left),
        );
        
        // Colonna Note - mostra categoria se diversa da quella principale
        if (player.teamCategory != selectedCategory) {
          graphics.drawString(
            player.teamCategory ?? '',
            normalFont,
            bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + nameWidth + 5, currentY + 5, noteWidth - 10, rowHeight - 10),
            brush: blackBrush, // Nero come richiesto
            format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.left),
          );
        }
        // Resto dello spazio vuoto per annotazioni manuali
        
        currentY += rowHeight;
      }
      
      // Aggiungi righe vuote fino a 20 righe totali
      for (int i = playersToShow.length; i < maxRows; i++) {
        // Bordi cella vuota
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin, currentY, numberWidth, rowHeight),
        );
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin + numberWidth, currentY, nameWidth, rowHeight),
        );
        graphics.drawRectangle(
          pen: sf.PdfPen(sf.PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(tableLeftMargin + numberWidth + nameWidth, currentY, noteWidth, rowHeight),
        );
        
        currentY += rowHeight;
      }
      
      // Salva il documento per l'anteprima
      final List<int> bytes = await document.save();
      document.dispose();
      
      // Chiudi popup di caricamento
      Navigator.of(context).pop();

      // Mostra anteprima PDF con possibilità di condivisione
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text(
                'Anteprima Convocazione',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.green,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: PdfPreview(
              build: (format) async => Uint8List.fromList(bytes),
              actions: const [],
              canChangePageFormat: false,
              canChangeOrientation: false,
              pdfFileName: 'Convocazione_${selectedCategory}_${DateFormat('dd-MM-yyyy').format(selectedMatch!.date)}_vs_${selectedMatch!.opponent.replaceAll(' ', '_')}.pdf',
            ),
          ),
        ),
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nella generazione del PDF: \$e')),
        );
      }
    }
  }

  // Mostra popup elegante per selezione orario ritrovo
  Future<void> _showTimePickerDialog() async {
    // Genera tutti gli orari disponibili da 08:30 a 21:00 con step di 15 minuti
    List<String> availableTimes = [];
    
    for (int hour = 8; hour <= 21; hour++) {
      List<int> minutes = (hour == 8) ? [30, 45] : (hour == 21) ? [0] : [0, 15, 30, 45];
      
      for (int minute in minutes) {
        availableTimes.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
      }
    }
    
    String? selectedTime = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.access_time,
                color: Colors.blue,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Seleziona Ritrovo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: availableTimes.length,
              itemBuilder: (context, index) {
                final time = availableTimes[index];
                final isSelected = time == meetingTime;
                
                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop(time);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Annulla',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop('15:30'); // Default se nessuna selezione
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Default (15:30)'),
            ),
          ],
        );
      },
    );
    
    if (selectedTime != null) {
      setState(() {
        meetingTime = selectedTime;
        // Aggiorna anche le variabili hour e minute per coerenza
        final parts = selectedTime.split(':');
        meetingHour = int.parse(parts[0]);
        meetingMinute = int.parse(parts[1]);
      });
    }
  }

  Future<void> _showEquipmentDialog() async {
    TextEditingController equipmentController = TextEditingController(text: equipment);
    
    String? selectedEquipment = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.sports_soccer,
                color: Colors.green,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Dotazione Richiesta',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: equipmentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'es. Divisa completa, scarpe da calcio, parastinchi',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                    fillColor: Colors.grey.shade50,
                    filled: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Esempi comuni:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.unfold_more,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Scorri per vedere tutti',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 150, // Altezza fissa per la listbox
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200, width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 1,
                      children: [
                        _buildEquipmentChip('Borraccia', equipmentController),
                        _buildEquipmentChip('Kway', equipmentController),
                        _buildEquipmentChip('Scarpe da ginnastica', equipmentController),
                        _buildEquipmentChip('Scarpe per erba artificiale', equipmentController),
                        _buildEquipmentChip('Scarpe per erba naturale', equipmentController),
                        _buildEquipmentChip('Documento di identità', equipmentController),
                        _buildEquipmentChip('Pallone', equipmentController),
                        _buildEquipmentChip('Parastinchi', equipmentController),
                        _buildEquipmentChip('Calzettoni rossi', equipmentController),
                        _buildEquipmentChip('Calzettoni blu', equipmentController),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Annulla',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(equipmentController.text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Conferma'),
            ),
          ],
        );
      },
    );
    
    if (selectedEquipment != null) {
      setState(() {
        equipment = selectedEquipment;
      });
    }
  }

  Widget _buildEquipmentChip(String text, TextEditingController controller) {
    return GestureDetector(
      onTap: () {
        if (controller.text.isEmpty) {
          controller.text = text;
        } else {
          controller.text += ', $text';
        }
      },
      child: Chip(
        label: Text(
          text,
          style: const TextStyle(fontSize: 10, height: 1.1),
        ),
        backgroundColor: Colors.green.shade50,
        side: BorderSide(color: Colors.green.shade200),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      ),
    );
  }

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
}
