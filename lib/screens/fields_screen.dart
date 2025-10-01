import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/field_model.dart';
import '../services/field_service.dart';

class FieldsScreen extends StatefulWidget {
  const FieldsScreen({super.key});

  @override
  State<FieldsScreen> createState() => _FieldsScreenState();
}

class _FieldsScreenState extends State<FieldsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldService = context.read<FieldService>();
      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Campi di Allenamento',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<FieldService>(
        builder: (context, fieldService, child) {
          if (fieldService.isLoading && fieldService.fields.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (fieldService.fields.isEmpty) {
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
                    'Nessun campo configurato',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddFieldDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Aggiungi Campo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // Bottom padding per FAB
                  itemCount: fieldService.fields.length,
                  itemBuilder: (context, index) {
                    final field = fieldService.fields[index];
                    return _buildFieldCard(field);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddFieldDialog(),
        backgroundColor: const Color(0xFF1E3A8A),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildFieldCard(Field field) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1E3A8A),
          child: Text(
            field.code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          field.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    field.address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.code,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  'Codice: ${field.code}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _showEditFieldDialog(field);
            } else if (value == 'delete') {
              _showDeleteFieldDialog(field);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Modifica'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Elimina'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFieldDialog() {
    _showFieldDialog();
  }

  void _showEditFieldDialog(Field field) {
    _showFieldDialog(field: field);
  }

  void _showFieldDialog({Field? field}) {
    final nameController = TextEditingController(text: field?.name ?? '');
    final addressController = TextEditingController(text: field?.address ?? '');
    final codeController = TextEditingController(text: field?.code ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          field == null ? 'Nuovo Campo' : 'Modifica Campo',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome Campo *',
                hintText: 'es. Campo Comunale',
                prefixIcon: Icon(Icons.sports_soccer),
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontSize: 12),
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Indirizzo *',
                hintText: 'es. Via dello Sport, 1',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontSize: 12),
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Sigla Campo *',
                hintText: 'es. CC, CSP, A1',
                prefixIcon: Icon(Icons.code),
                border: OutlineInputBorder(),
                labelStyle: TextStyle(fontSize: 12),
              ),
              style: const TextStyle(fontSize: 12),
              textCapitalization: TextCapitalization.characters,
              maxLength: 5,
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
              if (nameController.text.trim().isNotEmpty &&
                  addressController.text.trim().isNotEmpty &&
                  codeController.text.trim().isNotEmpty) {
                
                final fieldService = context.read<FieldService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                final fieldData = Field(
                  id: field?.id,
                  name: nameController.text.trim(),
                  address: addressController.text.trim(),
                  code: codeController.text.trim().toUpperCase(),
                );
                
                final success = field == null
                    ? await fieldService.addField(fieldData)
                    : await fieldService.updateField(fieldData);
                
                navigator.pop();
                if (success) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(field == null 
                        ? 'Campo aggiunto con successo!' 
                        : 'Campo aggiornato con successo!')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(fieldService.errorMessage ?? 
                          'Errore nell\'operazione'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: Text(
              field == null ? 'Aggiungi' : 'Salva',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteFieldDialog(Field field) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text('Sei sicuro di voler eliminare il campo "${field.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final fieldService = context.read<FieldService>();

              navigator.pop();
              final success = await fieldService.deleteField(field.id!);
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Campo eliminato con successo!')), 
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
}