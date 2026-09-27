# 架构

## 原则

- 解析与执行分离
- 输入与输出分离
- Core 与 UI 分离
- Core 与平台 API 分离

V1 数据流：

```text
Input
  → 点击「转换」
  → Parser
  → Unified Music Model
  → Lyric Alignment
  → Validate
  → Mapping
  → Renderer
  → Output
```

智能表格使用另一条入口：`SmartGridDocument → SmartGridConverter → ConversionResult`。格子已经包含行类型和稳定坐标，因此转换时直接生成对齐输出，不先拼成文本再交给旧解析器。文本模式继续使用原有 Parser 链路。

编辑输入时不自动执行上述链路。剪贴板复制属于 Presentation，不进入 Core。

## 模块

### Core（纯 Dart）

- `models`：Score / ScoreLine / Note / Rest / Hold / MeasureBar / Lyric。V1 不引入 Measure
- `parser`：词法拆分 + 语法分类。禁止用整段 replace 冒充解析
- `lyrics`：全局顺序对齐。不按行重置。普通音节默认 1:1；合法歌词 `-` 为 continuation；无最近音节的 `-` 不消费 Note
- `validation`：按 `lyricSlots = syllableCount + validContinuationCount` 检查歌词不足、歌词过多；无效前导 `-` 给出忽略 Warning
- `mapping`：音区到键盘字母
- `renderer`：结构化数据 → 纯文本
- `converter`：串联上述步骤

Core 不得依赖 Flutter Widget、BuildContext、剪贴板或任何操作系统 API。

### Presentation

- `features/converter`：文本输入、智能表格、手动转换按钮、复制、图片导出、清空、错误/警告展示。智能表格模型保存行类型、分组、单元格和视图恢复信息，并在模型层执行可撤销的单元格级位移
- `features/library`：曲谱记录、曲谱库页面、JSON 备份与恢复。曲谱记录保存源输入、元数据和可选的结果快照；结果快照包含字母简谱、键位映射、提示和保存时间
- 状态管理使用 Riverpod
- 编辑输入不得自动触发完整转换

智能表格的编辑时语法校验集中在纯 Dart 模块 `smart_grid_validation.dart`，编解码、转换与页面共享格子规则；页面只消费问题坐标，不定义另一套规则。编辑器按坐标索引问题，并将重型编辑控件限制到视口行列；完整转换与歌词对齐仍属于手动转换链路。

`SmartGridIssueOverlay` 按行绘制非交互错误／警告字形，避免每个错误格各建一棵图标布局树；格子继续负责边框、提示、输入、焦点和选择。图标字体仍由 `AppTypography` 集中定义，绘制模块不持有文档状态或控制器。

`TableScrollLink` 负责正文／冻结列双向同步、范围裁剪及监听生命周期，编辑表格和输出表格复用；控制器所有权留在各自 Widget。`persistence_state_notifiers.dart` 共享存储健康／写入状态的转换，不共享域状态：草稿与曲谱库的 Provider、初始值、Repository 和事务仍独立。面板布局存储通过 Provider 注入，测试可以使用隔离配置，不触碰个人偏好。

`TableScrollFrame` 只接收表格持有的横向控制器、正文纵向控制器、列标题高度和内容，统一输入／输出／曲谱库预览的轨道。内容与两条轨道采用 sibling 布局，底部／右侧固定预留 24 像素，右下角让给 `ResizablePanel` 的调整把手；轨道与实际视口长度一致，不依靠负边距补偿。模块按 `Scrollable` 的 `ScrollPosition` 身份转发滚动和尺寸通知，排除格内编辑器和冻结列；转发通知不向页面泄漏。绘制、命中、滑块拖动、轨道翻页和取消均交给 Flutter `RawScrollbar`。`TextFieldTapRegion` 将轨道计入表格内部交互，保留焦点和组词；仅在表内关闭桌面自动滚动条，不改变页面或全局滚动行为。旧 `HoverTableScrollbars` 的热区、隐藏计时器与指针补偿已移除。冻结列同步、可见列渲染、编辑器身份和视图恢复仍由原模块负责。

曲谱库和当前草稿通过 Repository 使用应用支持目录中的版本化 JSON 文件保存。写入在同目录串行执行，并使用临时文件刷盘后替换正式文件。首次运行 v1.6.0 时，只在新文件不存在时读取旧 `SharedPreferences`；迁移成功后保留旧值作为回退副本。

恢复快照使用独立 JSON 文件，单个损坏快照不影响其他快照。曲谱库和草稿分别保留最近 20 份。主数据损坏时禁止覆盖，界面必须先导出原始数据，再允许重置。

曲谱库 v2 数据继续同时保存智能表格和规范文本表示，并兼容读取 v1。备份导入在完整校验文件结构后才进入事务写入。

### 尚未实现

以下目录与能力留到后续版本，V1 不预建空壳：

- 图片导入 / OCR / OMR
- Playback / Timeline
- Platform Executor（键盘、鼠标、脚本）

## 错误处理

非法音符返回 `ParseFailure`，包含：

- `line`：行号
- `column`：真实 1-based 字符列号
- `tokenIndex`：该行 token 顺序
- 原始 token
- 错误原因

`column` 不得复用为元素序号。

歌词不足或歌词过多都返回 `ValidationMessage` 警告，不阻止输出。多余音节或合法 continuation 不得静默丢弃，必须保留在转换结果中。完全没有歌词音节、也没有合法 continuation 时，不进行数量校验。已提供歌词时按 `lyricSlots = syllableCount + validContinuationCount` 与可消费 Note 数比较。没有最近音节的歌词 `-` 不占槽位，不进入 `unmatchedLyrics`，但必须 Warning。
