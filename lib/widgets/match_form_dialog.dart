import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_model.dart';
import '../models/team_model.dart';
import '../models/field_model.dart';
import '../services/team_service.dart';
import '../services/field_service.dart';

class MatchFormDialog extends StatefulWidget {
  final DateTime selectedDate;
  final Match? match;
  final Function(Match) onSave;
  final Function()? onDelete;

  const MatchFormDialog({
    super.key,
    required this.selectedDate,
    this.match,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<MatchFormDialog> createState() => _MatchFormDialogState();
}

class _MatchFormDialogState extends State<MatchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _opponentController;
  late TextEditingController _timeController;
  late TextEditingController _locationController;
  late TextEditingController _notesController;
  late TextEditingController _goalsAuroraController;
  late TextEditingController _goalsOpponentController;
  late TextEditingController _giornataController;
  late DateTime _selectedDate;
  late bool _isHome;
  late bool _isRest;
  late String _matchType;
  String? _selectedAuroraTeam;
  String? _selectedFieldId;
  List<Map<String, String>> _tournaments = [];

  String _formatTimeToHHMM(String? time) {
    if (time == null || time.isEmpty) return '15:00';

    // Se già nel formato corretto, restituisci così com'è
    final timeRegex = RegExp(r'^(\d{1,2}):(\d{1,2})$');
    final match = timeRegex.firstMatch(time);

    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    // Se il formato non è valido, restituisci default
    return '15:00';
  }

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    
    // Non usiamo più lastMatchDetails per ora
    final Map<String, dynamic>? lastMatchDetails = null;

    _opponentController = TextEditingController(text: match?.opponent ?? '');
    _timeController = TextEditingController(text: _formatTimeToHHMM(match?.time ?? lastMatchDetails?['time']));
    _locationController = TextEditingController(text: match?.location ?? lastMatchDetails?['location'] ?? '');
    _notesController = TextEditingController(text: match?.notes ?? '');
    _goalsAuroraController = TextEditingController(text: match?.goalsAurora?.toString() ?? '');
    _goalsOpponentController = TextEditingController(text: match?.goalsOpponent?.toString() ?? '');
    _giornataController = TextEditingController(text: match?.giornata?.toString() ?? '');
    _selectedDate = match?.date ?? lastMatchDetails?['date'] ?? widget.selectedDate;
    _isHome = match?.isHome ?? lastMatchDetails?['isHome'] ?? true;
    _isRest = match?.isRest ?? lastMatchDetails?['isRest'] ?? false;
    _matchType = match?.matchType ?? lastMatchDetails?['matchType'] ?? 'campionato';
    _selectedAuroraTeam = match?.auroraTeam ?? lastMatchDetails?['auroraTeam'];
    _selectedFieldId = null; // Verrà impostato dopo il caricamento dei campi
    
    // Load teams, fields and tournament names when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamService = context.read<TeamService>();
      if (teamService.teams.isEmpty && !teamService.isLoading) {
        teamService.loadTeams();
      }

      final fieldService = context.read<FieldService>();
      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields().then((_) {
          // Dopo aver caricato i campi, imposta automaticamente il campo se stiamo modificando
          _autoSelectFieldForExistingMatch();
        });
      } else {
        // Se i campi sono già caricati, imposta immediatamente
        _autoSelectFieldForExistingMatch();
      }

      // Carica i nomi dei tornei
      _loadTournamentNames();
    });
  }

  @override
  void dispose() {
    _opponentController.dispose();
    _timeController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _goalsAuroraController.dispose();
    _goalsOpponentController.dispose();
    _giornataController.dispose();
    super.dispose();
  }

  void _autoSelectFieldForExistingMatch() {
    if (widget.match != null && widget.match!.location.isNotEmpty && _selectedFieldId == null) {
      final fieldService = context.read<FieldService>();
      if (fieldService.fields.isNotEmpty) {
        // Prova prima a fare un match esatto con il codice
        var matchedField = fieldService.fields.firstWhere(
          (field) => field.code.toUpperCase() == widget.match!.location.toUpperCase(),
          orElse: () => Field(id: '', name: '', address: '', code: ''),
        );
        
        // Se non trova un match esatto, prova a cercare per nome parziale
        if (matchedField.id?.isEmpty ?? true) {
          matchedField = fieldService.fields.firstWhere(
            (field) => field.name.toUpperCase().contains(widget.match!.location.toUpperCase()) ||
                       field.code.toUpperCase().contains(widget.match!.location.toUpperCase()),
            orElse: () => Field(id: '', name: '', address: '', code: ''),
          );
        }
        
        if (mounted) {
          setState(() {
            if (matchedField.id != null && matchedField.id!.isNotEmpty) {
              _selectedFieldId = matchedField.id;
            } else {
              _selectedFieldId = 'manual';
            }
          });
        }
      }
    }
  }

  Future<void> _loadTournamentNames() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('nomi_tornei')
          .select('nome')
          .order('nome');

      if (mounted) {
        setState(() {
          _tournaments = (response as List)
              .map((item) => {
                // Usiamo il nome originale come valore per evitare problemi con il database
                'value': item['nome'] as String,
                'display': item['nome'] as String,
              })
              .toList();

          // Ordiniamo alfabeticamente per nome
          _tournaments.sort((a, b) => a['display']!.compareTo(b['display']!));
        });
      }
    } catch (e) {
      // Se la tabella non esiste o c'è un errore, continua con i valori di default
      print('Error loading tournament names: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      title: Text(
        widget.match == null ? 'Nuova Partita' : 'Modifica Partita',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer2<TeamService, FieldService>(
                  builder: (context, teamService, fieldService, child) {
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // const Text('Squadra Aurora *', style: TextStyle(fontSize: 10)),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () {}, // Will be handled by PopupMenuButton
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Squadra Aurora Seriate *',
                                  prefixIcon: Icon(Icons.sports_soccer, size: 20),
                                  border: OutlineInputBorder(),
                                  labelStyle: TextStyle(fontSize: 10),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                child: PopupMenuButton<String>(
                            onSelected: (String value) {
                              setState(() {
                                _selectedAuroraTeam = value;
                              });
                            },
                            itemBuilder: (BuildContext context) {
                              return teamService.teams.map((Team team) {
                                return PopupMenuItem<String>(
                                  value: team.category,
                                  height: 24,
                                  padding: EdgeInsets.zero,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    child: Text(
                                      team.category,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList();
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedAuroraTeam ?? 'Seleziona squadra Aurora',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _selectedAuroraTeam != null ? Colors.black : Colors.grey,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                              ),
                            ),
                        if (_selectedAuroraTeam == null || _selectedAuroraTeam!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(left: 12, top: 4),
                            child: Text(
                              'Seleziona la squadra Aurora',
                              style: TextStyle(color: Colors.red, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _opponentController,
                  decoration: const InputDecoration(
                    labelText: 'Squadra Avversaria *',
                    prefixIcon: Icon(Icons.sports_soccer_outlined, size: 20),
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(fontSize: 10),
                  ),
                  style: const TextStyle(fontSize: 10),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    _opponentController.value = _opponentController.value.copyWith(
                      text: value.toUpperCase(),
                      selection: _opponentController.selection,
                    );
                  },
                  validator: (value) {
                    if (!_isRest && (value == null || value.isEmpty)) {
                      return 'Inserisci la squadra avversaria';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDate(),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data Partita',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(fontSize: 10),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          ),
                          child: Text(
                            DateFormat('dd/MM/yy').format(_selectedDate),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                    // Nascondi il campo orario se è una giornata di riposo
                    if (!_isRest) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectTime(),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Orario *',
                              prefixIcon: Icon(Icons.access_time),
                              border: OutlineInputBorder(),
                              labelStyle: TextStyle(fontSize: 10),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            ),
                            child: Text(
                              _timeController.text.isEmpty ? 'es. 15:00' : _timeController.text,
                              style: TextStyle(
                                fontSize: 10,
                                color: _timeController.text.isEmpty ? Colors.grey : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // const Text('Tipo Partita:', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: 'casa',
                                groupValue: _isRest ? 'riposa' : (_isHome ? 'casa' : 'trasferta'),
                                onChanged: (value) {
                                  setState(() {
                                    _isRest = false;
                                    _isHome = true;
                                    // Reset squadra avversaria se era RIPOSA
                                    if (_opponentController.text == 'RIPOSA') {
                                      _opponentController.clear();
                                    }
                                    // Se era riposo, resetta orario se vuoto
                                    if (_timeController.text.isEmpty) {
                                      _timeController.text = '15:00';
                                    }
                                  });
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const Text('Casa', style: TextStyle(fontSize: 9)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: 'trasferta',
                                groupValue: _isRest ? 'riposa' : (_isHome ? 'casa' : 'trasferta'),
                                onChanged: (value) {
                                  setState(() {
                                    _isRest = false;
                                    _isHome = false;
                                    // Reset squadra avversaria se era RIPOSA
                                    if (_opponentController.text == 'RIPOSA') {
                                      _opponentController.clear();
                                    }
                                    // Se era riposo, resetta orario se vuoto
                                    if (_timeController.text.isEmpty) {
                                      _timeController.text = '15:00';
                                    }
                                  });
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const Text('Trasf.', style: TextStyle(fontSize: 9)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: 'riposa',
                                groupValue: _isRest ? 'riposa' : (_isHome ? 'casa' : 'trasferta'),
                                onChanged: (value) {
                                  setState(() {
                                    _isRest = true;
                                    _isHome = true; // Default value per database
                                    _opponentController.text = 'RIPOSA';
                                    _timeController.clear();
                                    _locationController.clear();
                                    _selectedFieldId = null;
                                    // Pulisci anche i goal quando si seleziona RIPOSA
                                    _goalsAuroraController.clear();
                                    _goalsOpponentController.clear();
                                    // Imposta automaticamente campionato per RIPOSA se non è già un campionato
                                    if (_matchType != 'campionato') {
                                      _matchType = 'campionato';
                                    }
                                  });
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const Text('Riposa', style: TextStyle(fontSize: 9)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Campo Tipo Partita
                    Expanded(
                      flex: _matchType == 'campionato' ? 2 : 1,
                      child: InkWell(
                        onTap: () {}, // Will be handled by PopupMenuButton
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tipo Partita',
                            prefixIcon: Icon(Icons.event, size: 20),
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(fontSize: 10),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          child: PopupMenuButton<String>(
                    onSelected: (String value) {
                      setState(() {
                        _matchType = value;
                      });
                    },
                    itemBuilder: (BuildContext context) {
                      List<PopupMenuItem<String>> items = [
                        // Solo valori di default: campionato e amichevole
                        PopupMenuItem<String>(
                          value: 'campionato',
                          height: 24,
                          padding: EdgeInsets.zero,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: const Text('CAMPIONATO', style: TextStyle(fontSize: 10, height: 1.0)),
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'amichevole',
                          height: 24,
                          padding: EdgeInsets.zero,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: const Text('AMICHEVOLE', style: TextStyle(fontSize: 10, height: 1.0)),
                          ),
                        ),
                      ];

                      // Aggiungi un separatore se ci sono tornei dal database
                      if (_tournaments.isNotEmpty) {
                        items.add(
                          const PopupMenuItem<String>(
                            enabled: false,
                            height: 20,
                            child: Divider(height: 1),
                          ),
                        );
                      }

                      // Aggiungi tutti i tornei dal database (incluse coppe, tornei, etc.)
                      for (var tournament in _tournaments) {
                        items.add(
                          PopupMenuItem<String>(
                            value: tournament['value'],
                            height: 24,
                            padding: EdgeInsets.zero,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              child: Text(tournament['display']!, style: const TextStyle(fontSize: 10, height: 1.0)),
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
                            _getMatchTypeDisplayName(_matchType),
                            style: TextStyle(
                              fontSize: 10,
                              color: _matchType.isNotEmpty ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                    ),
                        ),
                      ),
                    ),
                    // Campo Giornata (per campionato o giornata di riposo)
                    if (_matchType == 'campionato' || _isRest) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _giornataController,
                          decoration: const InputDecoration(
                            labelText: 'Giornata',
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(fontSize: 8),
                            hintText: '1A',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          ),
                          style: const TextStyle(fontSize: 10),
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          validator: (value) {
                            if ((_matchType == 'campionato' || _isRest) && value != null && value.isNotEmpty) {
                              final regex = RegExp(r'^\d+[AR]$');
                              if (!regex.hasMatch(value.toUpperCase())) {
                                return 'Formato: 1A o 1R';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                // Nascondi completamente i campi campo da gioco se è una giornata di riposo
                if (!_isRest) ...[
                  const SizedBox(height: 12),
                  // Campo per selezione campo da gioco
                  Consumer<FieldService>(
                    builder: (context, fieldService, child) {
                      return _buildFieldSelector(fieldService);
                    },
                  ),
                  // Campo di testo che appare solo se selezionata l'opzione manuale
                  if (_selectedFieldId == 'manual') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Nome Campo *',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                        labelStyle: TextStyle(fontSize: 12),
                        hintText: 'es. Centro Sportivo Comunale',
                      ),
                      style: const TextStyle(fontSize: 12),
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) {
                        if (!_isRest && _selectedFieldId == 'manual' && (value == null || value.isEmpty)) {
                          return 'Inserisci il nome del campo';
                        }
                        return null;
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Note (opzionale)',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(fontSize: 8),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  ),
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                ),
                // Nascondi i campi goal quando è RIPOSA
                if (!_isRest) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _isHome ? _goalsAuroraController : _goalsOpponentController,
                          decoration: InputDecoration(
                            labelText: 'Goal ' + (_isHome
                              ? (_selectedAuroraTeam ?? 'Aurora Seriate')
                              : (_opponentController.text.isNotEmpty ? _opponentController.text : 'Squadra Avversaria')),
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(fontSize: 8),
                            hintText: 'Goal',
                          ),
                          style: const TextStyle(fontSize: 10),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final parsed = int.tryParse(value);
                              if (parsed == null || parsed < 0) {
                                return 'Inserisci un numero valido';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _isHome ? _goalsOpponentController : _goalsAuroraController,
                          decoration: InputDecoration(
                            labelText: 'Goal ' + (_isHome
                              ? (_opponentController.text.isNotEmpty ? _opponentController.text : 'Squadra Avversaria')
                              : (_selectedAuroraTeam ?? 'Aurora Seriate')),
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(fontSize: 8),
                            hintText: 'Goal',
                          ),
                          style: const TextStyle(fontSize: 10),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final parsed = int.tryParse(value);
                              if (parsed == null || parsed < 0) {
                                return 'Inserisci un numero valido';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla', style: TextStyle(fontSize: 12)),
        ),
        // Pulsante elimina solo per partite esistenti
        if (widget.match != null && widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete!();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Elimina', style: TextStyle(fontSize: 12)),
          ),
        ElevatedButton(
          onPressed: _saveMatch,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          child: Text(
            widget.match == null ? 'Aggiungi' : 'Salva',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF1E3A8A),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    TimeOfDay initialTime = const TimeOfDay(hour: 15, minute: 0);

    if (_timeController.text.isNotEmpty) {
      try {
        final parts = _timeController.text.split(':');
        if (parts.length == 2) {
          initialTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
      } catch (e) {
        // Se parsing fallisce, usa l'orario di default
      }
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF1E3A8A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _timeController.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Widget _buildFieldSelector(FieldService fieldService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {}, // Will be handled by PopupMenuButton
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Campo da Gioco',
              prefixIcon: Icon(Icons.location_on, size: 20),
              border: OutlineInputBorder(),
              labelStyle: TextStyle(fontSize: 10),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            child: PopupMenuButton<String>(
            onSelected: (String value) {
              setState(() {
                _selectedFieldId = value;
                if (value == 'manual') {
                  _locationController.clear();
                }
              });
            },
            itemBuilder: (BuildContext context) {
              List<PopupMenuItem<String>> items = [
                PopupMenuItem<String>(
                  value: null,
                  height: 24,
                  padding: EdgeInsets.zero,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: const Text(' ', style: TextStyle(fontSize: 10, height: 1.0)),
                  ),
                ),
              ];

              // Aggiungi i campi dal database
              for (var field in fieldService.fields) {
                items.add(
                  PopupMenuItem<String>(
                    value: field.id,
                    height: 24,
                    padding: EdgeInsets.zero,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      child: Text(
                        '${field.code} - ${field.name}',
                        style: const TextStyle(fontSize: 10, height: 1.0),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                );
              }

              // Opzione manuale
              items.add(
                PopupMenuItem<String>(
                  value: 'manual',
                  height: 24,
                  padding: EdgeInsets.zero,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: const Text('Inserisci manualmente...', style: TextStyle(fontSize: 10, height: 1.0)),
                  ),
                ),
              );

              return items;
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _getFieldDisplayName(_selectedFieldId, fieldService),
                    style: TextStyle(
                      fontSize: 10,
                      color: _selectedFieldId != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }

  String _getFieldDisplayName(String? value, FieldService fieldService) {
    if (value == null || value.isEmpty) {
      return ' '; // Spazio vuoto come default
    }
    if (value == 'manual') {
      return 'Inserisci manualmente...';
    }

    final field = fieldService.fields.firstWhere(
      (f) => f.id == value,
      orElse: () => Field(id: '', name: 'Campo non trovato', address: '', code: ''),
    );
    return '${field.code} - ${field.name}';
  }

  String _getMatchTypeDisplayName(String value) {
    switch (value) {
      case 'campionato':
        return 'CAMPIONATO';
      case 'amichevole':
        return 'AMICHEVOLE';
      case '':
        return 'Seleziona tipo partita';
      default:
        // Tutto il resto viene dalla tabella nomi_tornei
        final tournament = _tournaments.firstWhere(
          (t) => t['value'] == value || t['value']?.toLowerCase() == value.toLowerCase(),
          orElse: () => {'display': value.toUpperCase()},
        );
        return tournament['display'] ?? value.toUpperCase();
    }
  }

  void _saveMatch() {
    if (_formKey.currentState!.validate()) {
      final goalsAurora = _isRest ? null : (_goalsAuroraController.text.trim().isNotEmpty
          ? int.tryParse(_goalsAuroraController.text.trim())
          : null);
      final goalsOpponent = _isRest ? null : (_goalsOpponentController.text.trim().isNotEmpty
          ? int.tryParse(_goalsOpponentController.text.trim())
          : null);
      final giornata = _giornataController.text.trim().isNotEmpty
          ? _giornataController.text.trim().toUpperCase()
          : null;
      
      // Determina il location corretto in base alla selezione
      String locationToSave;
      if (_selectedFieldId != null && _selectedFieldId != 'manual') {
        // Campo selezionato dal dropdown - usa il nome del campo
        final fieldService = context.read<FieldService>();
        final selectedField = fieldService.fields.firstWhere(
          (field) => field.id == _selectedFieldId,
          orElse: () => Field(id: '', name: '', address: '', code: ''),
        );
        locationToSave = selectedField.name.isNotEmpty ? selectedField.name : _locationController.text.trim();
      } else {
        // Inserimento manuale - usa il testo del controller
        locationToSave = _locationController.text.trim();
      }
      
      final match = Match(
        id: widget.match?.id,
        opponent: _opponentController.text.trim(),
        date: _selectedDate,
        time: _isRest ? '' : _timeController.text.trim(), // Orario sempre vuoto se RIPOSA
        location: _isRest ? '' : locationToSave, // Location sempre vuota se RIPOSA
        isHome: _isHome,
        isRest: _isRest,
        matchType: _matchType,
        auroraTeam: _selectedAuroraTeam,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        goalsAurora: goalsAurora,
        goalsOpponent: goalsOpponent,
        giornata: giornata,
        userId: widget.match?.userId, // Preserva l'userId originale per gli update
      );
      
      // TODO: Implementare salvataggio dettagli ultima partita se necessario

      widget.onSave(match);
    }
  }
}