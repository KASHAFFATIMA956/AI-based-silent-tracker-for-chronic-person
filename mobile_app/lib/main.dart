import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/root_router.dart';
import 'state/admin_data_provider.dart';
import 'state/auth_provider.dart';
import 'state/doctor_data_provider.dart';
import 'state/language_provider.dart';
import 'state/patient_data_provider.dart';
import 'state/theme_provider.dart';

void main() {
  runApp(const RozNoorApp());
}

class RozNoorApp extends StatelessWidget {
  const RozNoorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..restoreSession()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => PatientDataProvider()),
        ChangeNotifierProvider(create: (_) => DoctorDataProvider()),
        ChangeNotifierProvider(create: (_) => AdminDataProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'RozNoor',
            debugShowCheckedModeBanner: false,
            theme: buildRnLightTheme(),
            darkTheme: buildRnDarkTheme(),
            themeMode: themeProvider.mode,
            home: const RootRouter(),
          );
        },
      ),
    );
  }
}
