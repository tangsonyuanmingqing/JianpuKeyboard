# Jianpu Keyboard

数字简谱键盘字母转换器。

把数字简谱解析成统一的音乐数据，再按键位映射输出可读的字母简谱，并保留歌词对应关系。

## 支持平台

- Windows
- macOS
- Android
- iOS

核心业务使用共享 Dart 代码；平台相关能力以后通过独立适配层接入。

## 当前版本

V1

## 当前功能

- 数字简谱文字输入
- 数字简谱解析（中音 / 低音 / 高音）
- 休止符、延音符、小节线
- 歌词与音符全局顺序对齐
- 数字简谱 → 键盘字母
- 文字输出
- 点击「转换」后执行完整转换
- 一键复制

V1 不包含：图片识谱、OCR/OMR、MIDI、自动按键、云端、登录、数据库。

## 输入格式

标准格式：

```text
[谱]
3 3 3 4 5 | 3 2 2 -
1 1 1 2 3 | 3 7 7 -

[词]
黑 黑 的 天 空 | 低 垂
亮 亮 的 繁 星 | 相 随
```

也允许只输入简谱，例如：

```text
3 4 5 6 7
```

详细规则见 [docs/input-format.md](docs/input-format.md)。

## 示例

输入：

```text
3 4 5
```

输出：

```text
D F G
```

输入：

```text
[谱]
3 4 5

[词]
我 爱 你
```

输出：

```text
D F G
我 爱 你
```

## 开发方式

1. 安装 Flutter SDK，并确保 `flutter` 在 PATH 中。
2. 在项目根目录生成平台脚手架（保留现有 `lib/`、`test/`、`docs/`）：

```bash
flutter create . --project-name jianpu_keyboard
```

3. 安装依赖并运行：

```bash
flutter pub get
flutter run
```

## 测试方式

```bash
flutter analyze
flutter test
```

核心测试不依赖具体操作系统 API。

## 文档

- [需求](docs/requirements.md)
- [输入格式](docs/input-format.md)
- [架构](docs/architecture.md)
- [路线图](docs/roadmap.md)
