import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin, injectable wrapper around the specific Supabase Auth calls
/// Vilvia's UI needs (sign up, sign in, sign out, auth-state/session
/// access). Exists purely for testability -- the real instance just
/// forwards to [Supabase.instance.client.auth]; widget tests inject a
/// fake instead of touching the real SDK or network.
class AuthService {
  AuthService({GoTrueClient? client}) : _providedClient = client;

  final GoTrueClient? _providedClient;

  // Resolved lazily (not in the constructor) so a test fake that extends
  // AuthService and overrides every member below never touches
  // Supabase.instance -- which would throw if Supabase.initialize()
  // hasn't run, as it never does in a widget test.
  GoTrueClient get _client => _providedClient ?? Supabase.instance.client.auth;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.signUp(email: email, password: password);
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.signOut();

  Stream<AuthState> get onAuthStateChange => _client.onAuthStateChange;

  Session? get currentSession => _client.currentSession;
}
