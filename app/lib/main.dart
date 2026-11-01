import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_language.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await AppLanguageController.instance.load();
  runApp(const DropleApp());
}

class DropleApp extends StatelessWidget {
  const DropleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageController.instance;
    return ListenableBuilder(
      listenable: language,
      builder: (context, _) {
        return MaterialApp(
          title: 'Drople',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          locale: Locale(language.language.code),
          supportedLocales: const [Locale('id'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeShell(),
        );
      },
    );
  }
}
