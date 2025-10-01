import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/match_model.dart';
import '../models/team_model.dart';
import '../services/match_service.dart';
import '../services/auth_service.dart';
import '../services/field_service.dart';
import '../services/team_service.dart';
import '../widgets/match_form_dialog.dart';

class MatchesCalendarScreen extends StatefulWidget {
  const MatchesCalendarScreen({super.key});

  @override
  State<MatchesCalendarScreen> createState() => _MatchesCalendarScreenState();
}

class _MatchesCalendarScreenState extends State<MatchesCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _showCalendar = true; // Vista di default: calendario
  String? _selectedTeam; // Team selezionato per il filtro (null = tutte)
  bool _onlyChampionship = false; // Filtro solo campionato (quando squadra selezionata)
  late ScrollController _scrollController;

  // Helper function per verificare se c'è una squadra selezionata
  bool get _hasSelectedTeam {
    final result = _selectedTeam != null && _selectedTeam!.isNotEmpty;
    if (kDebugMode && _selectedTeam != null) {
      print('_hasSelectedTeam: _selectedTeam=$_selectedTeam, result=$result');
    }
    return result;
  }
  String _currentVisibleMonth = ''; // Mese attualmente visibile nell'header

  @override
  void initState() {
    super.initState();
    // Imposta il giorno selezionato alla data odierna
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedDay = DateTime(now.year, now.month, now.day);
    
    // Inizializza il ScrollController
    _scrollController = ScrollController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MatchService>().loadMatches();
      // Carica anche i campi per la conversione codice -> nome
      final fieldService = context.read<FieldService>();
      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DateTime _getWeekStart(DateTime date) {
    final dayOfWeek = date.weekday;
    return DateTime(date.year, date.month, date.day - (dayOfWeek - 1));
  }

  String _getFieldDisplayName(String fieldCode) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Calendario',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 15,
            ),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E3A8A),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            // Pulsante rinumera: solo in vista elenco e con squadra selezionata
            if (!_showCalendar && _hasSelectedTeam)
              IconButton(
                onPressed: () => _showRenumberMatchdaysDialog(),
                icon: const Icon(Icons.format_list_numbered, color: Colors.white),
                tooltip: 'Rinumera Giornate ${_selectedTeam!}',
              ),
            IconButton(
              onPressed: () => _generateChampionshipPDF(),
              icon: const Icon(Icons.visibility, color: Colors.white),
              tooltip: 'Anteprima Campionato',
            ),
            IconButton(
              onPressed: () async {
                setState(() {
                  _showCalendar = !_showCalendar;
                });
                // Ricarica i match quando si cambia vista
                final matchService = context.read<MatchService>();
                await matchService.loadMatches();
              },
              icon: Icon(
                _showCalendar ? Icons.list : Icons.calendar_month,
                color: Colors.white,
              ),
              tooltip: _showCalendar ? 'Vista Lista' : 'Vista Calendario',
            ),
          ],
        ),
        body: SafeArea(
          child: Consumer3<MatchService, AuthService, FieldService>(
          builder: (context, matchService, authService, fieldService, child) {
            if (matchService.isLoading && matchService.matches.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            // Mostra la vista appropriata
            if (_showCalendar) {
              return Column(
                children: [
                  Card(
                    margin: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 4 : 8),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TableCalendar<Match>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    locale: 'it_IT',
                    eventLoader: (day) {
                      return matchService.getMatchesForDate(day);
                    },
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      weekendTextStyle: const TextStyle(color: Colors.red),
                      holidayTextStyle: const TextStyle(color: Colors.red),
                      selectedDecoration: const BoxDecoration(
                        color: Color(0xFF1E3A8A),
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      // Sistemiamo laltezza dei giorni della settimana
                      tablePadding: const EdgeInsets.all(4.0),
                      cellMargin: const EdgeInsets.all(6.0),
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                      formatButtonDecoration: BoxDecoration(
                        color: Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      formatButtonTextStyle: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      headerTitleBuilder: (context, day) {
                        return Container(
                          alignment: Alignment.center,
                          child: Text(
                            DateFormat('MMMM yy', 'it_IT').format(day),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                      dowBuilder: (context, day) {
                        // Sabato (6) e Domenica (7) in rosso, altri giorni in grigio
                        final isWeekend = day.weekday == 6 || day.weekday == 7;
                        return Container(
                          alignment: Alignment.center,
                          height: 30,
                          child: Text(
                            DateFormat('EEE', 'it_IT').format(day).toUpperCase(),
                            style: TextStyle(
                              color: isWeekend ? Colors.red : Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return null;
                        
                        // Raggruppa gli eventi per tipo per creare marker colorati
                        final Map<String, int> eventsByType = {};
                        for (final event in events) {
                          final match = event as Match;
                          eventsByType[match.matchType] = (eventsByType[match.matchType] ?? 0) + 1;
                        }
                        
                        // Crea i marker colorati
                        final List<Widget> markers = [];
                        int index = 0;
                        for (final entry in eventsByType.entries) {
                          if (index >= 3) break; // Max 3 marker per giorno
                          
                          // Se è una partita infrasettimanale (lun-ven), usa il rosso
                          final isWeekday = day.weekday >= 1 && day.weekday <= 5;
                          final markerColor = isWeekday ? Colors.red : _getMatchTypeMarkerColor(entry.key);
                          
                          markers.add(
                            Positioned(
                              bottom: 1,
                              right: 1 + (index * 8),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: markerColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          );
                          index++;
                        }
                        
                        return Stack(children: markers);
                      },
                    ),
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Mese',
                      CalendarFormat.twoWeeks: '2 settimane',  
                      CalendarFormat.week: 'Settimana',
                    },
                    selectedDayPredicate: (day) {
                      return isSameDay(_selectedDay, day);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      if (!isSameDay(_selectedDay, selectedDay)) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      }
                    },
                    onFormatChanged: (format) {
                      if (_calendarFormat != format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      }
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: _selectedDay == null
                      ? const Center(
                          child: Text('Seleziona una data per vedere le partite'),
                        )
                      : _buildMatchesList(matchService),
                ),
              ],
              );
            } else {
              // Vista lista di tutte le partite - ora con scroll infinito
              return _buildAllMatchesList(matchService);
            }
          },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddMatchDialog(),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
          tooltip: 'Aggiungi Partita',
        ),
        );
  }


  List<Match> _getFilteredMatches(List<Match> matches) {
    // RIMOZIONE FILTRO DATE: Per coerenza con il calendario, mostriamo tutte le partite
    // Il calendario mostra tutto, quindi anche l'elenco dovrebbe farlo
    var filteredMatches = matches.toList();

    // Applica il filtro della squadra se selezionata
    if (_hasSelectedTeam) {
      filteredMatches = filteredMatches.where((match) => match.auroraTeam == _selectedTeam).toList();

      // Applica il filtro "solo campionato" se attivo
      if (_onlyChampionship) {
        filteredMatches = filteredMatches.where((match) => match.matchType.toLowerCase() == 'campionato').toList();
      }
    }

    return filteredMatches;
  }

  Widget _buildTeamFilter(MatchService matchService) {
    return Consumer<TeamService>(
      builder: (context, teamService, child) {
        // Assicurati che le squadre siano caricate
        if (teamService.teams.isEmpty && !teamService.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            teamService.loadTeams();
          });
        }
        
        // Mostra loading se le squadre non sono ancora caricate
        if (teamService.isLoading) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        
        // Estrae squadre uniche dalle partite e le ordina per sort_order
        final uniqueTeams = <String>{};
        
        // Estrae squadre uniche dalle partite
        for (final match in matchService.matches) {
          if (match.auroraTeam != null && match.auroraTeam!.isNotEmpty) {
            uniqueTeams.add(match.auroraTeam!);
          }
        }
        
        // Converte in lista e ordina per sort_order
        final teams = uniqueTeams.toList()
          ..sort((a, b) {
            final teamA = teamService.teams.firstWhere(
              (team) => team.category == a, 
              orElse: () => Team(category: a, sortOrder: 999)
            );
            final teamB = teamService.teams.firstWhere(
              (team) => team.category == b, 
              orElse: () => Team(category: b, sortOrder: 999)
            );
            return teamA.sortOrder.compareTo(teamB.sortOrder);
          });
        
        return _buildDropdown(teams, teamService);
      },
    );
  }
  
  Widget _buildDropdown(List<String> teams, TeamService teamService) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      height: 50, // Altezza aumentata del dropdown
      child: Row(
        children: [
          // Dropdown squadre - sempre metà spazio
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: PopupMenuButton<String>(
                onSelected: (String value) {
                  setState(() {
                    _selectedTeam = value == 'all' ? null : value;
                    // Reset checkbox quando cambia squadra
                    if (!_hasSelectedTeam) {
                      _onlyChampionship = false;
                    }
                  });
                },
                itemBuilder: (BuildContext context) {
                  List<PopupMenuItem<String>> items = [
                    PopupMenuItem<String>(
                      value: 'all',
                      height: 35,
                      padding: EdgeInsets.zero,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: const Text(
                          'Tutte le squadre',
                          style: TextStyle(fontSize: 11, height: 1.0),
                        ),
                      ),
                    ),
                  ];

                  // Aggiungi le squadre
                  for (String teamName in teams) {
                    items.add(
                      PopupMenuItem<String>(
                        value: teamName,
                        height: 35,
                        padding: EdgeInsets.zero,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          child: Text(
                            teamName,
                            style: const TextStyle(fontSize: 11, height: 1.0),
                          ),
                        ),
                      ),
                    );
                  }

                  return items;
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedTeam ?? 'Tutte le squadre',
                        style: TextStyle(
                          fontSize: 11,
                          color: _hasSelectedTeam ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Checkbox "Campionato" - sempre presente, metà spazio
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _hasSelectedTeam
                    ? Colors.grey[50]
                    : Colors.grey[100], // Colore diverso quando inattivo
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.7,
                    child: Checkbox(
                      value: _hasSelectedTeam ? _onlyChampionship : false,
                      onChanged: _hasSelectedTeam
                          ? (value) {
                              if (kDebugMode) {
                                print('Checkbox cliccato: valore=$value, _hasSelectedTeam=$_hasSelectedTeam, _onlyChampionship prima=$_onlyChampionship');
                              }
                              setState(() {
                                _onlyChampionship = value ?? false;
                                if (kDebugMode) {
                                  print('Checkbox aggiornato: _onlyChampionship dopo=$_onlyChampionship');
                                }
                              });
                            }
                          : null, // Disabilitato quando nessuna squadra è selezionata
                      activeColor: _hasSelectedTeam ? const Color(0xFF1E3A8A) : Colors.grey,
                      checkColor: Colors.white,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      // Indica visivamente che è disabilitato
                      fillColor: MaterialStateProperty.resolveWith((states) {
                        if (!_hasSelectedTeam) {
                          return Colors.grey[300];
                        }
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFF1E3A8A);
                        }
                        return null;
                      }),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Campionato',
                      style: TextStyle(
                        fontSize: 10, // +1px
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllMatchesList(MatchService matchService) {
    return Column(
      children: [
        // Filtro squadre
        _buildTeamFilter(matchService),
        // Header fisso del mese
        _buildFixedMonthHeader(matchService),
        // Lista infinita partendo dal lunedì della settimana corrente
        Expanded(
          child: _buildInfiniteMatchesList(matchService),
        ),
      ],
    );
  }

  Widget _buildFixedMonthHeader(MatchService matchService) {
    final filteredMatches = _getFilteredMatches(matchService.matches)
      .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    
    if (filteredMatches.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Usa _currentVisibleMonth se è stato impostato, altrimenti usa la prima partita
    String displayMonth;
    if (_currentVisibleMonth.isEmpty) {
      final firstMatch = filteredMatches.first;
      displayMonth = DateFormat('MMMM yyyy', 'it_IT').format(firstMatch.date);
    } else {
      displayMonth = _currentVisibleMonth;
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        displayMonth.toUpperCase(),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildInfiniteMatchesList(MatchService matchService) {
    // Ottieni tutte le partite filtrate e ordinate per data
    final filteredMatches = _getFilteredMatches(matchService.matches)
      .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

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
              'Nessuna partita trovata',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Trova l'indice della prima partita da oggi in poi per lo scroll iniziale
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int? currentDayFirstMatchIndex;
    
    for (int i = 0; i < filteredMatches.length; i++) {
      final match = filteredMatches[i];
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      if (currentDayFirstMatchIndex == null && 
          (matchDate.isAtSameMomentAs(today) || matchDate.isAfter(today))) {
        currentDayFirstMatchIndex = i;
        debugPrint('Found first match from today at match index: $i, date: ${match.date}'); // Debug
        break;
      }
    }

    // Costruisci una lista di widget che include solo separatori settimane (no header mesi)  
    final List<Widget> widgets = [];
    final List<DateTime> matchDates = []; // Per tracking del mese visibile
    DateTime? lastWeekStart;
    int? currentDayIndex;

    for (int i = 0; i < filteredMatches.length; i++) {
      final match = filteredMatches[i];
      final matchWeekStart = _getWeekStart(match.date);
      
      // Segna l'indice quando raggiungiamo la prima partita da oggi in poi
      if (i == currentDayFirstMatchIndex) {
        currentDayIndex = widgets.length;
        debugPrint('Current day widget index: $currentDayIndex'); // Debug
      }
      
      // Aggiungi separatore blu per cambio settimana (solo se non è selezionata una squadra specifica)
      if (lastWeekStart != null &&
          !isSameDay(lastWeekStart, matchWeekStart) &&
          !_hasSelectedTeam) {
        widgets.add(
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }
      
      // Aggiungi la partita
      widgets.add(_buildCompactMatchItem(match));
      matchDates.add(match.date);
      
      lastWeekStart = matchWeekStart;
    }

    // Imposta il mese iniziale basato sulla data corrente
    if (_currentVisibleMonth.isEmpty && matchDates.isNotEmpty) {
      if (currentDayIndex != null && currentDayIndex < matchDates.length) {
        final currentDayDate = matchDates[currentDayIndex.clamp(0, matchDates.length - 1)];
        _currentVisibleMonth = DateFormat('MMMM yyyy', 'it_IT').format(currentDayDate);
      } else {
        _currentVisibleMonth = DateFormat('MMMM yyyy', 'it_IT').format(today);
      }
    }
    

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo is ScrollUpdateNotification) {
          _updateVisibleMonth(widgets, matchDates, scrollInfo.metrics.pixels);
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 2 : 4),
        itemCount: widgets.length,
        itemBuilder: (context, index) {
          return widgets[index];
        },
      ),
    );
  }

  void _updateVisibleMonth(List<Widget> widgets, List<DateTime> matchDates, double scrollOffset) {
    // Calcola approssimativamente quale partita è visibile in base allo scroll
    // Assumendo altezza media di 82px per card (80px + margini)
    const double averageItemHeight = 82.0;
    int visibleIndex = (scrollOffset / averageItemHeight).floor();
    
    // Trova il primo match dall'indice visibile
    // I separatori sono Container con decoration blu, le partite sono tutto il resto
    int matchIndex = 0;
    int widgetsSeen = 0;
    
    for (int i = 0; i < widgets.length && matchIndex < matchDates.length; i++) {
      // I separatori sono Container con decoration blu, le partite sono il resto
      Widget widget = widgets[i];
      bool isSeparator = false;
      
      if (widget is Container) {
        // Controlla se è un separatore (ha decoration con colore blu)
        if (widget.decoration != null && widget.decoration is BoxDecoration) {
          final decoration = widget.decoration as BoxDecoration;
          if (decoration.color == Colors.blue) {
            isSeparator = true;
          }
        }
      }
      
      if (!isSeparator) {
        // È una card di partita
        if (widgetsSeen >= visibleIndex) {
          break;
        }
        matchIndex++;
      }
      widgetsSeen++;
    }
    
    if (matchIndex < matchDates.length) {
      final newMonth = DateFormat('MMMM yyyy', 'it_IT').format(matchDates[matchIndex]);
      if (newMonth != _currentVisibleMonth) {
        setState(() {
          _currentVisibleMonth = newMonth;
        });
      }
    }
  }

  Widget _buildDaySection(DateTime date, MatchService matchService) {
    // Ottieni le partite per questo giorno
    final dayMatches = _getFilteredMatches(matchService.getMatchesForDate(date))
      ..sort((a, b) => a.time.compareTo(b.time));
    
    // Se non ci sono partite per questo giorno, mostra solo la data
    if (dayMatches.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Text(
              DateFormat('EEE dd/MM', 'it_IT').format(date),
              style: TextStyle(
                fontSize: 12,
                color: _getWeekdayColor(date),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    // Se ci sono partite, mostra la data come separatore e le partite
    return Column(
      children: [
        // Separatore data
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _isToday(date) ? const Color(0xFF1E3A8A) : Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            DateFormat('EEEE dd MMMM yyyy', 'it_IT').format(date).toUpperCase(),
            style: TextStyle(
              color: _isToday(date) ? Colors.white : _getWeekdayColor(date),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.left,
          ),
        ),
        // Lista partite del giorno
        ...dayMatches.map((match) => _buildCompactMatchItem(match)),
        const SizedBox(height: 1),
      ],
    );
  }
  
  bool _isToday(DateTime date) {
    final today = DateTime.now();
    return date.year == today.year &&
           date.month == today.month &&
           date.day == today.day;
  }

  Color _getWeekdayColor(DateTime date) {
    switch (date.weekday) {
      case DateTime.saturday:
        return Colors.blue[600]!; // Sabato blu
      case DateTime.sunday:
        return Colors.red[600]!; // Domenica rosso
      default:
        return Colors.grey[700]!; // Altri giorni
    }
  }

  // Resto delle funzioni rimane uguale ma con i colori categoria cambiati a blu scuro
  Widget _buildCompactMatchItem(Match match) {
    // Ottiene i campi dal servizio per la visualizzazione
    String getLocationDisplay() {
      // Se è una giornata di riposo, non mostrare informazioni sul campo
      if (match.isRest) {
        return '';
      }

      if (match.location.isEmpty) {
        return 'Campo non specificato';
      }

      try {
        final fieldService = context.read<FieldService>();
        final field = fieldService.fields.firstWhere(
          (field) => field.code == match.location,
        );
        return field.name;
      } catch (e) {
        return match.location;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0.5, horizontal: 4),
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.all(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        child: InkWell(
          onTap: () => _showEditMatchDialog(match),
          child: Container(
            height: 85,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(
                  color: _getMatchTypeMarkerColor(match.matchType),
                  width: 4,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
              // Layout: Goal(sinistra) - Squadra A - Data/Ora(centro) - Squadra B - Goal(destra)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Goal sinistra (sempre sul bordo sinistro)
                  Container(
                    width: 25,
                    child: Text(
                      match.isRest
                          ? ''
                          : match.isHome
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

                  // Squadra A (orientata verso il centro)
                  Expanded(
                    child: Text(
                      match.isHome
                          ? (match.auroraTeam ?? 'AURORA')
                          : match.opponent,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: match.isHome ? Colors.red : Colors.black,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Data e Orario al centro
                  Container(
                    width: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('dd/MM', 'it_IT').format(match.date),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getWeekdayColor(match.date),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          match.isRest ? '' : _formatTime(match.time),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3A8A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Squadra B (orientata verso il centro)
                  Expanded(
                    child: Text(
                      !match.isHome
                          ? (match.auroraTeam ?? 'AURORA')
                          : match.opponent,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: !match.isHome ? Colors.red : Colors.black,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Goal destra (sempre sul bordo destro)
                  Container(
                    width: 25,
                    child: Text(
                      match.isRest
                          ? ''
                          : !match.isHome
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

              const SizedBox(height: 0.5),

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
                  Flexible(
                    child: Text(
                      getLocationDisplay(),
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      softWrap: true,
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

  Widget _buildMatchesList(MatchService matchService) {
    final selectedMatches = matchService.getMatchesForDate(_selectedDay!)
      ..sort((a, b) => a.time.compareTo(b.time));

    if (selectedMatches.isEmpty) {
      return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
              Icons.sports_soccer,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nessuna partita il ${DateFormat('dd/MM/yyyy').format(_selectedDay!)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddMatchDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi Partita'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
            ),
          ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 4 : 8),
      itemCount: selectedMatches.length,
      itemBuilder: (context, index) {
        final match = selectedMatches[index];
        return _buildMatchCard(match);
      },
    );
  }

  Widget _buildMatchCard(Match match) {
    final matchTypeMap = {
      'campionato': 'Campionato',
      'torneo': 'Torneo', 
      'coppa': 'Coppa',
      'amichevole': 'Amichevole',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showEditMatchDialog(match),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: _getMatchTypeMarkerColor(match.matchType),
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            // Prima riga: Orario (solo se non è riposo)
            if (!match.isRest)
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ore ${_formatTime(match.time)}',
                    style: const TextStyle(
                      fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
              ),

            if (!match.isRest) const SizedBox(height: 1),

            // Seconda riga: Squadra A - Squadra B con risultati
            Row(
              children: [
                Icon(
                  Icons.sports_soccer,
                  size: 12,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: match.isRest
                            ? [
                                TextSpan(
                                  text: 'RIPOSA',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ]
                            : [
                                TextSpan(
                                  text: match.isHome ? (match.auroraTeam ?? 'AURORA') : match.opponent,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: match.isHome ? Colors.red : Colors.black,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' - ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                                TextSpan(
                                  text: !match.isHome ? (match.auroraTeam ?? 'AURORA') : match.opponent,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: !match.isHome ? Colors.red : Colors.black,
                                  ),
                                ),
                              ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                    if (!match.isRest && match.goalsAurora != null && match.goalsOpponent != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Risultato: ${match.isHome ? '${match.goalsAurora} - ${match.goalsOpponent}' : '${match.goalsOpponent} - ${match.goalsAurora}'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getResultColor(match.goalsAurora!, match.goalsOpponent!),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 3),

            // Terza riga: Campo (solo se presente e non è riposo)
            if (match.location.isNotEmpty && !match.isRest)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getFieldDisplayName(match.location),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                  ),
                ],
              ),

            if (match.location.isNotEmpty && !match.isRest) const SizedBox(height: 3),

            // Quarta riga: Tipo evento
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.event,
                  size: 12,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatMatchTypeForDisplay(match),
                  style: TextStyle(
                    fontSize: 10,
                    color: _getMatchTypeMarkerColor(match.matchType),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 3),

            // Quinta riga: Note
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.note,
                  size: 12,
                  color: match.notes != null && match.notes!.isNotEmpty
                      ? Colors.grey[600]
                      : Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  match.notes ?? 'Nessuna nota',
                  style: TextStyle(
                    fontSize: 10,
                    color: match.notes != null && match.notes!.isNotEmpty
                        ? Colors.grey[600]
                        : Colors.grey[400],
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ],
            ),
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
        return Colors.red[600]!; // Rosso
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getResultColor(int auroraGoals, int opponentGoals) {
    if (auroraGoals > opponentGoals) {
      return Colors.red[600]!; // Vittoria
    } else if (auroraGoals == opponentGoals) {
      return Colors.orange[600]!; // Pareggio
    } else {
      return Colors.red[600]!; // Sconfitta
    }
  }

  void _showAddMatchDialog() {
    _showFullMatchFormDialog();
  }
  
  void _showFullMatchFormDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return MatchFormDialog(
          selectedDate: _selectedDay ?? DateTime.now(),
          onSave: (match) async {
            final matchService = context.read<MatchService>();
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final success = await matchService.addMatch(match);
            
            navigator.pop();
            if (success) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Partita aggiunta con successo!')), 
              );
            } else {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(matchService.errorMessage ?? 'Errore sconosciuto'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      },
    );
  }

  void _showEditMatchDialog(Match match) {
    showDialog(
      context: context,
      builder: (context) => MatchFormDialog(
        selectedDate: match.date,
        match: match,
        onSave: (updatedMatch) async {
          if (kDebugMode) {
            debugPrint('=== DIALOG ONSAVE CALLED ===');
            debugPrint('Updated Match: ${updatedMatch.toJson()}');
            debugPrint('===========================');
          }
          
          final matchService = context.read<MatchService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await matchService.updateMatch(updatedMatch);

          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Partita aggiornata con successo!')), 
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(matchService.errorMessage ?? 'Errore nell aggiornamento'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onDelete: () => _showDeleteMatchDialog(match),
      ),
    );
  }

  void _showDeleteMatchDialog(Match match) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text('Sei sicuro di voler eliminare la partita vs ${match.opponent}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final matchService = context.read<MatchService>();

              navigator.pop();
              final success = await matchService.deleteMatch(match.id!);
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Partita eliminata con successo!')), 
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  void _showMatchDetails(Match match) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${match.auroraTeam ?? "Aurora"} vs ${match.opponent}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data: ${DateFormat('dd/MM/yyyy').format(match.date)}',
              style: const TextStyle(fontSize: 14),
            ),
            if (!match.isRest)
              Text(
                'Ora: ${_formatTime(match.time)}',
                style: const TextStyle(fontSize: 14),
              ),
            if (!match.isRest)
              Text(
                'Campo: ${_getFieldDisplayName(match.location)}',
                style: const TextStyle(fontSize: 14),
              ),
            Text(
              'Tipo: ${_formatMatchTypeForDisplay(match)}',
              style: const TextStyle(fontSize: 14),
            ),
            if (!match.isRest && match.goalsAurora != null && match.goalsOpponent != null)
              Text(
                'Risultato: ${match.goalsAurora} - ${match.goalsOpponent}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            if (match.notes != null && match.notes!.isNotEmpty)
              Text(
                'Note: ${match.notes}',
                style: const TextStyle(fontSize: 14),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
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

  Color _getMatchTypeMarkerColor(String matchType) {
    switch (matchType.toLowerCase()) {
      case 'campionato':
        return const Color(0xFF1E3A8A); // Blu
      case 'amichevole':
        return Colors.green[600]!; // Verde
      default:
        // Tutti gli altri tipi (da nomi_tornei) in arancione
        return Colors.orange[600]!; // Arancione
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

  Future<void> _generateChampionshipPDF() async {
    try {
      final matchService = context.read<MatchService>();
      
      // Filtra da oggi a fine campionato e include solo partite con includeInPlanning = true
      final today = DateTime.now();
      final startDate = DateTime(today.year, today.month, today.day, 0, 0, 0);
      
      // Fine campionato: assumiamo giugno dell'anno seguente se siamo nella stagione corrente
      final currentYear = today.month >= 8 ? today.year : today.year - 1;
      final endOfSeason = DateTime(currentYear + 1, 6, 30, 23, 59, 59);
      
      var seasonMatches = matchService.matches.where((match) {
        final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
        
        // Filtra da oggi a fine stagione E per includeInPlanning
        return matchDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
               matchDate.isBefore(endOfSeason.add(const Duration(days: 1))) &&
               match.includeInPlanning;
      }).toList();
      
      // Applica il filtro squadra se selezionata (come nella vista lista)
      if (_hasSelectedTeam) {
        seasonMatches = seasonMatches.where((match) => match.auroraTeam == _selectedTeam).toList();
      }
      
      if (seasonMatches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessuna partita trovata da oggi a fine stagione'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Ordina per data e ora
      seasonMatches.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.time.compareTo(b.time);
      });

      // Genera PDF per l'anteprima con paginazione
      final pdf = pw.Document();
      const int matchesPerPage = 20; // Numero massimo di partite per pagina
      
      // Calcola il numero di pagine necessarie
      final totalPages = (seasonMatches.length / matchesPerPage).ceil();
      
      for (int pageNum = 0; pageNum < totalPages; pageNum++) {
        final startIndex = pageNum * matchesPerPage;
        final endIndex = (startIndex + matchesPerPage > seasonMatches.length) 
            ? seasonMatches.length 
            : startIndex + matchesPerPage;
        
        final pageMatches = seasonMatches.sublist(startIndex, endIndex);
        
        pdf.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(40),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Titolo (solo nella prima pagina)
                  if (pageNum == 0) ...[
                    pw.Center(
                      child: pw.Text(
                        'CALENDARIO PARTITE DI CAMPIONATO',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                      ),
                    ),
                    if (_hasSelectedTeam) ...[
                      pw.SizedBox(height: 10),
                      pw.Center(
                        child: pw.Text(
                          'Squadra: $_selectedTeam',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 30),
                  ],
                  // Tabella partite senza bordi
                  pw.Expanded(
                    child: pw.Table(
                      columnWidths: const {
                        0: pw.FlexColumnWidth(0.6), // G.ta
                        1: pw.FlexColumnWidth(0.8), // Data
                        2: pw.FlexColumnWidth(0.7), // Ora
                        3: pw.FlexColumnWidth(4), // Partita (Casa - Ospite + indirizzo)
                      },
                      children: [
                        // Header della tabella (in ogni pagina)
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                              child: pw.Text(
                                'G.ta',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                              child: pw.Text(
                                'Data',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                              child: pw.Text(
                                'Ora',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                              child: pw.Text(
                                'Partita',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Righe delle partite per questa pagina
                        ...pageMatches.asMap().entries.map((entry) {
                          final pageIndex = entry.key;
                          final globalIndex = startIndex + pageIndex;
                          final match = entry.value;
                          
                          // Determina squadra casa e squadra fuori
                          final homeTeam = match.isHome ? (match.auroraTeam ?? 'AURORA') : match.opponent;
                          final awayTeam = match.isHome ? match.opponent : (match.auroraTeam ?? 'AURORA');
                          
                          // Determina se la partita appartiene alla squadra selezionata
                          final isSelectedTeamMatch = _hasSelectedTeam &&
                              match.auroraTeam == _selectedTeam;
                          
                          return pw.TableRow(
                            children: [
                              // G.ta (numero progressivo globale)
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                                child: pw.Text(
                                  '${globalIndex + 1}ª',
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Data
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                                child: pw.Text(
                                  DateFormat('dd/MM', 'it_IT').format(match.date),
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Ora
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                                child: pw.Text(
                                  match.isRest ? '' : _formatTime(match.time),
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Partita unificata con indirizzo sotto
                              pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    // Prima riga: squadre
                                    pw.Text(
                                      match.isRest ? 'RIPOSA' : '${match.isHome ? 'AURORA SERIATE' : match.opponent} - ${match.isHome ? match.opponent : 'AURORA SERIATE'}',
                                      style: pw.TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                      ),
                                    ),
                                    // Seconda riga: tipo partita con giornata se campionato
                                    pw.SizedBox(height: 2),
                                    pw.Text(
                                      _formatMatchTypeForPDF(match),
                                      style: pw.TextStyle(
                                        fontSize: 10,
                                        fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                      ),
                                    ),
                                    // Terza riga: indirizzo se presente e non è riposo
                                    if (match.location.isNotEmpty && !match.isRest) ...[
                                      pw.SizedBox(height: 2),
                                      pw.Text(
                                        match.location,
                                        style: pw.TextStyle(
                                          fontSize: 9,
                                          fontStyle: pw.FontStyle.italic,
                                          fontWeight: isSelectedTeamMatch ? pw.FontWeight.bold : pw.FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  // Numero pagina (se ci sono più pagine)
                  if (totalPages > 1) ...[
                    pw.SizedBox(height: 20),
                    pw.Center(
                      child: pw.Text(
                        'Pagina ${pageNum + 1} di $totalPages',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      }

      // Mostra anteprima PDF invece di stampare direttamente
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text(
                'Anteprima PDF Planning',
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
              build: (format) async {
                return await pdf.save();
              },
              canChangePageFormat: false,
              canChangeOrientation: false,
              pdfFileName: 'calendario_campionato_${DateFormat('yyyy_MM', 'it_IT').format(_focusedDay)}.pdf',
            ),
          ),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nella generazione del PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatMatchTypeForPDF(Match match) {
    if (match.matchType.toLowerCase() == 'campionato' && match.giornata != null && match.giornata!.isNotEmpty) {
      return '${match.giornata} CAMPIONATO';
    }
    return match.matchType.toUpperCase();
  }

  String _formatMatchTypeForDisplay(Match match) {
    if (kDebugMode && match.matchType.toLowerCase() == 'campionato') {
      debugPrint('Formatting display for campionato: giornata=${match.giornata}');
    }
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

  void _showRenumberMatchdaysDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Rinumera Giornate Campionato',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Questa operazione rinumerà tutte le giornate di CAMPIONATO della squadra ${_selectedTeam!} basandosi sulla data.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            const Text(
              '• Solo partite di CAMPIONATO della squadra selezionata',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Text(
              '• Partite entro il 31/12: suffisso A (andata)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Text(
              '• Partite dal 01/01: suffisso R (ritorno)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Text(
              '• Ogni data diversa = nuova giornata',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            const Text(
              'Vuoi continuare?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _renumberMatchdays();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Rinumera'),
          ),
        ],
      ),
    );
  }

  Future<void> _renumberMatchdays() async {
    try {
      final matchService = context.read<MatchService>();

      // Mostra loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Ottieni solo le partite di campionato della squadra selezionata
      final championshipMatches = matchService.matches
          .where((match) =>
              match.matchType.toLowerCase() == 'campionato' &&
              match.auroraTeam == _selectedTeam)
          .toList();

      if (championshipMatches.isEmpty) {
        Navigator.of(context).pop(); // Chiudi loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nessuna partita di campionato trovata per ${_selectedTeam!}'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Ordina per data
      championshipMatches.sort((a, b) => a.date.compareTo(b.date));

      // Trova l'anno della stagione (basato sulla prima partita)
      final firstMatchDate = championshipMatches.first.date;
      final seasonYear = firstMatchDate.month >= 8 ? firstMatchDate.year : firstMatchDate.year - 1;
      final endOfAndata = DateTime(seasonYear, 12, 31, 23, 59, 59);

      if (kDebugMode) {
        debugPrint('=== RINUMERAZIONE GIORNATE ===');
        debugPrint('Prima partita: ${firstMatchDate}');
        debugPrint('Anno stagione: $seasonYear');
        debugPrint('Fine andata: $endOfAndata');
        debugPrint('=============================');
      }

      // Separa andata e ritorno in base alla data
      final andataMatches = championshipMatches.where((m) => m.date.isBefore(endOfAndata.add(const Duration(days: 1)))).toList();
      final ritornoMatches = championshipMatches.where((m) => m.date.isAfter(endOfAndata)).toList();

      if (kDebugMode) {
        debugPrint('Partite andata: ${andataMatches.length}');
        debugPrint('Partite ritorno: ${ritornoMatches.length}');
      }

      // Rinumera l'andata (A)
      int giornataNumber = 1;
      for (int i = 0; i < andataMatches.length; i++) {
        final match = andataMatches[i];

        // Se non è la prima partita e la data è diversa dal match precedente, incrementa la giornata
        if (i > 0) {
          final prevMatch = andataMatches[i - 1];
          final currentDate = DateTime(match.date.year, match.date.month, match.date.day);
          final prevDate = DateTime(prevMatch.date.year, prevMatch.date.month, prevMatch.date.day);

          if (!currentDate.isAtSameMomentAs(prevDate)) {
            giornataNumber++;
          }
        }

        final newGiornata = '${giornataNumber}A';

        // Aggiorna solo se diverso
        if (match.giornata != newGiornata) {
          final updatedMatch = match.copyWith(giornata: newGiornata);
          await matchService.updateMatch(updatedMatch);
        }
      }

      // Rinumera il ritorno (R)
      giornataNumber = 1;
      for (int i = 0; i < ritornoMatches.length; i++) {
        final match = ritornoMatches[i];

        // Se non è la prima partita del ritorno e la data è diversa dal match precedente, incrementa la giornata
        if (i > 0) {
          final prevMatch = ritornoMatches[i - 1];
          final currentDate = DateTime(match.date.year, match.date.month, match.date.day);
          final prevDate = DateTime(prevMatch.date.year, prevMatch.date.month, prevMatch.date.day);

          if (!currentDate.isAtSameMomentAs(prevDate)) {
            giornataNumber++;
          }
        }

        final newGiornata = '${giornataNumber}R';

        // Aggiorna solo se diverso
        if (match.giornata != newGiornata) {
          final updatedMatch = match.copyWith(giornata: newGiornata);
          await matchService.updateMatch(updatedMatch);
        }
      }

      Navigator.of(context).pop(); // Chiudi loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${championshipMatches.length} partite di ${_selectedTeam!} rinumerate: ${andataMatches.length} andata (A), ${ritornoMatches.length} ritorno (R)'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      Navigator.of(context).pop(); // Chiudi loading se aperto
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante la rinumerazione: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

}