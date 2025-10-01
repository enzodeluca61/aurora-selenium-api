import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/match_service.dart';
import 'services/team_service.dart';
import 'services/training_service.dart';
import 'services/field_service.dart';
import 'services/player_service.dart';
import 'services/convocation_service.dart';
import 'services/results_service.dart';
import 'services/live_match_monitor.dart';
import 'services/team_logo_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inizializza i dati di localizzazione per l'italiano
  await initializeDateFormatting('it_IT', null);
  
  // TODO: Sostituire con le tue credenziali Supabase
  await Supabase.initialize(
    url: 'https://hkhuabfxjlcidlodbiru.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhraHVhYmZ4amxjaWRsb2RiaXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYwNTM2MjAsImV4cCI6MjA3MTYyOTYyMH0.ywg26EFefan4H1sPySmrWS0ndh6gPjOyjfqCIUQ67Ws',
    debug: true,
  );

  runApp(const AuroraSeriate1967App());
}

class AuroraSeriate1967App extends StatelessWidget {
  const AuroraSeriate1967App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => MatchService()),
        ChangeNotifierProvider(create: (_) => TeamService()),
        ChangeNotifierProvider(create: (_) => TrainingService()),
        ChangeNotifierProvider(create: (_) => FieldService()),
        ChangeNotifierProvider(create: (_) => PlayerService()),
        ChangeNotifierProvider(create: (_) => ConvocationService()),
        ChangeNotifierProvider(create: (_) => ResultsService()),
        ChangeNotifierProvider(create: (_) => LiveMatchMonitor()),
        ChangeNotifierProvider(create: (_) => TeamLogoService()),
      ],
      child: MaterialApp(
        title: 'Aurora Seriate 1967 - Allenatori',
        locale: const Locale('it', 'IT'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('it', 'IT'),
        ],
        theme: ThemeData(
          primarySwatch: Colors.blue,
          primaryColor: const Color(0xFF1E3A8A),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        if (authService.isLoading) {
          return const SplashScreen();
        } else if (authService.currentUser != null) {
          return const DashboardScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
