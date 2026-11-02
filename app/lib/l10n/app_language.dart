import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppLanguage {
  indonesian('id'),
  english('en');

  const AppLanguage(this.code);

  final String code;
}

class AppLanguageController extends ChangeNotifier {
  AppLanguageController._();

  static final AppLanguageController instance = AppLanguageController._();

  AppLanguage _language = AppLanguage.indonesian;

  AppLanguage get language => _language;

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final code = (await file.readAsString()).trim();
      _language = code == 'en' ? AppLanguage.english : AppLanguage.indonesian;
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (_language == value) return;
    _language = value;
    notifyListeners();
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(value.code, flush: true);
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}language.txt');
  }
}
