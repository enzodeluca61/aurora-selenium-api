import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';
import 'dart:math' as math;
import '../models/training_model.dart';
import '../models/team_model.dart';
import '../models/match_model.dart';
import '../models/field_model.dart';
import '../services/training_service.dart';
import '../services/team_service.dart';
import '../services/field_service.dart';
import '../services/match_service.dart';
import '../services/auth_service.dart'; // Added this import
import '../widgets/training_form_dialog.dart';

class TrainingsScreen extends StatefulWidget {
  const TrainingsScreen({super.key});

  @override
  State<TrainingsScreen> createState() => _TrainingsScreenState();
}

class _TrainingsScreenState extends State<TrainingsScreen> with TickerProviderStateMixin {
  DateTime _currentWeekStart = DateTime.now();
  final GlobalKey<_ProgressDialogState> _progressKey = GlobalKey<_ProgressDialogState>();
  AnimationController? _animationController;
  Animation<double>? _slideAnimation;
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Ritarda l'inizializzazione per evitare overflow warnings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isInitialized = true;
      });
    });
    
    // Inizializza animazione
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeInOut,
    ));
    
    final today = DateTime.now();
    final minDate = DateTime(2025, 8, 1);

    // Se oggi è prima del 01/08/2025, imposta la settimana al 01/08/2025
    if (today.isBefore(minDate)) {
      _currentWeekStart = _getWeekStart(minDate);
    } else {
      _currentWeekStart = _getWeekStart(today);
    }

    // Se oggi è domenica (weekday = 7), sposta alla settimana successiva
    if (today.weekday == 7) {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trainingService = context.read<TrainingService>();
      final teamService = context.read<TeamService>();
      final fieldService = context.read<FieldService>();
      
      if (trainingService.trainings.isEmpty && !trainingService.isLoading) {
        trainingService.loadTrainings();
      }
      if (teamService.teams.isEmpty && !teamService.isLoading) {
        teamService.loadTeams();
      }
      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields();
        // Inizializza con campi di default se necessario
        fieldService.initializeDefaultFields();
      }
    });
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  DateTime _getWeekStart(DateTime date) {
    final dayOfWeek = date.weekday;
    return DateTime(date.year, date.month, date.day - (dayOfWeek - 1));
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday - 1) / 7).ceil();
  }

  void _changeWeek(bool goNext) async {
    final targetWeek = goNext 
        ? _currentWeekStart.add(const Duration(days: 7))
        : _currentWeekStart.subtract(const Duration(days: 7));
    
    final minDate = DateTime(2025, 8, 1);
    final maxDate = DateTime(2026, 6, 30);
    
    // Controlla limiti di date
    if (goNext && (targetWeek.isAfter(maxDate))) return;
    if (!goNext && (targetWeek.isBefore(minDate))) return;
    
    // Avvia animazione di slide se disponibile
    if (_animationController != null) {
      _animationController!.reset();
      _animationController!.forward();
    }
    
    // Aggiorna la settimana
    setState(() {
      _currentWeekStart = targetWeek;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Allenamenti',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
            onPressed: () => _checkTrainingConflicts(),
            tooltip: 'Controlla Concomitanze',
          ),
          IconButton(
            icon: const Icon(Icons.visibility, color: Colors.white),
            onPressed: () => _showFieldSelectionDialog(),
            tooltip: 'Planning Settimanale',
          ),
        ],
      ),
      body: _isInitialized ? Consumer4<TrainingService, TeamService, FieldService, AuthService>(
        builder: (context, trainingService, teamService, fieldService, authService, child) {
          if (trainingService.isLoading || teamService.isLoading || fieldService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (teamService.teams.isEmpty || fieldService.fields.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nessuna squadra configurata', style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return Material(
            child: SafeArea(
              child: Column(
                children: [
                // Controlli settimana
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => _changeWeek(false), icon: const Icon(Icons.chevron_left)),
                        Expanded(
                          child: InkWell(
                            onTap: () => _showWeekPicker(),
                            child: Column(
                              children: [
                                const Text('Settimana', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                Text('${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yyyy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 4)))}', 
                                     style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1E3A8A)), textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                        IconButton(onPressed: () => _changeWeek(true), icon: const Icon(Icons.chevron_right)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (authService.isSuperAdmin) 
                      Row(
                        children: [
                          Expanded(child: ElevatedButton.icon(onPressed: () => _showCopyWeekDialog(), icon: const Icon(Icons.copy, size: 16), label: const Text('Copia'), 
                                   style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)))),
                          const SizedBox(width: 8),
                          Expanded(child: ElevatedButton.icon(onPressed: () => _showDeleteWeekDialog(), icon: const Icon(Icons.delete, size: 16), label: const Text('Cancella'),
                                   style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)))),
                        ],
                      ),
                  ],
                ),
              ),
              // Header tabella
              SizedBox(
                height: 35,
                child: Container(
                  color: const Color(0xFF1E3A8A).withAlpha(26),
                  child: Row(
                    children: [
                      Container(
                        width: 120, 
                        height: 35,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!, width: 1), color: const Color(0xFF1E3A8A).withAlpha(26)), 
                        alignment: Alignment.center, 
                        child: const Text('Squadra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.clip)
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _horizontalScrollController,
                          child: Row(
                            children: List.generate(5, (index) {
                              final dayDate = _currentWeekStart.add(Duration(days: index));
                              final dayAbbreviation = DateFormat('E', 'it_IT').format(dayDate);
                              final dayNumber = DateFormat('d').format(dayDate);
                              return Container(
                                width: 50, 
                                height: 35, 
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!, width: 1)), 
                                alignment: Alignment.center,
                                child: Text('$dayAbbreviation $dayNumber', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), 
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.clip,
                                  maxLines: 1
                                )
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Lista squadre
              Flexible(
                child: Container(
                  padding: const EdgeInsets.only(bottom: 80), // PADDING FISSO GRANDE
                  child: ListView.builder(
                    itemCount: teamService.teams.length,
                    itemBuilder: (context, index) {
                      final team = teamService.teams[index];
                      return GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity! > 0) _changeWeek(false);
                          else if (details.primaryVelocity! < 0) _changeWeek(true);
                        },
                        child: SizedBox(
                          height: 50,
                          child: ClipRRect(
                            child: Container(
                              height: 50,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              InkWell(
                                onTap: authService.isSuperAdmin ? () => _showTeamCopyDialog(team.category) : null,
                                child: Container(
                                  width: 120, height: 60, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), alignment: Alignment.centerRight,
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!, width: 1), 
                                                           color: authService.isSuperAdmin ? Colors.blue[50]?.withValues(alpha: 0.3) : null),
                                  child: ClipRect(
                                    child: OverflowBox(
                                      maxWidth: 110,
                                      child: _buildTeamCategoryText(team.category),
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  controller: _horizontalScrollController,
                                  child: Row(
                                    children: List.generate(5, (dayIndex) {
                                      final weekday = dayIndex + 1;
                                      final training = _getTraining(trainingService, team.category, weekday);
                                      return GestureDetector(
                                        onTap: authService.isSuperAdmin ? () => _showTrainingDialog(team.category, weekday, training, fieldService) : null,
                                        onLongPress: authService.isSuperAdmin && training != null ? () => _showCopyCellDialog(team.category, weekday, training) : null,
                                        child: Container(
                                          width: 50, height: 75, padding: const EdgeInsets.all(1), alignment: Alignment.center,
                                          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!, width: 1)),
                                          child: ClipRect(
                                            child: training != null
                                                ? Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1E3A8A),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(training.fieldCode, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center, overflow: TextOverflow.clip),
                                                      ),
                                                      Text(_formatTime(training.startTime), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w500), textAlign: TextAlign.center, overflow: TextOverflow.clip),
                                                    ],
                                                  )
                                                : (authService.isSuperAdmin ? Icon(Icons.add_circle_outline, size: 16, color: Colors.grey[400]) : const SizedBox.shrink()),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                              ],
                            ),
                          ),
                        ),
                        ),
                      );
                    },
                  ),
                ),
              ),
                ],
              ),
            ),
          );
        },
      ) : const Center(child: CircularProgressIndicator()),
    );
  }


  Widget _buildTeamCategoryText(String category) {
    // Soluzione semplice e sicura per evitare qualsiasi overflow
    return SizedBox(
      width: 110,
      height: 50,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          category,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  Training? _getTraining(TrainingService trainingService, String teamCategory, int weekday) {
    try {
      return trainingService.getTraining(teamCategory, weekday, _currentWeekStart);
    } catch (e) {
      return null;
    }
  }

  Map<String, String?> _getPreviousDayTrainingDetails(TrainingService trainingService, String teamCategory, int currentWeekday) {
    String? suggestedStartTime;
    String? suggestedFieldCode;

    // Calculate previous day's weekday and weekStart
    // currentWeekday is 1-indexed (Monday=1, Sunday=7)
    // We want the day before, so subtract 1 from currentWeekday to get the previous day's index
    // If currentWeekday is 1 (Monday), previousDayIndex will be 0, which means Sunday of the previous week.
    // We need to adjust the date accordingly.
    
    DateTime previousDayDate = _currentWeekStart.add(Duration(days: currentWeekday - 2)); // -2 because weekday is 1-indexed and we want the day before

    // Get the training for the previous day
    final previousDayTraining = _getTraining(trainingService, teamCategory, previousDayDate.weekday);

    if (previousDayTraining != null) {
      suggestedStartTime = previousDayTraining.startTime;
      suggestedFieldCode = previousDayTraining.fieldCode;
    }

    return {
      'startTime': suggestedStartTime,
      'fieldCode': suggestedFieldCode,
    };
  }

  String? _getSuggestedFieldCode(String teamCategory, int weekday, FieldService fieldService) {
    // Cerca se questa squadra ha già un allenamento in altri giorni
    for (int day = 1; day <= 5; day++) {
      if (day != weekday) {
        final existingTraining = _getTraining(context.read<TrainingService>(), teamCategory, day);
        if (existingTraining != null) {
          return existingTraining.fieldCode;
        }
      }
    }
    
    // Se non trova niente, prende il primo campo disponibile
    if (fieldService.fields.isNotEmpty) {
      return fieldService.fields.first.code;
    }
    
    return null;
  }

  void _showTrainingDialog(String teamCategory, int weekday, Training? training, FieldService fieldService) {
    showDialog(
      context: context,
      builder: (context) => TrainingFormDialog(
        teamCategory: teamCategory,
        weekday: weekday,
        weekStart: _currentWeekStart,
        training: training,
        suggestedFieldCode: training == null ? _getSuggestedFieldCode(teamCategory, weekday, fieldService) : null,
        onSave: (training) async {
          final trainingService = context.read<TrainingService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = training.id == null
              ? await trainingService.addTraining(training)
              : await trainingService.updateTraining(training);
          
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Allenamento salvato con successo!')), 
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(trainingService.errorMessage ?? 'Errore nel salvataggio'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onDelete: training != null ? () async {
          final trainingService = context.read<TrainingService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await trainingService.deleteTraining(training.id!);
          
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Allenamento eliminato con successo!')), 
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(trainingService.errorMessage ?? 'Errore nell\'eliminazione'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } : null,
      ),
    );
  }

  void _showTeamCopyDialog(String teamCategory) {
    DateTime? targetStartDate;
    DateTime? targetEndDate;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Copia Squadra $teamCategory',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sorgente:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E3A8A), width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.source, color: Color(0xFF1E3A8A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$teamCategory - ${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} / ${DateFormat('dd/MM/yy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 4)))}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              const Text(
                'Copia DALLA settimana:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _currentWeekStart.add(const Duration(days: 7)),
                    firstDate: DateTime(2025, 8, 1),
                    lastDate: DateTime(2026, 6, 30),
                    locale: const Locale('it', 'IT'),
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
                      targetStartDate = _getWeekStart(picked);
                      if (targetEndDate != null && targetEndDate!.isBefore(targetStartDate!)) {
                        targetEndDate = null;
                      }
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    targetStartDate != null
                        ? '${DateFormat('dd/MM', 'it_IT').format(targetStartDate!)} - ${DateFormat('dd/MM/yy', 'it_IT').format(targetStartDate!.add(const Duration(days: 4)))}'
                        : 'Seleziona prima settimana destinazione',
                    style: TextStyle(
                      fontSize: 14,
                      color: targetStartDate != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              const Text(
                'ALLA settimana:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: (targetStartDate ?? _currentWeekStart).add(const Duration(days: 7)),
                    firstDate: targetStartDate ?? DateTime(2025, 8, 1),
                    lastDate: DateTime(2026, 6, 30),
                    locale: const Locale('it', 'IT'),
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
                      targetEndDate = _getWeekStart(picked);
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    targetEndDate != null
                        ? '${DateFormat('dd/MM', 'it_IT').format(targetEndDate!)} - ${DateFormat('dd/MM/yy', 'it_IT').format(targetEndDate!.add(const Duration(days: 4)))}'
                        : 'Seleziona ultima settimana destinazione',
                    style: TextStyle(
                      fontSize: 14,
                      color: targetEndDate != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),

              if (targetStartDate != null && targetEndDate != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'La squadra $teamCategory verrà copiata in ${((targetEndDate!.difference(targetStartDate!).inDays) ~/ 7) + 1} settimane',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: (targetStartDate != null && targetEndDate != null) ? () async {
                final trainingService = context.read<TrainingService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                
                navigator.pop();

                final totalWeeks = ((targetEndDate!.difference(targetStartDate!).inDays) ~/ 7) + 1;
                
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => _ProgressDialog(
                    key: _progressKey,
                    title: 'Copia squadra...',
                    totalSteps: totalWeeks * 5, // 5 giorni per settimana
                  ),
                );

                DateTime currentTarget = targetStartDate!;
                bool allSuccess = true;
                int currentStep = 0;
                
                while (currentTarget.isBefore(targetEndDate!.add(const Duration(days: 1)))) {
                  // Copia ogni giorno della settimana per questa squadra
                  for (int weekday = 1; weekday <= 5; weekday++) {
                    currentStep++;
                    _progressKey.currentState?.updateProgress(currentStep);
                    
                    final sourceTraining = _getTraining(trainingService, teamCategory, weekday);
                    if (sourceTraining != null) {
                      // Elimina allenamento esistente per questa squadra e giorno
                      final existingTraining = trainingService.getTraining(teamCategory, weekday, currentTarget);
                      if (existingTraining != null) {
                        await trainingService.deleteTraining(existingTraining.id!);
                      }
                      
                      // Copia l'allenamento
                      final newTraining = sourceTraining.copyWith(
                        clearId: true,
                        weekStart: currentTarget,
                      );
                      
                      final success = await trainingService.addTraining(newTraining);
                      if (!success) {
                        allSuccess = false;
                        break;
                      }
                    }
                    
                    await Future.delayed(const Duration(milliseconds: 50));
                  }
                  
                  if (!allSuccess) break;
                  currentTarget = currentTarget.add(const Duration(days: 7));
                }
                
                await Future.delayed(const Duration(milliseconds: 1000));
                
                if (context.mounted) {
                  if (allSuccess) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Squadra $teamCategory copiata con successo!')), 
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(trainingService.errorMessage ?? 'Errore nella copia'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Copia'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopyWeekDialog() {
    DateTime? targetStartDate;
    DateTime? targetEndDate;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Copia Settimana',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sorgente:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E3A8A), width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.source, color: Color(0xFF1E3A8A)),
                    const SizedBox(width: 8),
                    Text(
                      '${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 4)))}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              const Text(
                'Copia DALLA settimana:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _currentWeekStart.add(const Duration(days: 7)),
                    firstDate: DateTime(2025, 8, 1),
                    lastDate: DateTime(2026, 6, 30),
                    locale: const Locale('it', 'IT'),
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
                      targetStartDate = _getWeekStart(picked);
                      // Reset end date se è prima della start
                      if (targetEndDate != null && targetEndDate!.isBefore(targetStartDate!)) {
                        targetEndDate = null;
                      }
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    targetStartDate != null
                        ? '${DateFormat('dd/MM', 'it_IT').format(targetStartDate!)} - ${DateFormat('dd/MM/yy', 'it_IT').format(targetStartDate!.add(const Duration(days: 4)))}'
                        : 'Seleziona prima settimana destinazione',
                    style: TextStyle(
                      fontSize: 14,
                      color: targetStartDate != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                'ALLA settimana:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: (targetStartDate ?? _currentWeekStart).add(const Duration(days: 7)),
                    firstDate: targetStartDate ?? DateTime(2025, 8, 1),
                    lastDate: DateTime(2026, 6, 30),
                    locale: const Locale('it', 'IT'),
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
                      targetEndDate = _getWeekStart(picked);
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    targetEndDate != null
                        ? '${DateFormat('dd/MM', 'it_IT').format(targetEndDate!)} - ${DateFormat('dd/MM/yy', 'it_IT').format(targetEndDate!.add(const Duration(days: 4)))}'
                        : 'Seleziona ultima settimana destinazione',
                    style: TextStyle(
                      fontSize: 14,
                      color: targetEndDate != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),

              if (targetStartDate != null && targetEndDate != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'La settimana corrente verrà copiata in ${((targetEndDate!.difference(targetStartDate!).inDays) ~/ 7) + 1} settimane',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: (targetStartDate != null && targetEndDate != null) ? () async {
                final trainingService = context.read<TrainingService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                
                // Chiudi immediatamente il dialog della copia
                navigator.pop();

                // Calcola il numero totale di settimane da copiare
                final totalWeeks = ((targetEndDate!.difference(targetStartDate!).inDays) ~/ 7) + 1;
                
                // Chiudi il dialog corrente e mostra quello di progresso
                navigator.pop();
                
                // Controlla se il context è ancora valido prima di mostrare il dialog
                if (!context.mounted) return;
                
                // Mostra il dialog di progresso
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => _ProgressDialog(
                    key: _progressKey,
                    title: 'Copia in corso...',
                    totalSteps: totalWeeks,
                  ),
                );

                // Copia la settimana corrente in tutte le settimane del range destinazione
                DateTime currentTarget = targetStartDate!;
                bool allSuccess = true;
                int currentStep = 0;
                
                while (currentTarget.isBefore(targetEndDate!.add(const Duration(days: 1)))) {
                  currentStep++;
                  
                  // Aggiorna il progresso
                  _progressKey.currentState?.updateProgress(currentStep);
                  
                  // Prima cancella gli allenamenti esistenti nella settimana target
                  final deleteSuccess = await trainingService.deleteWeekTrainings(currentTarget);
                  if (!deleteSuccess) {
                    allSuccess = false;
                    break;
                  }
                  
                  // Poi copia gli allenamenti della settimana corrente
                  final copySuccess = await trainingService.copyWeekTrainings(_currentWeekStart, currentTarget);
                  if (!copySuccess) {
                    allSuccess = false;
                    break;
                  }
                  
                  currentTarget = currentTarget.add(const Duration(days: 7));
                  
                  // Piccola pausa per far vedere il progresso
                  await Future.delayed(const Duration(milliseconds: 200));
                }
                
                // Il dialog si chiuderà automaticamente
                // Attendi che si chiuda prima di mostrare i messaggi
                await Future.delayed(const Duration(milliseconds: 1000));
                
                if (context.mounted) {
                  if (allSuccess) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Settimana copiata con successo!')), 
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(trainingService.errorMessage ?? 'Errore nella copia'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Copia'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopyCellDialog(String sourceTeamCategory, int sourceWeekday, Training sourceTraining) {
    List<int> selectedDays = [];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Copia Allenamento nella Stessa Squadra',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.height * 0.5,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A8A), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ORIGINE:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                        Text('$sourceTeamCategory - ${_getDayName(sourceWeekday)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text('${sourceTraining.startTime} - ${sourceTraining.endTime}', style: const TextStyle(fontSize: 12)),
                        Text(_getFieldName(sourceTraining.fieldCode), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF1E3A8A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'L\'allenamento verrà copiato per la squadra $sourceTeamCategory',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A8A), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Seleziona giorni destinazione:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 3, 4, 5].where((day) => day != sourceWeekday).map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(_getDayName(day), style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                          });
                        },
                        backgroundColor: Colors.grey[200],
                        selectedColor: Colors.green.withValues(alpha: 0.2),
                        checkmarkColor: Colors.green,
                      );
                    }).toList(),
                  ),
                  if (selectedDays.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'L\'allenamento verrà copiato in ${selectedDays.length} giorni per la squadra $sourceTeamCategory',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: selectedDays.isNotEmpty ? () async {
                final trainingService = context.read<TrainingService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                
                navigator.pop();
                
                bool allSuccess = true;
                int copiedCount = 0;
                
                for (final weekday in selectedDays) {
                  // Elimina allenamento esistente se presente
                  final existingTraining = _getTraining(trainingService, sourceTeamCategory, weekday);
                  if (existingTraining != null) {
                    await trainingService.deleteTraining(existingTraining.id!);
                  }
                  
                  // Crea nuovo allenamento per la stessa squadra
                  final newTraining = sourceTraining.copyWith(
                    clearId: true,
                    teamCategory: sourceTeamCategory,
                    weekday: weekday,
                    weekStart: _currentWeekStart,
                  );
                  
                  final success = await trainingService.addTraining(newTraining);
                  if (success) {
                    copiedCount++;
                  } else {
                    allSuccess = false;
                  }
                }
                
                if (allSuccess) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Allenamento copiato con successo in $copiedCount giorni!')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Copiato con successo in $copiedCount giorni, alcuni errori riscontrati'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Copia'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteWeekDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Cancella Settimana',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Attenzione!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              'Vuoi cancellare tutti gli allenamenti della settimana:\n${DateFormat('dd/MM', 'it_IT').format(_currentWeekStart)} - ${DateFormat('dd/MM/yy', 'it_IT').format(_currentWeekStart.add(const Duration(days: 4)))}?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Questa azione non può essere annullata.',
              style: TextStyle(fontSize: 12, color: Colors.red, fontStyle: FontStyle.italic),
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
              final trainingService = context.read<TrainingService>();
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              final success = await trainingService.deleteWeekTrainings(_currentWeekStart);
              
              navigator.pop();
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Settimana cancellata con successo!')), 
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(trainingService.errorMessage ?? 'Errore nella cancellazione'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancella Tutto'),
          ),
        ],
      ),
    );
  }

  void _showWeekPicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentWeekStart,
      firstDate: DateTime(2025, 8, 1), // 01/08/2025
      lastDate: DateTime(2026, 6, 30),  // 30/06/2026
      locale: const Locale('it', 'IT'),
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
      helpText: 'Seleziona una data della settimana',
      cancelText: 'Annulla',
      confirmText: 'Seleziona',
    );
    
    if (picked != null) {
      setState(() {
        _currentWeekStart = _getWeekStart(picked);
      });
      
      // Ricarica gli allenamenti per la nuova settimana
      final trainingService = context.read<TrainingService>();
      trainingService.loadTrainings(weekStart: _currentWeekStart);
    }
  }


  // Dialog per selezione campi per PDF
  void _showFieldSelectionDialog() {
    final fieldService = context.read<FieldService>();
    List<String> selectedFields = [...fieldService.fields.map((f) => f.id!).toList()]; // Inizia con tutti selezionati
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Seleziona Campi per PDF',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          selectedFields = [...fieldService.fields.map((f) => f.id!).toList()];
                        });
                      },
                      child: const Text('Seleziona', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          selectedFields.clear();
                        });
                      },
                      child: const Text('Deseleziona', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: fieldService.fields.length,
                    itemBuilder: (context, index) {
                      final field = fieldService.fields[index];
                      final isSelected = selectedFields.contains(field.id);
                      
                      return CheckboxListTile(
                        title: Text(
                          '${field.code} - ${field.name}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value ?? false) {
                              selectedFields.add(field.id!);
                            } else {
                              selectedFields.remove(field.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla', style: TextStyle(fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: selectedFields.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _previewWeeklyTrainingPDF(selectedFields);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Genera PDF', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // Funzioni per generare PDF degli allenamenti
  Future<void> _previewWeeklyTrainingPDF([List<String>? selectedFieldIds]) async {
    final trainingService = context.read<TrainingService>();
    final teamService = context.read<TeamService>();
    final fieldService = context.read<FieldService>();
    final matchService = context.read<MatchService>();
    
    // Converte gli ID dei campi selezionati in codici e nomi campo
    List<String>? selectedFieldCodes;
    List<String>? selectedFieldNames;
    if (selectedFieldIds != null && selectedFieldIds.isNotEmpty) {
      final selectedFields = fieldService.fields
          .where((field) => selectedFieldIds.contains(field.id))
          .toList();
      selectedFieldCodes = selectedFields.map((field) => field.code).toList();
      selectedFieldNames = selectedFields.map((field) => field.name).toList();
    }
    
    debugPrint('=== PDF GENERATION ===');
    debugPrint('Selected field IDs: $selectedFieldIds');
    debugPrint('Selected field codes: $selectedFieldCodes');
    debugPrint('Selected field names: $selectedFieldNames');
    debugPrint('All available fields: ${fieldService.fields.map((f) => '${f.code}:${f.name}').toList()}');
    
    // Helper per verificare se una partita è nei campi selezionati
    bool isMatchInSelectedFields(Match match) {
      if (selectedFieldCodes == null || selectedFieldCodes.isEmpty) {
        return true; // Se nessun filtro, mostra tutte le partite
      }
      
      // Se è una partita fuori casa (trasferta), mostra sempre
      if (!match.isHome) {
        debugPrint('Away match - always show: "${match.location}"');
        return true;
      }
      
      // Solo per partite in casa, applica il filtro per campo
      final location = match.location.toLowerCase().trim();
      
      debugPrint('Home match location: "${match.location}"');
      debugPrint('Selected field codes: $selectedFieldCodes');
      debugPrint('Selected field names: $selectedFieldNames');
      
      // Controlla se la location corrisponde esattamente a uno dei nomi dei campi selezionati
      if (selectedFieldNames != null) {
        for (String fieldName in selectedFieldNames) {
          final fieldNameLower = fieldName.toLowerCase().trim();
          
          // Confronto esatto
          if (location == fieldNameLower) {
            debugPrint('Exact match with field name: $fieldName');
            return true;
          }
          
          // Confronto con formato "address - FIELD_NAME"
          if (location.contains(' - ')) {
            final parts = location.split(' - ');
            if (parts.length > 1 && parts.last.trim() == fieldNameLower) {
              debugPrint('Match with format "address - FIELD_NAME": $fieldName');
              return true;
            }
          }
        }
      }
      
      // Controlla se la location contiene uno dei codici dei campi selezionati
      if (selectedFieldCodes != null) {
        for (String fieldCode in selectedFieldCodes) {
          final fieldCodeLower = fieldCode.toLowerCase().trim();
          
          // Confronto se la location contiene il codice del campo
          if (location.contains(fieldCodeLower)) {
            debugPrint('Match with field code: $fieldCode');
            return true;
          }
        }
      }
      
      debugPrint('Home match not in selected fields - filtering out');
      return false;
    }
    
    // Filtra i campi selezionati
    List<Field> fieldsToGenerate;
    if (selectedFieldIds == null || selectedFieldIds.isEmpty) {
      fieldsToGenerate = fieldService.fields;
    } else {
      fieldsToGenerate = fieldService.fields
          .where((field) => selectedFieldIds.contains(field.id))
          .toList();
    }
    
    // Load logo
    final logoData = await rootBundle.load('assets/images/aurora_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    
    // Load goalkeeper icon
    pw.MemoryImage? goalkeeperIcon;
    try {
      final goalkeeperData = await rootBundle.load('assets/images/portiere.png');
      goalkeeperIcon = pw.MemoryImage(goalkeeperData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Goalkeeper icon not found: $e');
    }
    
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );
    
    // Prima pagina - Prime 9 squadre
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(842, 595), // FORZA ORIZZONTALE width > height
        margin: const pw.EdgeInsets.all(20), // margini ridotti
        build: (pw.Context context) {
          return pw.Column(
            children: [
              // Header con loghi e titolo
              pw.Container(
                height: 35,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Container(
                      width: 35,
                      height: 35,
                      child: pw.Image(logo),
                    ),
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'PLANNING SETTIMANALE - AGONISTICA',
                              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              'ALLENAMENTI E PARTITE',
                              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.Container(
                      width: 35,
                      height: 35,
                      child: pw.Image(logo),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              // Tabella allenamenti
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 3),
                ),
                child: pw.Column(
                  children: [
                    // Header giorni
                    pw.Container(
                      height: 38,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.lightBlue,
                        border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 3))
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 100, // Stessa larghezza delle righe squadre per allineamento
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                                border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 2), bottom: pw.BorderSide(color: PdfColors.black, width: 2))
                            ),
                            child: pw.Center(child: pw.Text('SQUADRA', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)))
                          ),
                          ...List.generate(5, (index) {
                            final dayDate = _currentWeekStart.add(Duration(days: index));
                            final dayAbbr = DateFormat('EEEE', 'it_IT').format(dayDate).toUpperCase();
                            final dayDateFormatted = DateFormat('dd/MM').format(dayDate);
                            return pw.Expanded(child: pw.Container(
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                border: pw.Border(
                                  right: pw.BorderSide(color: PdfColors.black, width: 3),
                                  bottom: pw.BorderSide(color: PdfColors.black, width: 3),
                                  left: index == 0 ? pw.BorderSide(color: PdfColors.black, width: 3) : pw.BorderSide.none,
                                  top: pw.BorderSide(color: PdfColors.black, width: 3)
                                )
                              ),
                              child: pw.Center(child: pw.Text('$dayAbbr\n$dayDateFormatted', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center))
                            ));
                          }),
                        ],
                      ),
                    ),
                    ...teamService.teams.take(9).map((team) => pw.Container( // Prime 9 squadre
                      height: 48, // Altezza aumentata per visualizzare squadre
                      decoration: pw.BoxDecoration(
                                border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 3), bottom: pw.BorderSide(color: PdfColors.black, width: 1))
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 100, // Larghezza fissa ridotta (era flex: 2, circa 120mm)
                            decoration: pw.BoxDecoration(
                                border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 3), bottom: pw.BorderSide(color: PdfColors.black, width: 1))
                            ),
                            child: pw.Center(
                                child: pw.Padding(
                                    padding: const pw.EdgeInsets.all(2),
                                    child: pw.Text(team.category,
                                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                                        textAlign: pw.TextAlign.center)))),
                          ...List.generate(5, (dayIndex) {
                            final weekday = dayIndex + 1;
                            final dayDate = _currentWeekStart.add(Duration(days: dayIndex));
                            final training = _getTraining(trainingService, team.category, weekday);

                            // Cerca partite solo per i giorni feriali (lunedì-venerdì)
                            final matches = matchService.getMatchesForDate(dayDate).where((match) =>
                              match.auroraTeam == team.category &&
                              match.auroraTeam?.toUpperCase() != 'ALTRO' &&
                              match.includeInPlanning &&
                              isMatchInSelectedFields(match)).toList();
                            
                            return pw.Expanded(child: pw.Container(
                              decoration: pw.BoxDecoration(
                                color: matches.isNotEmpty 
                                  ? PdfColor.fromHex('#E8F4F8FF')  // Celestino molto più chiaro per tutte le partite
                                  : null,
                                border: pw.Border(
                                  top: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                  right: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                  bottom: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                  left: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1)
                                )
                              ),
                              child: matches.isNotEmpty
                                  ? pw.Column(
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: [
                                        // Controlla concomitanze
                                        if (matches.length > 1 && _hasConflicts(matches)) ...[
                                          pw.Text(
                                            '⚠️ CONCOMITANZA',
                                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red),
                                            textAlign: pw.TextAlign.center,
                                          ),
                                          pw.SizedBox(height: 2),
                                        ],
                                        for (final match in matches) ...[
                                          // Formato con distinzione casa/fuori casa (ALTRO escluso dal filtro)
                                            // Prima riga: orario - tipo partita
                                            pw.Text(
                                              '${_formatTime(match.time)} - ${_formatMatchType(match)}',
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                            // Seconda riga: Squadra di casa
                                            pw.Text(
                                              match.isHome ? 'AURORA SERIATE' : match.opponent,
                                              style: pw.TextStyle(
                                                fontSize: (match.isHome ? 9 : (match.opponent.toUpperCase().contains('AURORA') ? 9 : 8)),
                                                fontWeight: pw.FontWeight.bold,
                                                color: PdfColors.black
                                              ),
                                              textAlign: pw.TextAlign.center,
                                              maxLines: 1,
                                              overflow: pw.TextOverflow.clip,
                                            ),
                                            // Terza riga: Squadra ospite
                                            pw.Text(
                                              match.isHome ? match.opponent : 'AURORA SERIATE',
                                              style: pw.TextStyle(
                                                fontSize: (match.isHome ? (match.opponent.toUpperCase().contains('AURORA') ? 9 : 8) : 9),
                                                fontWeight: pw.FontWeight.bold,
                                                color: PdfColors.black
                                              ),
                                              textAlign: pw.TextAlign.center,
                                              maxLines: 1,
                                              overflow: pw.TextOverflow.clip,
                                            ),
                                            // Quarta riga: Indirizzo
                                            pw.Text(
                                              _formatAddress(match.location),
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                                              textAlign: pw.TextAlign.center,
                                              maxLines: 1,
                                              overflow: pw.TextOverflow.clip,
                                            ),
                                          if (matches.indexOf(match) < matches.length - 1)
                                            pw.SizedBox(height: 2),
                                        ]
                                      ],
                                    )
                                  : training != null && (selectedFieldCodes == null || selectedFieldCodes.isEmpty || selectedFieldCodes.contains(training.fieldCode))
                                      ? pw.Column(
                                          mainAxisAlignment: pw.MainAxisAlignment.center,
                                          children: [
                                            pw.Row(
                                              mainAxisAlignment: pw.MainAxisAlignment.center,
                                              children: [
                                                pw.Text(
                                                  'ALLENAMENTO',
                                                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                                                  textAlign: pw.TextAlign.center,
                                                ),
                                                // Icona portiere - solo se hasGoalkeeper è true
                                                if (training.hasGoalkeeper) ...[
                                                  pw.SizedBox(width: 4),
                                                  if (goalkeeperIcon != null)
                                                    pw.Container(
                                                      width: 10,
                                                      height: 10,
                                                      child: pw.Image(goalkeeperIcon),
                                                    ),
                                                ],
                                              ],
                                            ),
                                            pw.Text(
                                              '${_formatTime(training.startTime)} - ${_formatTime(training.endTime)}',
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                            pw.SizedBox(height: 2),
                                            pw.Text(
                                              _formatAddress(_getFieldName(training.fieldCode)),
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                          ],
                                        )
                                      : pw.Center(child: pw.Text('----', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600))),
                            ));
                          }),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              // Legenda
              pw.SizedBox(height: 16),
              pw.Row(
                children: [
                  pw.Text(
                    'Legenda: ',
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                  ),
                  if (goalkeeperIcon != null) ...[
                    pw.Container(
                      width: 12,
                      height: 12,
                      child: pw.Image(goalkeeperIcon),
                    ),
                    pw.SizedBox(width: 4),
                  ],
                  pw.Text(
                    'allenamenti con preparatori dei portieri',
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Seconda pagina - Squadre rimanenti (dalla 10ª in poi)
    if (teamService.teams.length > 9) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(842, 595), // FORZA ORIZZONTALE width > height
          margin: const pw.EdgeInsets.all(20), // margini ridotti
          build: (pw.Context context) {
            return pw.Column(
              children: [
                // Header con loghi e titolo (uguale alla prima pagina)
                pw.Container(
                  height: 35,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Container(
                        width: 35,
                        height: 35,
                        child: pw.Image(logo),
                      ),
                      pw.Expanded(
                        child: pw.Center(
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'PLANNING SETTIMANALE - ATTIVITA\' DI BASE',
                                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                'ALLENAMENTI E PARTITE',
                                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Container(
                        width: 35,
                        height: 35,
                        child: pw.Image(logo),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                // Tabella allenamenti
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 3),
                  ),
                  child: pw.Column(
                    children: [
                      // Header giorni (uguale alla prima pagina)
                      pw.Container(
                        height: 38,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.lightBlue,
                          border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 3))
                        ),
                        child: pw.Row(
                          children: [
                            pw.Container(
                              width: 100, // Stessa larghezza delle righe squadre per allineamento
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 2), bottom: pw.BorderSide(color: PdfColors.black, width: 2))
                              ),
                              child: pw.Center(child: pw.Text('SQUADRA', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)))
                            ),
                            ...List.generate(5, (index) {
                              final dayDate = _currentWeekStart.add(Duration(days: index));
                              final dayAbbr = DateFormat('EEEE', 'it_IT').format(dayDate).toUpperCase();
                              final dayDateFormatted = DateFormat('dd/MM').format(dayDate);
                              return pw.Expanded(child: pw.Container(
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  border: pw.Border(
                                    right: pw.BorderSide(color: PdfColors.black, width: 3),
                                    bottom: pw.BorderSide(color: PdfColors.black, width: 3),
                                    left: index == 0 ? pw.BorderSide(color: PdfColors.black, width: 3) : pw.BorderSide.none,
                                    top: pw.BorderSide(color: PdfColors.black, width: 3)
                                  )
                                ),
                                child: pw.Center(child: pw.Text('$dayAbbr\n$dayDateFormatted', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center))
                              ));
                            }),
                          ],
                        ),
                      ),
                      ...teamService.teams.skip(9).map((team) => pw.Container( // Squadre dalla 10ª in poi
                        height: 48, // Altezza aumentata per visualizzare squadre
                        decoration: pw.BoxDecoration(
                                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 3), bottom: pw.BorderSide(color: PdfColors.black, width: 1))
                        ),
                        child: pw.Row(
                          children: [
                            pw.Container(
                              width: 100, // Larghezza fissa ridotta (era flex: 2, circa 120mm)
                              decoration: pw.BoxDecoration(
                                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 3), bottom: pw.BorderSide(color: PdfColors.black, width: 1))
                              ),
                              child: pw.Center(
                                  child: pw.Padding(
                                      padding: const pw.EdgeInsets.all(2),
                                      child: pw.Text(team.category,
                                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                                          textAlign: pw.TextAlign.center)))),
                            ...List.generate(5, (dayIndex) {
                              final weekday = dayIndex + 1;
                              final dayDate = _currentWeekStart.add(Duration(days: dayIndex));
                              final training = _getTraining(trainingService, team.category, weekday);

                              // Cerca partite solo per i giorni feriali (lunedì-venerdì)
                              final matches = matchService.getMatchesForDate(dayDate).where((match) =>
                                match.auroraTeam == team.category &&
                                match.auroraTeam?.toUpperCase() != 'ALTRO' &&
                                match.includeInPlanning &&
                                isMatchInSelectedFields(match)).toList();
                              
                              return pw.Expanded(child: pw.Container(
                                decoration: pw.BoxDecoration(
                                  color: matches.isNotEmpty 
                                    ? PdfColor.fromHex('#E8F4F8FF')  // Celestino molto più chiaro per tutte le partite
                                    : null,
                                  border: pw.Border(
                                    top: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                    right: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                    bottom: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1),
                                    left: pw.BorderSide(color: PdfColors.black, width: matches.isNotEmpty ? 2 : 1)
                                  )
                                ),
                                child: matches.isNotEmpty
                                    ? pw.Column(
                                        mainAxisAlignment: pw.MainAxisAlignment.center,
                                        children: [
                                          // Controlla concomitanze
                                          if (matches.length > 1 && _hasConflicts(matches)) ...[
                                            pw.Text(
                                              '⚠️ CONCOMITANZA',
                                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red),
                                              textAlign: pw.TextAlign.center,
                                            ),
                                            pw.SizedBox(height: 2),
                                          ],
                                          for (final match in matches) ...[
                                            // Formato con distinzione casa/fuori casa (ALTRO escluso dal filtro)
                                              // Prima riga: orario - tipo partita
                                              pw.Text(
                                                '${_formatTime(match.time)} - ${_formatMatchType(match)}',
                                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                                                textAlign: pw.TextAlign.center,
                                              ),
                                              // Seconda riga: Squadra di casa
                                              pw.Text(
                                                match.isHome ? 'AURORA SERIATE' : match.opponent,
                                                style: pw.TextStyle(
                                                  fontSize: (match.isHome ? 9 : (match.opponent.toUpperCase().contains('AURORA') ? 9 : 8)),
                                                  fontWeight: pw.FontWeight.bold,
                                                  color: PdfColors.black
                                                ),
                                                textAlign: pw.TextAlign.center,
                                                maxLines: 1,
                                                overflow: pw.TextOverflow.clip,
                                              ),
                                              // Terza riga: Squadra ospite
                                              pw.Text(
                                                match.isHome ? match.opponent : 'AURORA SERIATE',
                                                style: pw.TextStyle(
                                                  fontSize: (match.isHome ? (match.opponent.toUpperCase().contains('AURORA') ? 9 : 8) : 9),
                                                  fontWeight: pw.FontWeight.bold,
                                                  color: PdfColors.black
                                                ),
                                                textAlign: pw.TextAlign.center,
                                                maxLines: 1,
                                                overflow: pw.TextOverflow.clip,
                                              ),
                                              // Quarta riga: Indirizzo
                                              pw.Text(
                                                _formatAddress(match.location),
                                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                                                textAlign: pw.TextAlign.center,
                                                maxLines: 1,
                                                overflow: pw.TextOverflow.clip,
                                              ),
                                            if (matches.indexOf(match) < matches.length - 1)
                                              pw.SizedBox(height: 2),
                                          ]
                                        ],
                                      )
                                    : training != null && (selectedFieldCodes == null || selectedFieldCodes.isEmpty || selectedFieldCodes.contains(training.fieldCode))
                                        ? pw.Column(
                                            mainAxisAlignment: pw.MainAxisAlignment.center,
                                            children: [
                                              pw.Row(
                                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                                children: [
                                                  pw.Text(
                                                    'ALLENAMENTO',
                                                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                                                    textAlign: pw.TextAlign.center,
                                                  ),
                                                  // Icona portiere - solo se hasGoalkeeper è true
                                                  if (training.hasGoalkeeper) ...[
                                                    pw.SizedBox(width: 4),
                                                    if (goalkeeperIcon != null)
                                                      pw.Container(
                                                        width: 10,
                                                        height: 10,
                                                        child: pw.Image(goalkeeperIcon),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                              pw.Text(
                                                '${_formatTime(training.startTime)} - ${_formatTime(training.endTime)}',
                                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                                                textAlign: pw.TextAlign.center,
                                              ),
                                              pw.SizedBox(height: 2),
                                              pw.Text(
                                                _formatAddress(_getFieldName(training.fieldCode)),
                                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                                                textAlign: pw.TextAlign.center,
                                              ),
                                            ],
                                          )
                                        : pw.Center(child: pw.Text('----', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600))),
                              ));
                            }),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
                // Legenda (uguale alla prima pagina)
                pw.SizedBox(height: 16),
                pw.Row(
                  children: [
                    pw.Text(
                      'Legenda: ',
                      style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                    ),
                    if (goalkeeperIcon != null) ...[
                      pw.Container(
                        width: 12,
                        height: 12,
                        child: pw.Image(goalkeeperIcon),
                      ),
                      pw.SizedBox(width: 4),
                    ],
                    pw.Text(
                      'allenamenti con preparatori dei portieri',
                      style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    // Anteprima PDF usando PdfPreview
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'Planning Settimanale',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: const Color(0xFF1E3A8A),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () async {
                  // Share the PDF
                  final output = await getTemporaryDirectory();
                  final startDate = DateFormat('dd/MM', 'it_IT').format(_currentWeekStart);
                  final endDate = DateFormat('dd/MM', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)));
                  final file = File('${output.path}/planning_settimanale_${startDate.replaceAll('/', '-')}_${endDate.replaceAll('/', '-')}.pdf');
                  await file.writeAsBytes(await pdf.save());
                  await Share.shareXFiles([XFile(file.path)], text: 'Planning Settimanale!');
                },
              ),
            ],
          ),
          body: PdfPreview(
            build: (format) async => await pdf.save(),
          ),
        ),
      ),
    );
  }

  Future<void> _generateWeeklyTrainingPDF() async {
    debugPrint('=== GENERATING WEEKLY TRAINING PDF ===');
    final trainingService = context.read<TrainingService>();
    final teamService = context.read<TeamService>();
    final fieldService = context.read<FieldService>();
    final matchService = context.read<MatchService>();
    
    debugPrint('Services loaded, starting PDF creation...');
    
    // Load logo
    final logoData = await rootBundle.load('assets/images/aurora_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    
    // Load goalkeeper icon
    pw.MemoryImage? goalkeeperIcon;
    try {
      final goalkeeperData = await rootBundle.load('assets/images/portiere.png');
      goalkeeperIcon = pw.MemoryImage(goalkeeperData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Goalkeeper icon not found: $e');
    }
    
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      ),
    );
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(842, 595),
        margin: const pw.EdgeInsets.all(28.35),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              // This would contain the PDF content similar to _previewWeeklyTrainingPDF
              // For now, adding a simple placeholder
              pw.Text('Training Schedule', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    try {
      debugPrint('Loading PDF fonts and creating document...');
      final output = await getTemporaryDirectory();
      final startDate = DateFormat('dd/MM', 'it_IT').format(_currentWeekStart);
      final endDate = DateFormat('dd/MM', 'it_IT').format(_currentWeekStart.add(const Duration(days: 6)));
      final file = File('${output.path}/planning_settimanale_${startDate.replaceAll('/', '-')}_${endDate.replaceAll('/', '-')}.pdf');
      debugPrint('Saving PDF to: ${file.path}');
      await file.writeAsBytes(await pdf.save());
      debugPrint('PDF saved successfully, sharing...');
      await Share.shareXFiles([XFile(file.path)], text: 'Planning Settimanale!');
      debugPrint('PDF shared successfully!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF generato e condiviso!')),
        );
      }
    } catch (e) {
      debugPrint('ERROR in PDF generation: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nella generazione del PDF: $e')),
        );
      }
    }
  }

  void _shareWeeklyPDF() async {
    await _generateWeeklyTrainingPDF();
  }

  // Helper per ottenere nome completo campo dal codice
  String _getFieldName(String fieldCode) {
    try {
      final fieldService = context.read<FieldService>();
      final field = fieldService.fields.firstWhere(
        (f) => f.code == fieldCode,
      );
      return field.name; // Ritorna il NOME completo del campo
    } catch (e) {
      return fieldCode; // Se non trova, usa il codice come fallback
    }
  }

  String _formatMatchType(Match match) {
    if (match.matchType.toLowerCase() == 'campionato' && match.giornata != null && match.giornata!.isNotEmpty) {
      // Prova a trovare il girone della squadra
      try {
        final teamService = context.read<TeamService>();
        final team = teamService.teams.where((t) => t.category == match.auroraTeam).firstOrNull;
        final gironeText = team?.girone != null && team!.girone!.isNotEmpty ? ' (${team.girone})' : '';
        return '${match.giornata} Campionato$gironeText';
      } catch (e) {
        // Se non riesce a accedere al context, ritorna senza girone
        return '${match.giornata} Campionato';
      }
    }
    switch (match.matchType.toLowerCase()) {
      case 'campionato':
        return 'Campionato';
      case 'torneo':
        return 'Torneo';
      case 'coppa':
        return 'Coppa';
      case 'amichevole':
        return 'Amichevole';
      default:
        return match.matchType.isEmpty ? '' : '${match.matchType[0].toUpperCase()}${match.matchType.substring(1).toLowerCase()}';
    }
  }

  String _formatAddress(String address) {
    return address
        .replaceAll('COMUNALE', 'Com.')
        .replaceAll('comunale', 'Com.')
        .replaceAll('Comunale', 'Com.')
        .toLowerCase()
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
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

  // Helper per ottenere le partite per un giorno specifico e squadra
  // Esclude sabato (6) e domenica (7) per il planning settimanale
  List<Match> _getMatchesForDay(DateTime date, String teamCategory) {
    try {
      // Escludi sabato e domenica per il planning settimanale
      if (date.weekday == 6 || date.weekday == 7) {
        return [];
      }

      final matchService = context.read<MatchService>();
      return matchService.getMatchesForDate(date).where((match) =>
        match.auroraTeam == teamCategory
      ).toList();
    } catch (e) {
      return [];
    }
  }

  // Controlla se ci sono concomitanze (stesso orario e stesso campo)
  bool _hasConflicts(List<Match> matches) {
    // Raggruppa le partite per orario e campo
    Map<String, List<Match>> conflicts = {};

    for (Match match in matches) {
      String key = '${match.time}_${match.location}';
      conflicts[key] ??= [];
      conflicts[key]!.add(match);
    }

    // Controlla ogni gruppo per vedere se ci sono troppi match
    for (String key in conflicts.keys) {
      List<Match> matchesAtSameTime = conflicts[key]!;
      if (matchesAtSameTime.length <= 1) continue;

      // Ottieni il nome del campo per questo gruppo
      String fieldName = _getFieldName(matchesAtSameTime.first.location);

      // Campi che possono ospitare fino a 2 squadre contemporaneamente
      bool canHost2Teams = (fieldName.toLowerCase().contains('oratorio') &&
                           fieldName.toLowerCase().contains('seriate') &&
                           fieldName.toLowerCase().contains('erba')) ||
                          fieldName.toLowerCase().contains('ora11');

      if (canHost2Teams) {
        if (matchesAtSameTime.length > 2) {
          return true; // Più di 2 squadre contemporaneamente
        }
      } else {
        // Altri campi possono ospitare solo 1 squadra alla volta
        if (matchesAtSameTime.length > 1) {
          return true;
        }
      }
    }

    return false;
  }


  // Helper per ottenere il nome del giorno
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Lunedì';
      case 2: return 'Martedì';
      case 3: return 'Mercoledì';
      case 4: return 'Giovedì';
      case 5: return 'Venerdì';
      case 6: return 'Sabato';
      case 7: return 'Domenica';
      default: return 'Giorno $weekday';
    }
  }

  void _checkTrainingConflicts() {
    final trainingService = context.read<TrainingService>();
    final teamService = context.read<TeamService>();

    List<String> conflicts = [];

    // Funzione per verificare se una categoria può condividere campo/orario
    bool canShareField(String category) {
      final categoryLower = category.toLowerCase();
      return categoryLower.contains('pulcini') ||
             categoryLower.contains('primi calci') ||
             categoryLower.contains('piccoli amici');
    }

    // Controlla i conflitti per ogni giorno della settimana (lunedì-venerdì)
    for (int weekday = 1; weekday <= 5; weekday++) {
      // Raggruppa allenamenti per campo e orario
      Map<String, Map<String, List<String>>> fieldTimeTeams = {};

      for (final team in teamService.teams) {
        final training = _getTraining(trainingService, team.category, weekday);
        if (training != null) {
          final fieldCode = training.fieldCode;
          final startTime = training.startTime;
          final endTime = training.endTime;

          // Inizializza le mappe se necessario
          fieldTimeTeams[fieldCode] ??= {};

          // Controlla conflitti con altri allenamenti sullo stesso campo
          for (final existingTime in fieldTimeTeams[fieldCode]!.keys) {
            if (_hasTimeOverlap(startTime, endTime, existingTime.split('-')[0], existingTime.split('-')[1])) {
              // Conflitto trovato
              final conflictingTeams = fieldTimeTeams[fieldCode]![existingTime]!;

              // Verifica se il conflitto coinvolge solo categorie che possono condividere campo e orario
              final currentCanShare = canShareField(team.category);
              final allConflictingCanShare = conflictingTeams.every((category) => canShareField(category));

              // Verifica capacità del campo
              bool fieldCanHost2Teams = fieldCode.toLowerCase().contains('ora11') ||
                                       (fieldCode.toLowerCase().contains('oratorio') &&
                                        fieldCode.toLowerCase().contains('seriate') &&
                                        fieldCode.toLowerCase().contains('erba'));

              // Calcola il numero totale di squadre che si allenerebbero contemporaneamente
              int totalTeams = conflictingTeams.length + 1; // +1 per la squadra corrente

              bool shouldSkipConflict = false;

              if (currentCanShare && allConflictingCanShare) {
                // Tutte le categorie possono condividere, non segnalare il conflitto
                shouldSkipConflict = true;
              } else if (fieldCanHost2Teams && totalTeams <= 2) {
                // Il campo può ospitare 2 squadre e non superano il limite
                shouldSkipConflict = true;
              }

              if (!shouldSkipConflict) {
                conflicts.add(
                  '${_getDayName(weekday)}:\nConcomitanza campo $fieldCode tra ${conflictingTeams.join(", ")} e ${team.category} (${_formatTime(startTime)}-${_formatTime(endTime)})'
                );
              }
            }
          }

          // Aggiungi l'allenamento corrente
          final timeKey = '$startTime-$endTime';
          fieldTimeTeams[fieldCode]![timeKey] ??= [];
          fieldTimeTeams[fieldCode]![timeKey]!.add(team.category);
        }
      }
    }
    
    // Mostra risultati
    if (conflicts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessuna concomitanza trovata!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      _showConflictsDialog(conflicts);
    }
  }

  bool _hasTimeOverlap(String start1, String end1, String start2, String end2) {
    try {
      // Converte gli orari in minuti per confronto più facile
      int start1Minutes = _timeToMinutes(start1);
      int end1Minutes = _timeToMinutes(end1);
      int start2Minutes = _timeToMinutes(start2);
      int end2Minutes = _timeToMinutes(end2);
      
      // Verifica se i due intervalli si sovrappongono
      return (start1Minutes < end2Minutes && end1Minutes > start2Minutes);
    } catch (e) {
      return false; // In caso di errore, assume nessuna sovrapposizione
    }
  }

  int _timeToMinutes(String time) {
    final cleanTime = time.replaceAll(RegExp(r'[^0-9:]+'), '');
    if (cleanTime.contains(':')) {
      final parts = cleanTime.split(':');
      if (parts.length >= 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    }
    return 0;
  }

  void _showConflictsDialog(List<String> conflicts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Concomitanze Trovate',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.red,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: math.min(700, conflicts.length * 120.0 + 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trovate ${conflicts.length} concomitanze:',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: conflicts.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withAlpha(77), width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.error_outline,
                              color: Colors.red[600],
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              conflicts[index],
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
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
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }
}

// Widget separato per il dialog di progresso
class _ProgressDialog extends StatefulWidget {
  final String title;
  final int totalSteps;

  const _ProgressDialog({
    super.key,
    required this.title,
    required this.totalSteps,
  });

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  int currentStep = 0;
  String currentMessage = '';

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalSteps > 0 ? currentStep / widget.totalSteps : 0.0;
    
    return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.copy, color: Color(0xFF1E3A8A)),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra di progresso
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1E3A8A)),
              minHeight: 8,
            ),
            const SizedBox(height: 16),
            // Percentuale
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
    );
  }

  // Metodo per aggiornare il progresso dall'esterno
  void updateProgress(int step) {
    if (mounted) {
      setState(() {
        currentStep = step;
      });
      
      // Auto-chiudi quando completato
      if (step >= widget.totalSteps) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }
}
