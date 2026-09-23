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

曲谱库和当前临时草稿均使用本机 `SharedPreferences` 保存。曲谱库 v2 同时保存智能表格和规范文本表示，并兼容读取 v1。备份导入在完整校验文件结构后才写入本机存储，避免损坏的备份造成部分更新。

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
