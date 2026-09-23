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

V1.4.0。

## 当前功能

- 数字简谱文字输入
- 智能表格输入：按行列坐标逐格填写谱、歌词、单词或符号
- 谱行与歌词行分组、整组移动、行列插入删除和批量表格粘贴
- 单元格级插入删除：本行左右移动、本列同类型行或全部行上下移动
- 纯文本预览按谱词格子的显示宽度对齐，复制与图片导出使用相同结果
- 文本输入与智能表格互相预览转换；旧草稿继续使用原来的文本模式
- 数字简谱解析（中音 / 低音 / 高音）
- 休止符、延音符、小节线
- 歌词与音符全局顺序对齐
- 歌词延续标记 `-`（一字多音需显式写出）
- 数字简谱 → 键盘字母
- 文字输出
- 点击「转换」后执行完整转换
- 一键复制
- 内置示例与格式说明
- 自动保存并恢复输入草稿
- 本地曲谱库：保存歌曲名、歌手、标签、备注、数字简谱和歌词
- 保存有效转换后的字母简谱、键位快照与转换提示
- 曲谱库搜索、标签筛选、排序、一键填入、删除撤销
- 曲谱库 JSON 单曲/全库导入导出
- 已保存的字母简谱可复制、导出 PNG，并可应用保存时的键位
- 导出干净的 PNG 字母简谱图片
- 导出带行列坐标、分组和问题标记的检查图
- Windows x64 安装包与便携版发行

编辑数字简谱、歌词或键位后，上一轮结果会被清空；点击「转换」才会显示按当前输入和键位生成的新结果。曲谱库会保留上次成功保存的结果；源谱改动后尚未重新转换时，曲谱库会标记为“转换结果待更新”。

新建空白草稿默认使用智能表格。每个格子填写一个数字简谱 token、一个汉字、一个单词、一个字母或一个符号；空格子会保留对齐位置。选中单个格子后，可通过顶部「单元格操作」、右键或长按执行局部位移。表格仍可切换到文本输入，详细操作见 [docs/smart-grid.md](docs/smart-grid.md)。

键位页面可编辑低音、中音、高音各 7 个字母。合法键位会保存在本机并在重启后恢复；非法草稿不会覆盖上一次保存的配置。修改键位仍需点击「转换」才会生成新结果。

V1 不包含：图片识谱、OCR/OMR、MIDI、自动按键、云端、登录、数据库。

## 输入格式

标准格式：

```text
[谱]
3 3 3 4 5 | 3 2 2 -
1 1 1 2 3 | 3 7 7 -

[词]
黑 黑 的 天 空 | 低 垂 -
亮 亮 的 繁 星 | 相 随 -
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

Windows 本地持久化验收按顺序执行以下三个独立应用进程。测试使用专用存储键，不改动日常使用的键位配置：

```bash
flutter test -d windows integration_test/mapping_persistence_write_test.dart
flutter test -d windows integration_test/mapping_persistence_restart_test.dart
flutter test -d windows integration_test/mapping_persistence_reset_restart_test.dart
```

## 文档

- [需求](docs/requirements.md)
- [输入格式](docs/input-format.md)
- [智能表格](docs/smart-grid.md)
- [架构](docs/architecture.md)
- [曲谱库与备份](docs/song-library.md)
- [路线图](docs/roadmap.md)
- [V1.2 交付说明](docs/v1.2-spec.md)
