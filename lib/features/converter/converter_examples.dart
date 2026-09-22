import 'converter_input.dart';

class ConverterExample {
  final String title;
  final String description;
  final ConverterInput input;

  const ConverterExample({
    required this.title,
    required this.description,
    required this.input,
  });

  String get standardDocument =>
      '[谱]\n${input.scoreText}\n\n[词]\n${input.lyricsText}';
}

const converterExamples = [
  ConverterExample(
    title: '基础语法示例',
    description: '包含高低音、休止、延音、小节线与歌词延续。',
    input: ConverterInput(
      scoreText: "1, 2, 3 0 4 | 5 6' 7' -",
      lyricsText: '微 风 来 | 到 身 边 -',
    ),
  ),
  ConverterExample(
    title: '完整原创片段',
    description: '两行原创旋律，展示跨行歌词对齐。',
    input: ConverterInput(
      scoreText: '3 3 4 5 | 5 4 3 -\n2 2 3 4 | 3 2 1 -',
      lyricsText: '晨 光 落 在 | 窗 前 -\n轻 声 唱 起 | 新 的 歌 -',
    ),
  ),
  ConverterExample(
    title: '交替谱词示例',
    description: '重复 [谱] / [词]，用 // 分句、; 分行。',
    input: ConverterInput(
      scoreText: '[谱] 3 4 5; 5 4 3 // 1 2\n[词] 我爱你;你爱我 // 新歌\n[谱] 6 7\n[词] 好啊',
    ),
  ),
];
