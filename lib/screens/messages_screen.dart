import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/match_service.dart';
import '../services/field_service.dart';
import '../models/match_model.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool showAvversarioSubMenu = false;

  // Funzione helper per formattare l'orario nel formato hh:mm
  String _formatTime(String time) {
    if (time.isEmpty) return time;

    try {
      // Se il tempo ha già il formato corretto (hh:mm), mantienilo
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time)) {
        final parts = time.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return time; // Fallback al valore originale
    }
    return time;
  }

  // Metodo per ordinare le partite per priorità agonistica
  List<Match> _sortMatchesByPriority(List<Match> matches) {
    // Definisce l'ordine di priorità per le squadre agonistiche
    const agonisticOrder = [
      'PRIMA SQUADRA',
      'U21', 'UNDER 21',
      'U19', 'UNDER 19', 'JUNIORES',
      'U18', 'UNDER 18',
      'U17', 'UNDER 17',
      'U16', 'UNDER 16',
      'U15', 'UNDER 15',
      'U14', 'UNDER 14',
      'ALLIEVI',
    ];

    return matches.toList()..sort((a, b) {
      // Prima ordina per tipologia: in casa prima di fuori casa
      if (a.isHome != b.isHome) {
        return a.isHome ? -1 : 1;
      }

      // Poi ordina per priorità agonistica
      final aTeam = a.auroraTeam?.toUpperCase() ?? '';
      final bTeam = b.auroraTeam?.toUpperCase() ?? '';

      int aIndex = agonisticOrder.length; // Default per squadre non agonistiche
      int bIndex = agonisticOrder.length;

      // Trova la priorità della squadra A
      for (int i = 0; i < agonisticOrder.length; i++) {
        if (aTeam.contains(agonisticOrder[i])) {
          aIndex = i;
          break;
        }
      }

      // Trova la priorità della squadra B
      for (int i = 0; i < agonisticOrder.length; i++) {
        if (bTeam.contains(agonisticOrder[i])) {
          bIndex = i;
          break;
        }
      }

      // Se hanno priorità diversa, ordina per priorità
      if (aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }

      // Se hanno la stessa priorità, ordina per data
      return a.date.compareTo(b.date);
    });
  }

  // Metodo per raggruppare le partite per settimana
  Map<String, List<Match>> _groupMatchesByWeek(List<Match> matches) {
    final Map<String, List<Match>> weeklyGroups = {};

    for (final match in matches) {
      // Calcola l'inizio della settimana (Lunedì)
      final matchDate = match.date;
      final daysSinceMonday = (matchDate.weekday - 1) % 7;
      final weekStart = matchDate.subtract(Duration(days: daysSinceMonday));
      final weekEnd = weekStart.add(const Duration(days: 6));

      // Crea la chiave della settimana
      final weekKey = '${DateFormat('dd/MM').format(weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}';

      // Raggruppa per settimana
      if (!weeklyGroups.containsKey(weekKey)) {
        weeklyGroups[weekKey] = [];
      }
      weeklyGroups[weekKey]!.add(match);
    }

    // Ordina ogni gruppo per priorità agonistica
    for (final weekKey in weeklyGroups.keys) {
      weeklyGroups[weekKey] = _sortMatchesByPriority(weeklyGroups[weekKey]!);
    }

    return weeklyGroups;
  }

  void _showInfoAvversariDialog() {
    final matchService = context.read<MatchService>();

    // Filtra partite future in casa che non sono di riposo
    final allFutureMatches = matchService.matches.where((match) {
      final today = DateTime.now();
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      final todayDate = DateTime(today.year, today.month, today.day);
      return !match.isRest &&
             match.isHome && // Solo partite in casa
             (matchDate.isAfter(todayDate) || matchDate.isAtSameMomentAs(todayDate));
    }).toList();

    // Raggruppa le partite per settimana
    final weeklyGroups = _groupMatchesByWeek(allFutureMatches);

    if (weeklyGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna partita futura disponibile')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Seleziona Partita',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: weeklyGroups.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final weekEntry = entry.value;
                  final weekRange = weekEntry.key;
                  final weekMatches = weekEntry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header della settimana
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        margin: EdgeInsets.only(bottom: 8, top: index == 0 ? 0 : 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Settimana $weekRange',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Partite della settimana
                      ...weekMatches.map((match) {
                        final shortDateText = DateFormat('dd/MM/yy').format(match.date);
                        final formattedTime = _formatTime(match.time);
                        final dayName = DateFormat('EEEE', 'it').format(match.date);

                        // Determina il colore basato sulla priorità agonistica
                        final auroraTeam = match.auroraTeam?.toUpperCase() ?? '';
                        const agonisticOrder = [
                          'PRIMA SQUADRA', 'U21', 'UNDER 21', 'U19', 'UNDER 19', 'JUNIORES',
                          'U18', 'UNDER 18', 'U17', 'UNDER 17', 'U16', 'UNDER 16',
                          'U15', 'UNDER 15', 'U14', 'UNDER 14', 'ALLIEVI'
                        ];

                        final isAgonistica = agonisticOrder.any((cat) => auroraTeam.contains(cat));

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          child: ListTile(
                            title: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$dayName $shortDateText - $formattedTime\n',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isAgonistica ? Colors.blue : Colors.black87,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '${match.opponent.toUpperCase()}\n',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  TextSpan(
                                    text: match.auroraTeam ?? "Categoria non specificata",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: isAgonistica ? Colors.blue : Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              _generateInfoAvversariMessage(match);
                            },
                          ),
                        );
                      }).toList(),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
          ],
        );
      },
    );
  }

  void _generateInfoAvversariMessage(Match match) {
    final fieldService = context.read<FieldService>();

    // Genera il messaggio per Info da Avversari
    final categoria = match.auroraTeam ?? "CATEGORIA";
    final avversario = match.opponent.toUpperCase();
    final dateText = DateFormat('dd/MM/yy').format(match.date);

    // Formatta l'orario nel formato hh:mm
    final formattedTime = _formatTime(match.time);

    // Cerca l'indirizzo reale del campo dalla tabella fields
    String realAddress = match.location;
    final field = fieldService.fields.where((field) =>
      field.name.toLowerCase().contains(match.location.toLowerCase()) ||
      field.code.toLowerCase() == match.location.toLowerCase()
    ).firstOrNull;

    if (field != null) {
      realAddress = field.address;
    }

    final location = realAddress.isNotEmpty ? realAddress : match.location;

    // Crea il link Google Maps
    final encodedAddress = Uri.encodeComponent(location);
    final googleMapsLink = "https://www.google.com/maps/search/?api=1&query=$encodedAddress";

    final message = '''$categoria
${match.giornata ?? ""} CAMPIONATO
$dateText - $formattedTime

AURORA SERIATE
$avversario

Buongiorno,
Sono un dirigente dell' Aurora Seriate.
Per una migliore organizzazione, Le chiediamo di comunicarci il colore della muta di gara che la Sua squadra utilizzerà.

Grazie della collaborazione

ℹ️ INFO UTILI

📍 $location

❇️ Squadre (staff e giocatori)
📌 Presentarsi all'ingresso con gruppo completo staff e giocatori.

🅿️ PARCHEGGI GRATUITI

🗺️ Google Maps: $googleMapsLink''';

    _showMessageDialog('Messaggio Info ad Avversari', message, match);
  }

  void _showMessageDialog(String title, String message, [Match? match]) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _shareOnWhatsApp(message),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.message, size: 18),
                  SizedBox(width: 4),
                  Text('WhatsApp'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareOnWhatsApp(String message) async {
    // Codifica il messaggio per URL
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = "whatsapp://send?text=$encodedMessage";

    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback: prova con WhatsApp Web
        final webUrl = "https://web.whatsapp.com/send?text=$encodedMessage";
        final webUri = Uri.parse(webUrl);
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('WhatsApp non disponibile su questo dispositivo')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nell\'aprire WhatsApp')),
        );
      }
    }
  }


  @override
  void initState() {
    super.initState();
    // Carica le partite e i campi quando la schermata viene inizializzata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final matchService = context.read<MatchService>();
      final fieldService = context.read<FieldService>();

      if (matchService.matches.isEmpty && !matchService.isLoading) {
        matchService.loadMatches();
      }

      if (fieldService.fields.isEmpty && !fieldService.isLoading) {
        fieldService.loadFields();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messaggi',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<MatchService>(
        builder: (context, matchService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Pulsante Avversario
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      showAvversarioSubMenu = !showAvversarioSubMenu;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  icon: Icon(
                    showAvversarioSubMenu ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 24,
                  ),
                  label: const Text(
                    'Avversario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Sotto-menu Avversario (visibile solo se showAvversarioSubMenu è true)
                if (showAvversarioSubMenu) ...[
                  const SizedBox(height: 12),

                  // Info da Avversari
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0),
                    child: ElevatedButton.icon(
                      onPressed: _showInfoAvversariDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.info_outline, size: 20),
                      label: const Text(
                        'Info da Avversari',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Info ai Genitori
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Implementare azione per Info ai Genitori
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Info ai Genitori - Da implementare')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.family_restroom, size: 20),
                      label: const Text(
                        'Info ai Genitori',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}