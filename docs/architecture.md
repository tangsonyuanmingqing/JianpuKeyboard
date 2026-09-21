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

编辑输入时不自动执行上述链路。剪贴板复制属于 Presentation，不进入 Core。

## 模块

### Core（纯 Dart）

- `models`：Score / ScoreLine / Note / Rest / Hold / MeasureBar / Lyric。V1 不引入 Measure
- `parser`：词法拆分 + 语法分类。禁止用整段 replace 冒充解析
- `lyrics`：全局顺序对齐。不按行重置
- `validation`：歌词不足、歌词过多等警告
- `mapping`：音区到键盘字母
- `renderer`：结构化数据 → 纯文本
- `converter`：串联上述步骤

Core 不得依赖 Flutter Widget、BuildContext、剪贴板或任何操作系统 API。

### Presentation

- `features/converter`：输入、手动转换按钮、复制、清空、错误/警告展示
- 状态管理使用 Riverpod
- 编辑输入不得自动触发完整转换

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

歌词不足或歌词过多都返回 `ValidationMessage` 警告，不阻止输出。多余歌词不得静默丢弃，必须保留在转换结果中。未提供歌词（空或只有空白）不进行歌词数量校验，也不产生 Warning。
