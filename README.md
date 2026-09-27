# Jianpu Keyboard

数字简谱键盘字母转换器。

把数字简谱解析成统一的音乐数据，再按键位映射输出可读的字母简谱，并保留歌词对应关系。

## 支持平台

当前正式验证和本地发布目标为 Windows x64。核心业务使用共享 Dart 代码，其他平台尚未进入正式验收。

## 当前版本

V1.6.1。安装版、便携版与 SHA-256 校验文件见 [GitHub Release](https://github.com/tangsonyuanmingqing/JianpuKeyboard/releases/tag/v1.6.1)，更新内容与升级注意事项见 [v1.6.1 发布说明](docs/releases/v1.6.1.md)。

## 当前功能

- 数字简谱文字输入
- 智能表格输入：按行列坐标逐格填写谱、歌词、单词或符号
- 谱行与歌词行分组、整组移动、行列插入删除和批量表格粘贴
- 单元格级插入删除：本行左右移动、本列同类型行或全部行上下移动
- 纯文本预览按谱词格子的显示宽度对齐，复制与图片导出使用相同结果
- 输入和输出区域可从右下角拖动调整宽高，并在重启后保留个人布局
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
- 自动保存并恢复输入草稿与歌曲名
- 本地曲谱库：保存歌曲名、歌手、标签、备注、数字简谱和歌词
- 保存有效转换后的字母简谱、键位快照与转换提示
- 曲谱库搜索、标签筛选、排序、一键填入、删除撤销
- 曲谱库 JSON 单曲/全库导入导出
- 曲谱库与当前草稿使用版本化原子 JSON 存储，首次启动自动迁移旧数据
- 恢复中心：创建、预览、恢复、导出和删除曲谱库/草稿快照
- 草稿保存状态、失败重试与退出前写入刷新
- 已保存的字母简谱可复制、导出 PNG，并可应用保存时的键位
- 导出带歌曲名的干净 PNG 字母简谱图片；复制内容也会附带歌曲名
- 导出带行列坐标、分组和问题标记的检查图
- Windows x64 安装包与便携版发行
- Windows 单实例：重复启动会激活已有窗口
- Windows 窗口置顶
- 白色／深灰黑主题切换，内置中文字体与统一排版

编辑数字简谱、歌词或键位后，当前有效结果会失效；文本模式清空上一轮结果，智能表格模式保留旧预览、降低表格透明度并标记“结果待更新”。点击「转换」才会按当前输入和键位生成新结果。主页标题栏下方可填写歌曲名；歌曲名会随临时草稿恢复，保存时会直接作为曲谱库标题。曲谱库会保留上次成功保存的结果；源谱改动后尚未重新转换时，曲谱库会标记为“转换结果待更新”。

新建空白草稿默认使用智能表格。每个格子填写一个数字简谱 token、一个汉字、一个单词、一个字母或一个符号；空格子会保留对齐位置。选中单个格子后，可通过顶部「单元格操作」、右键或长按执行局部位移。工具栏中的「全局表格大小」会同步输入、输出和曲谱库预览表格，并在重启后恢复；可选择小 0%、中 50%、大 100%，或在 0%–100% 间微调。表格仍可切换到文本输入，详细操作见 [docs/smart-grid.md](docs/smart-grid.md)。

数字简谱、歌词、智能表格、字母简谱表格和纯文本预览都可通过右下角斜纹拖动角调整宽高。双击拖动角会恢复默认大小；表格在缩窄后保持单元格大小并可滚动，纯文本预览继续保持谱词对齐。尺寸作为本机界面偏好保存，不影响曲谱草稿或图片导出。

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

v1.6.1 的输入、输出和曲谱库表格预览统一为有溢出时常显的双轴滑块，底部／右侧各预留 24 逻辑像素，操作滑块保留编辑焦点和组词。操作说明见[表格滚动](docs/smart-grid.md#表格滚动)，复现与验收记录见[滚动条重构验证](docs/table-scroll-validation.md)。

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

应用排版使用内置 Noto Sans CJK SC 与 Noto Sans Mono CJK SC；界面和简谱文本的使用规则见[排版规范](docs/typography.md)。

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

100×100 智能表格的 Windows 真实界面性能验收：

```powershell
.\tools\run_windows_ui_performance.ps1 -Runs 3
```

运行前保存并关闭现有应用。测试使用 Profile 模式和临时数据目录，结果保存在 `build/performance/`；测量口径与复跑说明见 [Windows 真实界面性能验证](docs/windows-ui-performance.md)。

默认测量 `default-valid`（默认 360 高度面板、有效数据）。可用 `-Scenario default-errors`、`large-valid` 或 `large-errors` 分别复测密集错误和大面板；每个场景独立统计，不覆盖个人布局偏好。

## 文档

- [需求](docs/requirements.md)
- [输入格式](docs/input-format.md)
- [智能表格](docs/smart-grid.md)
- [架构](docs/architecture.md)
- [曲谱库与备份](docs/song-library.md)
- [排版规范](docs/typography.md)
- [路线图](docs/roadmap.md)
- [v1.6.1 发布说明](docs/releases/v1.6.1.md)
- [v1.6.0 历史发布说明](docs/releases/v1.6.0.md)
- [Windows 真实界面性能验证](docs/windows-ui-performance.md)
- [Windows 打包](installer/README.md)
- [V1.2 交付说明](docs/v1.2-spec.md)
