import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/training_model.dart';
import '../models/field_model.dart';
import '../services/field_service.dart';

class TrainingFormDialog extends StatefulWidget {
  final String teamCategory;
  final int weekday;
  final DateTime weekStart;
  final Training? training;
  final String? suggestedFieldCode;
  final Function(Training) onSave;
  final VoidCallback? onDelete;

  const TrainingFormDialog({
    super.key,
    required this.teamCategory,
    required this.weekday,
    required this.weekStart,
    this.training,
    this.suggestedFieldCode,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<TrainingFormDialog> createState() => _TrainingFormDialogState();
}

class _TrainingFormDialogState extends State<TrainingFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _startTimeController;
  late TextEditingController _endTimeController;
  String? _selectedFieldCode;
  bool _hasGoalkeeper = false;

  @override
  void initState() {
    super.initState();
    final training = widget.training;
    
    _startTimeController = TextEditingController(text: training?.startTime ?? '18:00');
    _endTimeController = TextEditingController(text: training?.endTime ?? '19:30');
    _selectedFieldCode = training?.fieldCode ?? widget.suggestedFieldCode;
    _hasGoalkeeper = training?.hasGoalkeeper ?? false;
  }

  @override
  void dispose() {
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  String get _weekdayName {
    switch (widget.weekday) {
      case 1: return 'Lunedì';
      case 2: return 'Martedì';
      case 3: return 'Mercoledì';
      case 4: return 'Giovedì';
      case 5: return 'Venerdì';
      default: return 'Lunedì';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 600;
    final isVerySmallScreen = screenWidth < 400;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 40,
        vertical: isSmallScreen ? 20 : 24,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isSmallScreen ? screenWidth - 32 : 500,
          maxHeight: screenHeight * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.training == null ? 'Nuovo Allenamento' : 'Modifica Allenamento',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isVerySmallScreen ? 14 : 16,
                        color: const Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info squadra e giorno
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Squadra: ${widget.teamCategory}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isVerySmallScreen ? 11 : 12,
                              ),
                            ),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            Text(
                              'Giorno: $_weekdayName',
                              style: TextStyle(
                                fontSize: isVerySmallScreen ? 10 : 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      
                      // Orari
                      isSmallScreen 
                          ? _buildTimeFieldsVertical()
                          : _buildTimeFieldsHorizontal(),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      
                      // Campo
                      Consumer<FieldService>(
                        builder: (context, fieldService, child) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Campo *', 
                                style: TextStyle(
                                  fontSize: isVerySmallScreen ? 11 : 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: isSmallScreen ? 6 : 8),
                              DropdownButtonFormField<String>(
                                value: _selectedFieldCode,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.location_on, 
                                    size: isVerySmallScreen ? 16 : 18,
                                  ),
                                  border: const OutlineInputBorder(),
                                  hintText: 'Seleziona campo',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: isVerySmallScreen ? 8 : 12, 
                                    vertical: isVerySmallScreen ? 6 : 8,
                                  ),
                                  hintStyle: TextStyle(
                                    fontSize: isVerySmallScreen ? 11 : 12,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: isVerySmallScreen ? 11 : 12, 
                                  color: Colors.black,
                                ),
                                items: fieldService.fields
                                    .fold<Map<String, Field>>({}, (map, field) {
                                      map[field.code] = field;
                                      return map;
                                    })
                                    .values
                                    .map((Field field) {
                                  return DropdownMenuItem<String>(
                                    value: field.code,
                                    child: Text(
                                      '${field.code} - ${field.name}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isVerySmallScreen ? 10 : 11,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Seleziona il campo';
                                  }
                                  return null;
                                },
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedFieldCode = newValue;
                                  });
                                },
                              ),
                              if (fieldService.fields.isEmpty) ...[
                                SizedBox(height: isSmallScreen ? 6 : 8),
                                Text(
                                  'Nessun campo configurato. Aggiungili dalle Impostazioni.',
                                  style: TextStyle(
                                    fontSize: isVerySmallScreen ? 9 : 10,
                                    color: Colors.orange[700],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      
                      // Checkbox Portiere
                      Row(
                        children: [
                          Checkbox(
                            value: _hasGoalkeeper,
                            onChanged: (bool? value) {
                              setState(() {
                                _hasGoalkeeper = value ?? false;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Allenamento Portieri',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Actions
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: isSmallScreen ? _buildActionsVertical() : _buildActionsHorizontal(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeFieldsHorizontal() {
    return Row(
      children: [
        Expanded(child: _buildStartTimeField()),
        const SizedBox(width: 12),
        Expanded(child: _buildEndTimeField()),
      ],
    );
  }

  Widget _buildTimeFieldsVertical() {
    return Column(
      children: [
        _buildStartTimeField(),
        const SizedBox(height: 12),
        _buildEndTimeField(),
      ],
    );
  }

  Widget _buildStartTimeField() {
    final isVerySmallScreen = MediaQuery.of(context).size.width < 400;
    
    return TextFormField(
      controller: _startTimeController,
      decoration: InputDecoration(
        labelText: 'Ora Inizio *',
        prefixIcon: Icon(Icons.access_time, size: isVerySmallScreen ? 16 : 18),
        border: const OutlineInputBorder(),
        hintText: 'es. 18:00',
        labelStyle: TextStyle(fontSize: isVerySmallScreen ? 11 : 12),
        hintStyle: TextStyle(fontSize: isVerySmallScreen ? 10 : 11),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isVerySmallScreen ? 8 : 12,
          vertical: isVerySmallScreen ? 8 : 10,
        ),
      ),
      style: TextStyle(fontSize: isVerySmallScreen ? 11 : 12),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Inserisci l\'ora di inizio';
        }
        if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value)) {
          return 'Formato: HH:MM';
        }
        return null;
      },
    );
  }

  

  Widget _buildEndTimeField() {
    final isVerySmallScreen = MediaQuery.of(context).size.width < 400;
    
    return TextFormField(
      controller: _endTimeController,
      decoration: InputDecoration(
        labelText: 'Ora Fine',
        prefixIcon: Icon(Icons.access_time_filled, size: isVerySmallScreen ? 16 : 18),
        border: const OutlineInputBorder(),
        hintText: 'es. 19:30',
        labelStyle: TextStyle(fontSize: isVerySmallScreen ? 11 : 12),
        hintStyle: TextStyle(fontSize: isVerySmallScreen ? 10 : 11),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isVerySmallScreen ? 8 : 12,
          vertical: isVerySmallScreen ? 8 : 10,
        ),
      ),
      style: TextStyle(fontSize: isVerySmallScreen ? 11 : 12),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Inserisci l\'ora di fine';
        }
        if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value)) {
          return 'Formato: HH:MM';
        }
        return null;
      },
    );
  }

  Widget _buildActionsHorizontal() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.onDelete != null) ...[
          TextButton(
            onPressed: _showDeleteConfirmation,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Elimina', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _saveTraining,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Text(
            widget.training == null ? 'Aggiungi' : 'Salva',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsVertical() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _saveTraining,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text(
            widget.training == null ? 'Aggiungi' : 'Salva',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (widget.onDelete != null) ...[
              Expanded(
                child: TextButton(
                  onPressed: _showDeleteConfirmation,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Elimina', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annulla', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione', style: TextStyle(fontSize: 16)),
        content: Text(
          'Sei sicuro di voler eliminare l\'allenamento del ${widget.teamCategory} di $_weekdayName?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla', style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete!();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Elimina', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _saveTraining() {
    if (_formKey.currentState!.validate()) {
      final training = Training(
        id: widget.training?.id,
        teamCategory: widget.teamCategory,
        weekday: widget.weekday,
        startTime: _startTimeController.text.trim(),
        endTime: _endTimeController.text.trim(),
        fieldCode: _selectedFieldCode!,
        weekStart: widget.weekStart,
        hasGoalkeeper: _hasGoalkeeper,
      );
      
      widget.onSave(training);
    }
  }
}