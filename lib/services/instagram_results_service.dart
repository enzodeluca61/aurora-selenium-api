import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/raster.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/match_model.dart';
import '../models/team_model.dart';

class InstagramResultsService {
  static const double pageWidth = 21.0; // cm
  static const double pageHeight = 29.7; // cm A4
  static const double margin = 1.0; // cm
  static const double dayHeaderHeight = 1.5; // cm
  static const double matchRowHeight = 1.2; // cm

  // Cache per i loghi delle squadre
  static final Map<String, pw.MemoryImage?> _logoCache = {};

  /// Genera un PDF con i risultati delle partite per Instagram
  static Future<Uint8List> generateResultsPdf({
    required List<Match> matches,
    required DateTime startDate,
    required DateTime endDate,
    List<Team>? teams,
  }) async {
    final pdf = pw.Document();

    // Carica il font BebasNeue
    final bebasNeueFontData = await rootBundle.load('assets/fonts/BebasNeue Bold.ttf');
    final bebasNeueFont = pw.Font.ttf(bebasNeueFontData);

    // Carica le immagini
    final backgroundImage = await _loadAssetImage('assets/images/sfondo_ris_social_ex.jpg');
    final dayChangeImage = await _loadAssetImage('assets/images/cambiogiorno_ridotto.png');
    final rowBackgroundImage = await _loadAssetImage('assets/images/fondoriga60.png');
    final auroraLogo = await _loadAssetImage('assets/images/aurora_logo.png');

    // Raggruppa le partite per giorno e ordina per categoria
    final matchesByDay = _groupMatchesByDay(matches, startDate, endDate, teams);

    // Precarica i loghi per tutte le partite
    final Map<String, pw.MemoryImage?> teamLogos = {};
    final Set<String> uniqueTeams = {};

    // Raccogli tutti i nomi delle squadre uniche dalle partite
    for (final dayMatches in matchesByDay.values) {
      for (final match in dayMatches) {
        final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
        final awayTeam = !match.isHome ? 'AURORA SERIATE' : match.opponent;
        uniqueTeams.add(homeTeam);
        uniqueTeams.add(awayTeam);
      }
    }

    // Carica tutti i loghi in parallelo con timeout
    try {
      final futures = uniqueTeams.map((teamName) => _loadTeamLogo(teamName)).toList();
      final results = await Future.wait(futures, eagerError: false).timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.filled(uniqueTeams.length, null),
      );

      // Associa i risultati alle squadre
      int index = 0;
      for (final teamName in uniqueTeams) {
        final cleanTeamName = _cleanTeamNameForLogo(teamName);
        teamLogos[cleanTeamName] = results[index];
        index++;
      }
    } catch (e) {
      debugPrint('Timeout o errore nel caricamento loghi: $e');
      // Continua senza loghi se il caricamento fallisce
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            width: double.infinity,
            height: double.infinity,
            decoration: pw.BoxDecoration(
              image: pw.DecorationImage(
                image: backgroundImage,
                fit: pw.BoxFit.cover,
              ),
            ),
            child: pw.Column(
              children: [
                pw.SizedBox(height: PdfPageFormat.cm * 9), // Spazio dall'alto - aumentato a 9cm
                ...matchesByDay.entries.map((dayEntry) {
                  return _buildDaySection(
                    dayEntry.key,
                    dayEntry.value,
                    dayChangeImage,
                    rowBackgroundImage,
                    auroraLogo,
                    bebasNeueFont,
                    teamLogos,
                  );
                }).toList(),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Genera un JPG con i risultati delle partite per Instagram
  static Future<Uint8List> generateResultsJpg({
    required List<Match> matches,
    required DateTime startDate,
    required DateTime endDate,
    List<Team>? teams,
  }) async {
    // Prima genera il PDF
    final pdfBytes = await generateResultsPdf(
      matches: matches,
      startDate: startDate,
      endDate: endDate,
      teams: teams,
    );

    // Converte PDF in immagine usando il metodo corretto
    final images = <PdfRaster>[];
    await for (final page in Printing.raster(
      pdfBytes,
      pages: [0], // Solo la prima pagina
      dpi: 300, // Alta risoluzione per qualità Instagram
    )) {
      images.add(page);
    }

    if (images.isNotEmpty) {
      // Prende la prima pagina e converte in PNG di alta qualità
      final image = images.first;
      return await image.toPng();
    }

    throw Exception('Errore nella generazione dell\'immagine');
  }

  /// Carica un'immagine dagli assets
  static Future<pw.ImageProvider> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }

  /// Raggruppa le partite per giorno
  static Map<DateTime, List<Match>> _groupMatchesByDay(
    List<Match> matches,
    DateTime startDate,
    DateTime endDate,
    List<Team>? teams,
  ) {
    final Map<DateTime, List<Match>> result = {};

    // Prefissi delle categorie consentite per Instagram
    final allowedPrefixes = [
      'PRIMA',
      'PROMO',
      'U21',
      'U19',
      'U18',
      'U17',
      'U16',
      'U15',
      'U14'
    ];

    // Inizializza tutti i giorni della settimana
    DateTime currentDate = startDate;
    while (currentDate.isBefore(endDate.add(const Duration(days: 1)))) {
      result[DateTime(currentDate.year, currentDate.month, currentDate.day)] = [];
      currentDate = currentDate.add(const Duration(days: 1));
    }

    // Filtra e raggruppa solo le partite flaggate per il planning e delle categorie consentite
    for (final match in matches) {
      final matchDate = DateTime(match.date.year, match.date.month, match.date.day);
      final auroraTeamUpper = match.auroraTeam?.toUpperCase() ?? '';

      // Controlla se il nome della squadra inizia con uno dei prefissi consentiti
      final isAllowedCategory = allowedPrefixes.any((prefix) => auroraTeamUpper.startsWith(prefix));

      if (result.containsKey(matchDate) &&
          match.includeInPlanning &&
          isAllowedCategory) {
        result[matchDate]!.add(match);
      }
    }

    // Ordina le partite in ogni giorno per sortOrder della categoria
    if (teams != null) {
      for (final dayMatches in result.values) {
        dayMatches.sort((a, b) {
          final teamA = teams.firstWhere(
            (team) => team.category == a.auroraTeam,
            orElse: () => Team(category: '', sortOrder: 999),
          );
          final teamB = teams.firstWhere(
            (team) => team.category == b.auroraTeam,
            orElse: () => Team(category: '', sortOrder: 999),
          );
          return teamA.sortOrder.compareTo(teamB.sortOrder);
        });
      }
    }

    return result;
  }

  /// Costruisce una sezione per un giorno specifico
  static pw.Widget _buildDaySection(
    DateTime date,
    List<Match> matches,
    pw.ImageProvider dayChangeImage,
    pw.ImageProvider rowBackgroundImage,
    pw.ImageProvider auroraLogo,
    pw.Font bebasNeueFont,
    Map<String, pw.MemoryImage?> teamLogos,
  ) {
    if (matches.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final dayName = _getDayName(date);
    final dayString = '$dayName ${DateFormat('dd.MM').format(date)}';

    return pw.Column(
      children: [
        // Header del giorno
        pw.Container(
          width: double.infinity,
          height: PdfPageFormat.cm * dayHeaderHeight,
          decoration: pw.BoxDecoration(
            image: pw.DecorationImage(
              image: dayChangeImage,
              fit: pw.BoxFit.cover,
            ),
          ),
          child: pw.Center(
            child: pw.Text(
              dayString,
              style: pw.TextStyle(
                font: bebasNeueFont,
                fontSize: 23, // Aumentato di 4px (da 19 a 23)
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 8), // Spazio tra cambio giorno e prima riga
        // Partite del giorno
        pw.Column(
          children: matches.map((match) => pw.Column(
            children: [
              _buildMatchRow(
                match,
                rowBackgroundImage,
                auroraLogo,
                bebasNeueFont,
                teamLogos,
              ),
              pw.SizedBox(height: 6), // Diminuito spazio tra le righe
            ],
          )).toList(),
        ),
        pw.SizedBox(height: PdfPageFormat.cm * 0.5), // Spazio tra giorni
      ],
    );
  }

  /// Costruisce una riga per una singola partita
  static pw.Widget _buildMatchRow(
    Match match,
    pw.ImageProvider rowBackgroundImage,
    pw.ImageProvider auroraLogo,
    pw.Font bebasNeueFont,
    Map<String, pw.MemoryImage?> teamLogos,
  ) {
    // Determina squadra casa e fuori casa
    final bool auroraInCasa = match.isHome;
    final String squadraCasa = auroraInCasa ? (match.auroraTeam ?? 'AURORA SERIATE') : match.opponent;
    final String squadraFuori = auroraInCasa ? match.opponent : (match.auroraTeam ?? 'AURORA SERIATE');
    final int goalCasa = auroraInCasa ? (match.goalsAurora ?? 0) : (match.goalsOpponent ?? 0);
    final int goalFuori = auroraInCasa ? (match.goalsOpponent ?? 0) : (match.goalsAurora ?? 0);

    return pw.Container(
      width: double.infinity,
      height: PdfPageFormat.cm * matchRowHeight,
      decoration: pw.BoxDecoration(
        image: pw.DecorationImage(
          image: rowBackgroundImage,
          fit: pw.BoxFit.cover,
        ),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Colonna 1: Logo squadra casa
            pw.Container(
              width: 40,
              height: 50,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5DC'), // Colore beige chiaro simile al cambiogiorno
                border: pw.Border.all(color: PdfColors.white, width: 2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: auroraInCasa
                    ? pw.Image(auroraLogo, width: 26, height: 26)
                    : _buildTeamLogo(squadraCasa, teamLogos, bebasNeueFont, 26),
              ),
            ),
            pw.SizedBox(width: 8),
            // Colonna 2: Nome squadra casa
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  squadraCasa,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: auroraInCasa ? 16 : 15, // +1px per Aurora in casa
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.right,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            // Colonna 3: Goal casa
            pw.Container(
              width: 30,
              alignment: pw.Alignment.center,
              child: pw.Text(
                goalCasa.toString(),
                style: pw.TextStyle(
                  font: bebasNeueFont,
                  fontSize: 19,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            // Colonna 4: Goal fuori casa
            pw.Container(
              width: 30,
              alignment: pw.Alignment.center,
              child: pw.Text(
                goalFuori.toString(),
                style: pw.TextStyle(
                  font: bebasNeueFont,
                  fontSize: 19,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            // Colonna 5: Nome squadra fuori casa
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  squadraFuori,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: !auroraInCasa ? 16 : 15, // +1px per Aurora fuori casa
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.left,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            // Colonna 6: Logo squadra fuori casa
            pw.Container(
              width: 40,
              height: 50,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5DC'), // Colore beige chiaro simile al cambiogiorno
                border: pw.Border.all(color: PdfColors.white, width: 2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: !auroraInCasa
                    ? pw.Image(auroraLogo, width: 26, height: 26)
                    : _buildTeamLogo(squadraFuori, teamLogos, bebasNeueFont, 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Costruisce un logo per squadra avversaria
  static pw.Widget _buildOpponentLogo(String teamName, pw.Font bebasNeueFont) {
    // Mappa delle squadre comuni con i loro colori rappresentativi
    final Map<String, Map<String, dynamic>> teamData = {
      'ATALANTA': {'color': PdfColors.blue800, 'text': 'A'},
      'INTER': {'color': PdfColors.blue900, 'text': 'I'},
      'MILAN': {'color': PdfColors.red800, 'text': 'M'},
      'JUVENTUS': {'color': PdfColors.black, 'text': 'J'},
      'BERGAMO': {'color': PdfColors.blue700, 'text': 'B'},
      'CREMONESE': {'color': PdfColors.red700, 'text': 'C'},
      'BRESCIA': {'color': PdfColors.blue600, 'text': 'BR'},
      'LECCO': {'color': PdfColors.blue500, 'text': 'L'},
      'COMO': {'color': PdfColors.cyan700, 'text': 'CO'},
      'ALBINOLEFFE': {'color': PdfColors.blue800, 'text': 'AL'},
      'VIRTUS': {'color': PdfColors.green800, 'text': 'V'},
      'SERIATE': {'color': PdfColors.red900, 'text': 'S'},
      'ROMANO': {'color': PdfColors.orange800, 'text': 'R'},
      'VERDELLO': {'color': PdfColors.green700, 'text': 'VE'},
      'VILLA': {'color': PdfColors.purple700, 'text': 'VI'},
      'CARAVAGGIO': {'color': PdfColors.brown, 'text': 'CA'},
      'TREVIGLIO': {'color': PdfColors.indigo800, 'text': 'T'},
    };

    // Cerca un pattern per la squadra
    PdfColor bgColor = PdfColors.red; // Colore di default MOLTO visibile
    String logoText = '?';

    final upperTeamName = teamName.toUpperCase();
    for (final entry in teamData.entries) {
      if (upperTeamName.contains(entry.key)) {
        bgColor = entry.value['color'];
        logoText = entry.value['text'];
        break;
      }
    }

    // Se non trovato, usa la prima lettera del nome con colore forte
    if (logoText == '?' && teamName.isNotEmpty) {
      logoText = teamName.substring(0, 1).toUpperCase();
      bgColor = PdfColors.deepOrange800; // Colore di fallback molto visibile
    }

    return pw.Container(
      width: 24, // Aumentato ulteriormente per visibilità
      height: 24,
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.white, width: 2), // Bordo più spesso
      ),
      child: pw.Center(
        child: pw.Text(
          logoText,
          style: pw.TextStyle(
            font: bebasNeueFont,
            fontSize: 16, // Aumentato per visibilità
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
    );
  }

  /// Ottiene il nome del giorno in italiano
  static String _getDayName(DateTime date) {
    switch (date.weekday) {
      case 1: return 'Lunedì';
      case 2: return 'Martedì';
      case 3: return 'Mercoledì';
      case 4: return 'Giovedì';
      case 5: return 'Venerdì';
      case 6: return 'Sabato';
      case 7: return 'Domenica';
      default: return 'Sconosciuto';
    }
  }

  /// Salva il PDF e restituisce il percorso del file
  static Future<String> savePdfToFile(Uint8List pdfBytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Mostra l'anteprima dell'immagine JPG
  static Future<void> showImagePreview(
    BuildContext context,
    Uint8List imageBytes,
    List<Match> matches,
    DateTime startDate,
    DateTime endDate,
    List<Team>? teams,
  ) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text(
              'Anteprima Risultati Instagram',
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
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: () async {
                  try {
                    // Salva temporaneamente il file
                    final directory = await getTemporaryDirectory();
                    final fileName = 'risultati_instagram_${DateFormat('ddMMyy').format(DateTime.now())}.jpg';
                    final file = File('${directory.path}/$fileName');
                    await file.writeAsBytes(imageBytes);

                    // Condividi il file
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: 'Risultati partite Aurora Seriate 1967',
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Errore nella condivisione: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                tooltip: 'Condividi',
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(
                imageBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pulisce il nome della squadra per la ricerca del logo
  static String _cleanTeamNameForLogo(String teamName) {
    return teamName
        .replaceAll('SQ.A', '')
        .replaceAll('SQ.B', '')
        .replaceAll('sq.a', '')
        .replaceAll('sq.b', '')
        .replaceAll('sq_a', '')
        .replaceAll('sq_b', '')
        .replaceAll('SQ_A', '')
        .replaceAll('SQ_B', '')
        .trim();
  }

  /// Carica il logo di una squadra dal storage Supabase
  static Future<pw.MemoryImage?> _loadTeamLogo(String teamName) async {
    try {
      final cleanTeamName = _cleanTeamNameForLogo(teamName);

      // Controlla prima nella cache
      if (_logoCache.containsKey(cleanTeamName)) {
        debugPrint('Logo trovato nella cache per: $cleanTeamName');
        return _logoCache[cleanTeamName];
      }

      debugPrint('=== LOGO LOADING DEBUG ===');
      debugPrint('Input nome originale: "$teamName"');
      debugPrint('Dopo _cleanTeamNameForLogo: "$cleanTeamName"');

      // Normalizza il nome della squadra per il filename
      var normalizedName = cleanTeamName
          .toLowerCase()
          .replaceAll('/', '')
          .replaceAll('-', '')
          .replaceAll('à', 'a')
          .replaceAll('è', 'e')
          .replaceAll('ì', 'i')
          .replaceAll('ò', 'o')
          .replaceAll('ù', 'u');

      // Pulisce ancora le varianti normalizzate di SQ.A/SQ.B
      normalizedName = normalizedName
          .replaceAll('sqa', '')
          .replaceAll('sqb', '')
          .trim();

      debugPrint('Nome finale normalizzato: "$normalizedName"');
      debugPrint('=========================');

      // Cerca il nome della squadra con diverse varianti
      final nameVariations = [
        normalizedName,
        normalizedName.toUpperCase(),
      ];

      for (final variation in nameVariations) {
        try {
          final fileName = '$variation.png';
          debugPrint('Provando: $fileName');

          // Prima prova con URL pubblico
          final publicUrl = Supabase.instance.client.storage
              .from('loghi')
              .getPublicUrl(fileName);

          debugPrint('URL pubblico: $publicUrl');

          final response = await http.get(
            Uri.parse(publicUrl),
          ).timeout(const Duration(seconds: 3));

          debugPrint('Response status code: ${response.statusCode}');

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            debugPrint('Logo caricato con successo per: $cleanTeamName');
            final logo = pw.MemoryImage(response.bodyBytes);
            // Salva nella cache
            _logoCache[cleanTeamName] = logo;
            return logo;
          } else {
            debugPrint('Logo non trovato o vuoto per: $fileName (status: ${response.statusCode})');
          }
        } catch (e) {
          debugPrint('Errore nel caricamento di $variation.png: $e');
        }
      }

      debugPrint('Nessun logo trovato per: $cleanTeamName');
      // Salva null nella cache per evitare ricaricamenti futuri
      _logoCache[cleanTeamName] = null;
      return null;
    } catch (e) {
      debugPrint('Errore generale nel caricamento logo per $teamName: $e');
      // Salva null nella cache per evitare ricaricamenti futuri
      final cleanTeamName = _cleanTeamNameForLogo(teamName);
      _logoCache[cleanTeamName] = null;
      return null;
    }
  }

  /// Costruisce un logo per squadra (usa logo reale se disponibile, altrimenti fallback)
  static pw.Widget _buildTeamLogo(String teamName, Map<String, pw.MemoryImage?> teamLogos, pw.Font bebasNeueFont, [double size = 22]) {
    final cleanTeamName = _cleanTeamNameForLogo(teamName);
    final logo = teamLogos[cleanTeamName];

    if (logo != null) {
      return pw.Image(logo, width: size, height: size, fit: pw.BoxFit.contain);
    } else {
      // Fallback al logo testuale se non c'è l'immagine, adattato alla nuova dimensione
      return _buildOpponentLogoWithSize(teamName, bebasNeueFont, size);
    }
  }

  /// Costruisce un logo testuale per squadra avversaria con dimensione personalizzata
  static pw.Widget _buildOpponentLogoWithSize(String teamName, pw.Font bebasNeueFont, double size) {
    // Mappa delle squadre comuni con i loro colori rappresentativi
    final Map<String, Map<String, dynamic>> teamData = {
      'ATALANTA': {'color': PdfColors.blue800, 'text': 'A'},
      'INTER': {'color': PdfColors.blue900, 'text': 'I'},
      'MILAN': {'color': PdfColors.red800, 'text': 'M'},
      'JUVENTUS': {'color': PdfColors.black, 'text': 'J'},
      'BERGAMO': {'color': PdfColors.blue700, 'text': 'B'},
      'CREMONESE': {'color': PdfColors.red700, 'text': 'C'},
      'BRESCIA': {'color': PdfColors.blue600, 'text': 'BR'},
      'LECCO': {'color': PdfColors.blue500, 'text': 'L'},
      'COMO': {'color': PdfColors.cyan700, 'text': 'CO'},
      'ALBINOLEFFE': {'color': PdfColors.blue800, 'text': 'AL'},
      'VIRTUS': {'color': PdfColors.green800, 'text': 'V'},
      'SERIATE': {'color': PdfColors.red900, 'text': 'S'},
      'ROMANO': {'color': PdfColors.orange800, 'text': 'R'},
      'VERDELLO': {'color': PdfColors.green700, 'text': 'VE'},
      'VILLA': {'color': PdfColors.purple700, 'text': 'VI'},
      'CARAVAGGIO': {'color': PdfColors.brown, 'text': 'CA'},
      'TREVIGLIO': {'color': PdfColors.indigo800, 'text': 'T'},
    };

    // Cerca un pattern per la squadra
    PdfColor bgColor = PdfColors.red; // Colore di default MOLTO visibile
    String logoText = '?';

    final upperTeamName = teamName.toUpperCase();
    for (final entry in teamData.entries) {
      if (upperTeamName.contains(entry.key)) {
        bgColor = entry.value['color'];
        logoText = entry.value['text'];
        break;
      }
    }

    // Se non trovato, usa la prima lettera del nome con colore forte
    if (logoText == '?' && teamName.isNotEmpty) {
      logoText = teamName.substring(0, 1).toUpperCase();
      bgColor = PdfColors.deepOrange800; // Colore di fallback molto visibile
    }

    // Calcola la dimensione del font in base alla dimensione del container
    final fontSize = size * 0.55; // Proporzione tra font e dimensione container

    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Center(
        child: pw.Text(
          logoText,
          style: pw.TextStyle(
            font: bebasNeueFont,
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
    );
  }
}