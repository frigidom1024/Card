# RunningHub 批量快捷生图命令行工具设计

- 日期：2026-08-04
- 状态：待用户确认
- 范围：独立 Python CLI，不修改 Godot 游戏运行逻辑

## 目标

在 MonoCard 项目中提供一个可重复使用的 RunningHub 云端生图命令行工具。用户输入一批不同的提示词，并只输入一次统一的宽度和高度；工具并发提交这些任务，轮询任务状态，并在结果链接有效期内自动下载到本地资源目录。

## 使用方式

API Key 仅从环境变量 `RUNNINGHUB_API_KEY` 读取，不写入源码、示例配置或 Git。

单批多提示词：

```powershell
$env:RUNNINGHUB_API_KEY = "<your-key>"
python tools/runninghub_generate.py `
  --workflow-id 2084605200131780610 `
  --prompt "ash-white rib bone knife, card art" `
  --prompt "weathered pilgrim lantern, card art" `
  --width 512 --height 512 `
  --concurrency 100
```

也支持从文本文件读取，每行一个提示词；空行和 `#` 开头的行忽略：

```powershell
python tools/runninghub_generate.py `
  --workflow-id 2084605200131780610 `
  --prompts-file prompts.txt `
  --width 512 --height 512
```

`--prompt` 与 `--prompts-file` 可以同时使用，工具按命令出现顺序合并提示词。

## 默认工作流映射

基于 RunningHub 文档中的 AI App 工作流参数：

- prompt：节点 `134` 的字段 `text`
- width：节点 `620` 的字段 `width`
- height：节点 `620` 的字段 `height`

所有映射都可通过参数覆盖，支持将任意额外的 `nodeId.fieldName=value` 添加到请求的 `nodeInfoList`，以适配后续卡牌、角色、场景等不同工作流。

## 处理流程

1. 校验 API Key、工作流 ID、至少一段提示词、宽高和并发数。
2. 为每段提示词构造独立的 RunningHub `/openapi/v2/run/ai-app/{workflow_id}` 请求。
3. 使用最多 `--concurrency` 个并发工作槽；并发值默认 8，最大 100。
4. 每个任务提交成功后，轮询 `/openapi/v2/query`，状态为 `QUEUED` 或 `RUNNING` 时按间隔等待。
5. 状态为 `SUCCESS` 时立即下载所有图片结果；RunningHub 结果 URL 有效期有限，因此不只打印 URL。
6. 单个任务失败时记录错误并继续处理其他提示词。
7. 最终输出成功/失败汇总，并返回非零退出码表示批次存在失败。

## 输出

默认目录为 `art/generated/`，可由 `--output-dir` 覆盖。文件名包含批次序号、任务 ID 和结果序号，例如：

```text
art/generated/001-2013508786110730241-01.png
```

同时输出每个任务的状态、耗时、结果路径和错误信息，便于创作批次追踪。

## 安全与可恢复性

- 不在日志中打印完整 API Key。
- `.gitignore` 忽略本地密钥配置和生成输出目录；示例文件只包含占位符。
- 网络请求设置连接/读取超时。
- 对 HTTP 错误、JSON 错误、任务失败、无结果和轮询超时提供明确错误。
- 任务完成后立即下载，避免临时结果链接过期。
- 不自动重试已提交任务，避免因网络问题造成重复扣费；提交前的本地校验不消耗额度。

## 测试策略

使用 Python 标准库 `unittest` 和 mock HTTP 传输层，不访问真实 RunningHub：

- 多个 `--prompt` 与提示词文件的合并和空行过滤；
- 统一宽高在每个任务请求中正确传递；
- 并发上限被限制为 100；
- 提交、轮询成功和结果下载；
- 单任务失败不会阻塞其他任务；
- 缺少 API Key、参数非法、轮询超时和无结果的错误行为；
- dry-run 只打印请求计划，不发起网络请求。

## 非目标

- 不在 Godot 内新增编辑器 UI；
- 不把 API Key 保存到仓库；
- 不实现 Webhook 服务端；
- 不修改现有卡牌、场景或游戏逻辑；
- 不自动上传生成图片到 Godot 资源数据库，下载后的文件由用户按需导入。
