import 'package:flutter/material.dart';
import '../models/player_model.dart';

class EditStaffDialog extends StatefulWidget {
  final Player staff;
  final Function(Player) onSave;

  const EditStaffDialog({
    super.key,
    required this.staff,
    required this.onSave,
  });

  @override
  State<EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<EditStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _selectedRole;

  final List<String> _staffRoles = [
    'Allenatore',
    'Vice Allenatore',
    'Preparatore Atletico',
    'Preparatore dei Portieri',
    'Team Manager',
    'Fisioterapista',
    'Medico Sociale',
    'Dirigente',
    'Accompagnatore',
    'Altro',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.staff.name);
    _selectedRole = widget.staff.position;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(

      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nome e Cognome *',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Inserisci il nome dello staff';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ruolo *',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.work),
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRole,
                    items: _staffRoles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Expanded(
                          child: Text(role),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Seleziona un ruolo';
                      }
                      return null;
                    },
                  ),
                ],
              ),
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
          onPressed: _saveStaff,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
          ),
          child: const Text('Salva'),
        ),
      ],
    );
  }

  void _saveStaff() {
    if (_formKey.currentState!.validate()) {
      final updatedStaff = Player(
        id: widget.staff.id, // Keep the original ID
        name: _nameController.text.trim(),
        position: _selectedRole,
        teamCategory: widget.staff.teamCategory, // Keep the original team category
        isStaff: true, // Staff always remains staff
      );

      widget.onSave(updatedStaff);
    }
  }
}
