import 'package:flutter/material.dart';

import '../features/converter/converter_page.dart';
import 'theme/app_theme.dart';

class JianpuKeyboardApp extends StatelessWidget {
  const JianpuKeyboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '数字简谱键盘字母转换器',
      theme: AppTheme.light(),
      home: const ConverterPage(),
    );
  }
}
