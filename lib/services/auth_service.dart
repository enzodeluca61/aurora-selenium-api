import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  User? _currentUser;
  String? _errorMessage;
  bool _isSuperAdmin = false;

  bool get isLoading => _isLoading;
  User? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isSuperAdmin => _isSuperAdmin;

  AuthService() {
    _init();
  }

  void _init() {
    _currentUser = _supabase.auth.currentUser;
    if (_currentUser != null) {
      _loadUserRole();
    }
    _supabase.auth.onAuthStateChange.listen((data) {
      _currentUser = data.session?.user;
      if (_currentUser != null) {
        _loadUserRole();
      } else {
        _isSuperAdmin = false;
      }
      notifyListeners();
    });
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== DEBUG LOGIN: Starting ===');
        debugPrint('Email: $email');
        debugPrint('Supabase client initialized: ${_supabase.runtimeType}');
      }

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (kDebugMode) {
        debugPrint('=== LOGIN RESPONSE ===');
        debugPrint('User: ${response.user?.id}');
        debugPrint('Email: ${response.user?.email}');
        debugPrint('Session: ${response.session?.accessToken != null ? "EXISTS" : "NULL"}');
        debugPrint('Current user after login: ${_supabase.auth.currentUser?.id}');
      }

      if (response.user != null && response.session != null) {
        _currentUser = response.user;
        if (kDebugMode) {
          debugPrint('✅ Login successful for: ${response.user!.email}');
        }
        return true;
      } else {
        _setError('Credenziali non valide o account non verificato');
        return false;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Errore login: $error');
      }
      
      String errorMessage = 'Errore durante il login';
      
      if (error.toString().contains('Invalid login credentials')) {
        errorMessage = 'Email o password non corretti';
      } else if (error.toString().contains('Email not confirmed')) {
        errorMessage = 'Email non ancora verificata. Controlla la tua casella email';
      } else if (error.toString().contains('Too many requests')) {
        errorMessage = 'Troppi tentativi. Riprova tra qualche minuto';
      }
      
      _setError(errorMessage);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signUp(String email, String password, String fullName) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('Tentativo di registrazione per: $email');
      }

      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      if (kDebugMode) {
        debugPrint('SignUp Response user: ${response.user}');
        debugPrint('SignUp Response session: ${response.session}');
      }

      if (response.user != null) {
        _currentUser = response.user;
        
        if (response.session == null) {
          _setError('Registrazione completata! Verifica la tua email prima di accedere');
        }
        
        if (kDebugMode) {
          debugPrint('Registrazione successful for: ${response.user!.email}');
        }
        return true;
      }
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Errore registrazione: $error');
      }
      
      String errorMessage = 'Errore durante la registrazione';
      
      if (error.toString().contains('User already registered')) {
        errorMessage = 'Questa email è già registrata. Prova ad accedere';
      } else if (error.toString().contains('Password should be at least')) {
        errorMessage = 'La password deve essere di almeno 6 caratteri';
      } else if (error.toString().contains('Unable to validate email')) {
        errorMessage = 'Email non valida';
      }
      
      _setError(errorMessage);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _currentUser = null;
      notifyListeners();
    } catch (error) {
      _setError('Errore durante il logout: ${error.toString()}');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Demo login senza Supabase per test immediato
  Future<bool> demoLogin(String email) async {
    try {
      _setLoading(true);
      _clearError();

      // Simula un user demo per test locale
      await Future.delayed(const Duration(seconds: 1));
      
      // Crea un user fittizio per demo
      if (kDebugMode) {
        debugPrint('Demo login per: $email');
      }

      // Per demo, creiamo un user simulato
      _currentUser = User(
        id: 'demo-user-123',
        appMetadata: {},
        userMetadata: {'full_name': 'Demo Allenatore', 'email': email},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      if (kDebugMode) {
        debugPrint('Demo login successful!');
      }
      
      return true;
    } catch (error) {
      _setError('Errore demo login: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadUserRole() async {
    try {
      if (_currentUser == null) {
        if (kDebugMode) {
          debugPrint('_loadUserRole: currentUser is null');
        }
        return;
      }
      
      if (kDebugMode) {
        debugPrint('=== LOADING USER ROLE ===');
        debugPrint('User ID: ${_currentUser!.id}');
        debugPrint('User Email: ${_currentUser!.email}');
        debugPrint('User Metadata: ${_currentUser!.userMetadata}');
        debugPrint('App Metadata: ${_currentUser!.appMetadata}');
      }
      
      // Prova diversi modi per caricare il ruolo
      bool isAdmin = false;
      
      // 1. Controlla user metadata
      if (_currentUser!.userMetadata?['is_super_admin'] != null) {
        isAdmin = _currentUser!.userMetadata!['is_super_admin'] as bool? ?? false;
        if (kDebugMode) {
          debugPrint('Found is_super_admin in userMetadata: $isAdmin');
        }
      }
      
      // 2. Controlla app metadata  
      if (!isAdmin && _currentUser!.appMetadata['is_super_admin'] != null) {
        isAdmin = _currentUser!.appMetadata['is_super_admin'] as bool? ?? false;
        if (kDebugMode) {
          debugPrint('Found is_super_admin in appMetadata: $isAdmin');
        }
      }
      
      // 3. Per test: se l'email è specifica, forza admin
      if (!isAdmin && _currentUser!.email != null) {
        final testEmails = ['admin@test.com', 'vincenzo@test.com']; // Aggiungi qui le tue email di test
        if (testEmails.contains(_currentUser!.email!.toLowerCase())) {
          isAdmin = true;
          if (kDebugMode) {
            debugPrint('Forced admin for test email: ${_currentUser!.email}');
          }
        }
      }
      
      // 4. Prova a caricare da tabella profiles
      if (!isAdmin) {
        try {
          final response = await _supabase
              .from('profiles')
              .select('is_super_admin')
              .eq('id', _currentUser!.id)
              .maybeSingle();
          
          if (response != null) {
            isAdmin = response['is_super_admin'] as bool? ?? false;
            if (kDebugMode) {
              debugPrint('Found is_super_admin in profiles table: $isAdmin');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Errore caricamento ruolo da profiles: $e');
          }
        }
      }
      
      _isSuperAdmin = isAdmin;
      
      if (kDebugMode) {
        debugPrint('=== FINAL RESULT ===');
        debugPrint('is_super_admin = $_isSuperAdmin');
        debugPrint('========================');
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Errore nel caricamento del ruolo utente: $e');
      }
    }
  }
}