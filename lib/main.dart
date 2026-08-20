import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/app/app.dart';
import 'package:vilvia/core/constants/supabase_constants.dart';
import 'package:vilvia/core/storage/secure_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      // Same key-derivation formula supabase_flutter itself uses for its
      // default SharedPreferencesLocalStorage (see its own
      // Supabase.initialize) -- needed here only to read/migrate any
      // pre-existing plaintext session; this storage is never written to
      // again once SecureLocalStorage takes over.
      localStorage: SecureLocalStorage(
        legacyPersistSessionKey:
            'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
      ),
    ),
  );
  runApp(const VilviaApp());
}
