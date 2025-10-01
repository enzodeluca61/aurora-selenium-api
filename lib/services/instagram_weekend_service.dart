import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
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

class InstagramWeekendService {
  static const double pageWidth = 21.0; // cm
  static const double pageHeight = 29.7; // cm A4
  static const double margin = 1.0; // cm
  static const double dayHeaderHeight = 1.5; // cm
  static const double matchRowHeight = 1.8; // cm (aumentato di 1.5x)

  // Cache per i loghi delle squadre
  static final Map<String, pw.MemoryImage?> _logoCache = {};

  /// Genera un PDF con i risultati del weekend per Instagram
  static Future<Uint8List> generateWeekendResultsPdf({
    required List<Match> matches,
    required DateTime startDate,
    required DateTime endDate,
    List<Team>? teams,
  }) async {
    final pdf = pw.Document();

    // Carica il font BebasNeue
    final bebasNeueFontData = await rootBundle.load('assets/fonts/BebasNeue Bold.ttf');
    final bebasNeueFont = pw.Font.ttf(bebasNeueFontData);

    // Carica le immagini per il weekend Instagram
    final backgroundImageAgo = await _loadAssetImage('assets/images/Instagram_wm_ago.jpg');
    final backgroundImageAdb = await _loadAssetImage('assets/images/Instagram_wm_adb.jpg');
    final dayChangeImage = await _loadAssetImage('assets/images/cambiogiorno_ridotto.png');
    final rowBackgroundImage = await _loadAssetImage('assets/images/fondo_riga_wm2.png');
    final auroraLogo = await _loadAssetImage('assets/images/aurora_logo.png');

    // Ottieni le partite del weekend in ordine cronologico
    final weekendMatches = _getWeekendMatchesInOrder(matches, startDate, endDate, teams);

    // Separa le partite in agonistiche e attività di base
    final agonistiche = <Match>[];
    final attivitaDiBase = <Match>[];

    for (final match in weekendMatches) {
      if (_isAgoristicTeam(match.auroraTeam)) {
        agonistiche.add(match);
      } else {
        attivitaDiBase.add(match);
      }
    }

    // Precarica i loghi per tutte le partite
    final Map<String, pw.MemoryImage?> teamLogos = {};
    final Set<String> uniqueTeams = {};

    // Raccogli tutti i nomi delle squadre uniche dalle partite
    for (final match in weekendMatches) {
      final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
      final awayTeam = !match.isHome ? 'AURORA SERIATE' : match.opponent;
      uniqueTeams.add(homeTeam);
      uniqueTeams.add(awayTeam);
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

    // Prima pagina: Agonistiche
    if (agonistiche.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                image: pw.DecorationImage(
                  image: backgroundImageAgo,
                  fit: pw.BoxFit.cover,
                ),
              ),
              child: pw.Column(
                children: [
                  pw.SizedBox(height: 400), // Spazio dall'alto in pixel
                  // Partite agonistiche del weekend raggruppate per giorno
                  _buildWeekendMatchesByDay(
                    agonistiche,
                    rowBackgroundImage,
                    auroraLogo,
                    bebasNeueFont,
                    teamLogos,
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    // Seconda pagina: Attività di Base
    if (attivitaDiBase.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                image: pw.DecorationImage(
                  image: backgroundImageAdb,
                  fit: pw.BoxFit.cover,
                ),
              ),
              child: pw.Column(
                children: [
                  pw.SizedBox(height: 400), // Spazio dall'alto in pixel
                  // Partite attività di base del weekend raggruppate per giorno
                  _buildWeekendMatchesByDay(
                    attivitaDiBase,
                    rowBackgroundImage,
                    auroraLogo,
                    bebasNeueFont,
                    teamLogos,
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Genera immagini JPG separate per Instagram (Agonistiche e Attività di Base)
  static Future<List<Uint8List>> generateWeekendResultsJpgs({
    required List<Match> matches,
    required DateTime startDate,
    required DateTime endDate,
    List<Team>? teams,
  }) async {
    final images = <Uint8List>[];

    // Carica le risorse necessarie
    final bebasNeueFontData = await rootBundle.load('assets/fonts/BebasNeue Bold.ttf');
    final bebasNeueFont = pw.Font.ttf(bebasNeueFontData);
    final backgroundImageAgo = await _loadAssetImage('assets/images/Instagram_wm_ago.jpg');
    final backgroundImageAdb = await _loadAssetImage('assets/images/Instagram_wm_adb.jpg');
    final rowBackgroundImage = await _loadAssetImage('assets/images/fondo_riga_wm2.png');
    final auroraLogo = await _loadAssetImage('assets/images/aurora_logo.png');

    // Ottieni le partite del weekend in ordine cronologico
    final weekendMatches = _getWeekendMatchesInOrder(matches, startDate, endDate, teams);

    // Separa le partite in agonistiche e attività di base
    final agonistiche = <Match>[];
    final attivitaDiBase = <Match>[];

    for (final match in weekendMatches) {
      if (_isAgoristicTeam(match.auroraTeam)) {
        agonistiche.add(match);
      } else {
        attivitaDiBase.add(match);
      }
    }

    // Precarica i loghi per tutte le partite
    final Map<String, pw.MemoryImage?> teamLogos = {};
    final Set<String> uniqueTeams = {};
    for (final match in weekendMatches) {
      final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
      final awayTeam = !match.isHome ? 'AURORA SERIATE' : match.opponent;
      uniqueTeams.add(homeTeam);
      uniqueTeams.add(awayTeam);
    }

    try {
      final futures = uniqueTeams.map((teamName) => _loadTeamLogo(teamName)).toList();
      final results = await Future.wait(futures, eagerError: false).timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.filled(uniqueTeams.length, null),
      );
      int index = 0;
      for (final teamName in uniqueTeams) {
        final cleanTeamName = _cleanTeamNameForLogo(teamName);
        teamLogos[cleanTeamName] = results[index];
        index++;
      }
    } catch (e) {
      debugPrint('Timeout o errore nel caricamento loghi: $e');
    }

    // Genera immagine per Agonistiche (se ci sono partite)
    if (agonistiche.isNotEmpty) {
      final pdfAgo = pw.Document();
      pdfAgo.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                image: pw.DecorationImage(
                  image: backgroundImageAgo,
                  fit: pw.BoxFit.cover,
                ),
              ),
              child: pw.Column(
                children: [
                  pw.SizedBox(height: 400), // Spazio dall'alto in pixel
                  // Partite agonistiche del weekend raggruppate per giorno
                  _buildWeekendMatchesByDay(
                    agonistiche,
                    rowBackgroundImage,
                    auroraLogo,
                    bebasNeueFont,
                    teamLogos,
                  ),
                ],
              ),
            );
          },
        ),
      );

      final pdfBytesAgo = await pdfAgo.save();
      await for (final page in Printing.raster(pdfBytesAgo, dpi: 180)) {
        images.add(await page.toPng());
        break; // Solo la prima (unica) pagina
      }
    }

    // Genera immagine per Attività di Base (se ci sono partite)
    if (attivitaDiBase.isNotEmpty) {
      final pdfAdb = pw.Document();
      pdfAdb.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                image: pw.DecorationImage(
                  image: backgroundImageAdb,
                  fit: pw.BoxFit.cover,
                ),
              ),
              child: pw.Column(
                children: [
                  pw.SizedBox(height: 400), // Spazio dall'alto in pixel
                  // Partite attività di base del weekend raggruppate per giorno
                  _buildWeekendMatchesByDay(
                    attivitaDiBase,
                    rowBackgroundImage,
                    auroraLogo,
                    bebasNeueFont,
                    teamLogos,
                  ),
                ],
              ),
            );
          },
        ),
      );

      final pdfBytesAdb = await pdfAdb.save();
      await for (final page in Printing.raster(pdfBytesAdb, dpi: 180)) {
        images.add(await page.toPng());
        break; // Solo la prima (unica) pagina
      }
    }

    if (images.isEmpty) {
      throw Exception('Nessuna partita del weekend trovata per generare immagini');
    }

    return images;
  }

  /// Mantiene il metodo originale per compatibilità (restituisce la prima immagine)
  static Future<Uint8List> generateWeekendResultsJpg({
    required List<Match> matches,
    required DateTime startDate,
    required DateTime endDate,
    List<Team>? teams,
  }) async {
    final images = await generateWeekendResultsJpgs(
      matches: matches,
      startDate: startDate,
      endDate: endDate,
      teams: teams,
    );
    return images.first;
  }

  /// Carica un'immagine dagli assets
  static Future<pw.ImageProvider> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }

  /// Ottiene la lista di partite del weekend in ordine cronologico
  static List<Match> _getWeekendMatchesInOrder(
    List<Match> matches,
    DateTime startDate,
    DateTime endDate,
    List<Team>? teams,
  ) {
    // Filtra le partite del weekend flaggate per il planning
    debugPrint('=== FILTRAGGIO PARTITE WEEKEND ===');
    debugPrint('Range date: ${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}');
    debugPrint('Partite totali da controllare: ${matches.length}');

    final weekendMatches = <Match>[];
    for (final match in matches) {
      final isWeekend = match.date.weekday == 6 || match.date.weekday == 7; // Sabato o domenica

      // Confronta solo le date senza orario
      final matchDateOnly = DateTime(match.date.year, match.date.month, match.date.day);
      final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);

      final isInDateRange = matchDateOnly.isAtSameMomentAs(startDateOnly) ||
          matchDateOnly.isAtSameMomentAs(endDateOnly) ||
          (matchDateOnly.isAfter(startDateOnly) && matchDateOnly.isBefore(endDateOnly));

      debugPrint('Analizzando: ${match.auroraTeam} vs ${match.opponent}');
      debugPrint('  Data: ${DateFormat('dd/MM/yyyy').format(match.date)} (weekday: ${match.date.weekday})');
      debugPrint('  Weekend: $isWeekend, InRange: $isInDateRange, Planning: ${match.includeInPlanning}');

      // Include tutte le partite del weekend nel range di date
      // (per ora ignoriamo il flag includeInPlanning per il debug)
      if (isWeekend && isInDateRange) {
        weekendMatches.add(match);
        debugPrint('  ✓ AGGIUNTA alla lista weekend');
      } else if (!isWeekend) {
        debugPrint('  ✗ ESCLUSA: non è weekend');
      } else if (!isInDateRange) {
        debugPrint('  ✗ ESCLUSA: fuori dal range di date');
      } else {
        debugPrint('  ✗ ESCLUSA: motivo sconosciuto');
      }
    }

    // Ordina le partite per data e ora
    weekendMatches.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;

      // Se stesso giorno, ordina per ora
      return a.time.compareTo(b.time);
    });

    debugPrint('Partite weekend trovate: ${weekendMatches.length}');
    for (final match in weekendMatches) {
      debugPrint('- ${match.auroraTeam} vs ${match.opponent} il ${DateFormat('dd/MM/yyyy').format(match.date)} alle ${match.time}');
    }

    return weekendMatches;
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
                fontSize: 23,
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
              pw.SizedBox(height: 6), // Spazio tra le righe
            ],
          )).toList(),
        ),
        pw.SizedBox(height: PdfPageFormat.cm * 0.5), // Spazio tra giorni
      ],
    );
  }

  /// Costruisce una riga per una singola partita del weekend
  static pw.Widget _buildWeekendMatchRow(
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
    final String goalCasa = auroraInCasa
        ? (match.goalsAurora?.toString() ?? '')
        : (match.goalsOpponent?.toString() ?? '');
    final String goalFuori = auroraInCasa
        ? (match.goalsOpponent?.toString() ?? '')
        : (match.goalsAurora?.toString() ?? '');

    // Formatta data e ora
    final dayString = DateFormat('dd.MM').format(match.date);

    // Formatta l'orario come hh:mm (rimuove secondi se presenti)
    String timeString = match.time;
    if (timeString.contains(':') && timeString.split(':').length > 2) {
      // Se ha formato hh:mm:ss, mantieni solo hh:mm
      final timeParts = timeString.split(':');
      timeString = '${timeParts[0]}:${timeParts[1]}';
    }

    return pw.Transform(
      transform: vector_math.Matrix4.diagonal3Values(10/9, 1.0, 1.0), // Stretch orizzontale di 1/9
      child: pw.Container(
        width: double.infinity,
        height: PdfPageFormat.cm * matchRowHeight,
        decoration: pw.BoxDecoration(
          image: pw.DecorationImage(
            image: rowBackgroundImage,
            fit: pw.BoxFit.cover,
          ),
        ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8.0, 6.0, 8.0, 2.0),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Squadra casa (sinistra) - solo nome
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerRight,
                child: auroraInCasa ? pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      squadraCasa,
                      style: pw.TextStyle(
                        font: bebasNeueFont,
                        fontSize: 36,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                      textAlign: pw.TextAlign.right,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                ) : pw.Text(
                  squadraCasa,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: 34,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.right,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            // Logo casa al centro
            pw.Container(
              width: 70,
              height: 70,
              decoration: const pw.BoxDecoration(),
              child: pw.Center(
                child: auroraInCasa
                    ? pw.Image(auroraLogo, width: 56, height: 56, fit: pw.BoxFit.contain)
                    : _buildTeamLogo(squadraCasa, teamLogos, bebasNeueFont, 56),
              ),
            ),
            pw.SizedBox(width: 16),
            // Centro: Solo orario
            pw.Container(
              width: 80,
              alignment: pw.Alignment.center,
              child: pw.Text(
                timeString,
                style: pw.TextStyle(
                  font: bebasNeueFont,
                  fontSize: 38,
                  fontWeight: pw.FontWeight.normal,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            // Logo fuori casa al centro
            pw.Container(
              width: 70,
              height: 70,
              decoration: const pw.BoxDecoration(),
              child: pw.Center(
                child: !auroraInCasa
                    ? pw.Image(auroraLogo, width: 56, height: 56, fit: pw.BoxFit.contain)
                    : _buildTeamLogo(squadraFuori, teamLogos, bebasNeueFont, 56),
              ),
            ),
            pw.SizedBox(width: 16),
            // Squadra fuori casa (destra) - solo nome
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerLeft,
                child: !auroraInCasa ? pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Text(
                      squadraFuori,
                      style: pw.TextStyle(
                        font: bebasNeueFont,
                        fontSize: 36,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                      textAlign: pw.TextAlign.left,
                      overflow: pw.TextOverflow.clip,
                    ),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ],
                ) : pw.Text(
                  squadraFuori,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: 34,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.left,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Costruisce una riga per una singola partita (versione originale non utilizzata)
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

    return pw.Transform(
      transform: vector_math.Matrix4.diagonal3Values(10/9, 1.0, 1.0), // Stretch orizzontale di 1/9
      child: pw.Container(
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
                color: PdfColor.fromHex('#F5F5DC'),
                border: pw.Border.all(color: PdfColors.white, width: 2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: auroraInCasa
                    ? pw.Image(auroraLogo, width: 30, height: 30)
                    : _buildTeamLogo(squadraCasa, teamLogos, bebasNeueFont, 30),
              ),
            ),
            pw.SizedBox(width: 16),
            // Colonna 2: Nome squadra casa
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  squadraCasa,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: auroraInCasa ? 42 : 40,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.right,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
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
            pw.SizedBox(width: 16),
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
            pw.SizedBox(width: 16),
            // Colonna 5: Nome squadra fuori casa
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  squadraFuori,
                  style: pw.TextStyle(
                    font: bebasNeueFont,
                    fontSize: !auroraInCasa ? 42 : 40,
                    fontWeight: pw.FontWeight.bold,
                    color: !auroraInCasa ? PdfColor.fromHex('#FFD700') : PdfColors.white,
                  ),
                  textAlign: pw.TextAlign.left,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            // Colonna 6: Logo squadra fuori casa
            pw.Container(
              width: 40,
              height: 50,
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5DC'),
                border: pw.Border.all(color: PdfColors.white, width: 2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: !auroraInCasa
                    ? pw.Image(auroraLogo, width: 30, height: 30)
                    : _buildTeamLogo(squadraFuori, teamLogos, bebasNeueFont, 30),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Mostra l'anteprima dell'immagine JPG weekend
  static Future<void> showWeekendImagePreview(
    BuildContext context,
    Uint8List imageBytes,
    List<Match> matches,
    DateTime startDate,
    DateTime endDate,
    List<Team>? teams,
  ) async {
    // Formatta le date per il nome del file
    final startDateStr = DateFormat('dd.MM').format(startDate);
    final endDateStr = DateFormat('dd.MM').format(endDate);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text(
              'Anteprima Week Match',
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
                    final fileName = 'Weekend Match $startDateStr-$endDateStr.png';
                    final file = File('${directory.path}/$fileName');
                    await file.writeAsBytes(imageBytes);

                    // Condividi il file
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      text: 'Weekend Match Aurora Seriate 1967',
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
      // Fallback al logo testuale se non c'è l'immagine
      return _buildOpponentLogoWithSize(teamName, bebasNeueFont, size);
    }
  }


  /// Costruisce un logo testuale per squadra avversaria con dimensione personalizzata
  static pw.Widget _buildOpponentLogoWithSize(String teamName, pw.Font bebasNeueFont, double size) {
    // Mappa delle squadre comuni con i loro colori rappresentativi (più vividi)
    final Map<String, Map<String, dynamic>> teamData = {
      'ATALANTA': {'color': PdfColor.fromHex('#0066FF'), 'text': 'A'}, // Blu vivido
      'INTER': {'color': PdfColor.fromHex('#004CFF'), 'text': 'I'}, // Blu scuro vivido
      'MILAN': {'color': PdfColor.fromHex('#FF0000'), 'text': 'M'}, // Rosso vivido
      'JUVENTUS': {'color': PdfColors.black, 'text': 'J'},
      'BERGAMO': {'color': PdfColor.fromHex('#3399FF'), 'text': 'B'}, // Blu medio vivido
      'CREMONESE': {'color': PdfColor.fromHex('#CC0000'), 'text': 'C'}, // Rosso scuro vivido
      'BRESCIA': {'color': PdfColor.fromHex('#4488FF'), 'text': 'BR'}, // Blu chiaro vivido
      'LECCO': {'color': PdfColor.fromHex('#5599FF'), 'text': 'L'}, // Blu vivido
      'COMO': {'color': PdfColor.fromHex('#00CCCC'), 'text': 'CO'}, // Ciano vivido
      'ALBINOLEFFE': {'color': PdfColor.fromHex('#0066FF'), 'text': 'AL'}, // Blu vivido
      'VIRTUS': {'color': PdfColor.fromHex('#00AA00'), 'text': 'V'}, // Verde vivido
      'SERIATE': {'color': PdfColor.fromHex('#990000'), 'text': 'S'}, // Rosso scuro vivido
      'ROMANO': {'color': PdfColor.fromHex('#FF6600'), 'text': 'R'}, // Arancione vivido
      'VERDELLO': {'color': PdfColor.fromHex('#00CC00'), 'text': 'VE'}, // Verde chiaro vivido
      'VILLA': {'color': PdfColor.fromHex('#9933FF'), 'text': 'VI'}, // Viola vivido
      'CARAVAGGIO': {'color': PdfColor.fromHex('#8B4513'), 'text': 'CA'}, // Marrone vivido
      'TREVIGLIO': {'color': PdfColor.fromHex('#4B0082'), 'text': 'T'}, // Indaco vivido
    };

    // Cerca un pattern per la squadra
    PdfColor bgColor = PdfColor.fromHex('#FF0000'); // Rosso vivido di default
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
      bgColor = PdfColor.fromHex('#FF4500'); // Arancione vivido
    }

    // Calcola la dimensione del font in base alla dimensione del container
    final fontSize = size * 0.55;

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


  /// Costruisce le partite weekend raggruppate per giorno
  static pw.Widget _buildWeekendMatchesByDay(
    List<Match> weekendMatches,
    pw.ImageProvider rowBackgroundImage,
    pw.ImageProvider auroraLogo,
    pw.Font bebasNeueFont,
    Map<String, pw.MemoryImage?> teamLogos,
  ) {
    // Raggruppa le partite per giorno
    final Map<DateTime, List<Match>> matchesByDay = {};

    for (final match in weekendMatches) {
      final dateOnly = DateTime(match.date.year, match.date.month, match.date.day);
      if (!matchesByDay.containsKey(dateOnly)) {
        matchesByDay[dateOnly] = [];
      }
      matchesByDay[dateOnly]!.add(match);
    }

    // Ordina le date
    final sortedDates = matchesByDay.keys.toList()..sort();

    final List<pw.Widget> dayWidgets = [];

    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final matches = matchesByDay[date]!;

      // Se non è il primo giorno, aggiungi spazio
      if (i > 0) {
        dayWidgets.add(pw.SizedBox(height: 40));
      }

      // Aggiungi intestazione giorno
      dayWidgets.add(_buildDayHeader(date, bebasNeueFont));
      dayWidgets.add(pw.SizedBox(height: 20));

      // Aggiungi partite del giorno
      for (final match in matches) {
        dayWidgets.add(_buildWeekendMatchRow(
          match,
          rowBackgroundImage,
          auroraLogo,
          bebasNeueFont,
          teamLogos,
        ));
        dayWidgets.add(pw.SizedBox(height: 16));
      }
    }

    return pw.Column(children: dayWidgets);
  }

  /// Costruisce l'intestazione del giorno
  static pw.Widget _buildDayHeader(DateTime date, pw.Font bebasNeueFont) {
    final dayName = _getDayName(date);
    final dayString = '$dayName ${DateFormat('dd/MM/yyyy').format(date)}';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: pw.Text(
        dayString.toUpperCase(),
        style: pw.TextStyle(
          font: bebasNeueFont,
          fontSize: 48,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
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

  /// Ottiene il nome del mese in italiano
  static String _getMonthName(DateTime date) {
    switch (date.month) {
      case 1: return 'gennaio';
      case 2: return 'febbraio';
      case 3: return 'marzo';
      case 4: return 'aprile';
      case 5: return 'maggio';
      case 6: return 'giugno';
      case 7: return 'luglio';
      case 8: return 'agosto';
      case 9: return 'settembre';
      case 10: return 'ottobre';
      case 11: return 'novembre';
      case 12: return 'dicembre';
      default: return 'sconosciuto';
    }
  }

  /// Determina se una squadra è agonistica o attività di base
  static bool _isAgoristicTeam(String? auroraTeam) {
    if (auroraTeam == null || auroraTeam.isEmpty) return false;

    final team = auroraTeam.toUpperCase();

    // Squadre agonistiche (categorie senior e giovanili agonistiche)
    const agonistiche = [
      'PRIMA SQUADRA',
      'JUNIORES',
      'JUNIORES NAZIONALE',
      'JUNIORES REGIONALE',
      'ALLIEVI REGIONALI',
      'ALLIEVI ELITE',
      'PRIMA',
      'SECONDA',
      'TERZA',
      'SENIOR',
      'U21',
      'U19',
      'U18',
      'U17',
      'U16',
      'U15',
      'U14',
      'UNDER 21',
      'UNDER 19',
      'UNDER 18',
      'UNDER 17',
      'UNDER 16',
      'UNDER 15',
      'UNDER 14',
    ];

    // Escludi squadre di promozione
    if (team.contains('PROMOZIONE')) {
      return false;
    }

    // Controlla se la squadra è nelle categorie agonistiche
    for (final categoria in agonistiche) {
      if (team.contains(categoria)) {
        return true;
      }
    }

    // Tutte le altre sono considerate attività di base
    return false;
  }


  /// Combina più pagine verticalmente in un'unica immagine
  static Future<Uint8List> _combineImagesVertically(List<PdfRaster> images) async {
    if (images.isEmpty) throw Exception('Nessuna immagine da combinare');
    if (images.length == 1) return await images.first.toPng();

    // Converte le pagine in PNG
    final pngImages = <Uint8List>[];
    for (final image in images) {
      pngImages.add(await image.toPng());
    }

    // Usa Flutter UI per combinare le immagini
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    double totalHeight = 0;
    int maxWidth = 0;
    final decodedImages = <ui.Image>[];

    // Decodifica tutte le immagini e calcola dimensioni
    for (final pngBytes in pngImages) {
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      decodedImages.add(image);
      totalHeight += image.height;
      if (image.width > maxWidth) maxWidth = image.width;
    }

    // Disegna le immagini una sotto l'altra
    double currentY = 0;
    for (final image in decodedImages) {
      // Centra l'immagine orizzontalmente se più stretta del max width
      final x = (maxWidth - image.width) / 2;
      canvas.drawImage(image, Offset(x, currentY), Paint());
      currentY += image.height;
      image.dispose(); // Libera la memoria
    }

    // Converte il canvas in immagine
    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(maxWidth, totalHeight.toInt());
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

    // Cleanup
    picture.dispose();
    finalImage.dispose();

    if (byteData == null) {
      throw Exception('Errore nella creazione dell\'immagine combinata');
    }

    return byteData.buffer.asUint8List();
  }
}