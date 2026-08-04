# RunningHub 快捷生图工具

`runninghub_generate.py` 用于把一批不同的提示词提交给同一个 RunningHub AI App 工作流。每次命令只需输入一次宽度和高度；每个提示词会独立生成一张图，任务可以并发执行，最大并发数是 100。

## 1. 配置 API Key

工具会自动读取 `tools/.env` 文件。也可以不要把 API Key 写入脚本或 JSON 文件，而是在 PowerShell 会话中设置环境变量：

```powershell
$env:RUNNINGHUB_API_KEY = "你的-RunningHub-API-Key"
```

`tools/.env` 会被自动加载；如果系统环境变量中已经存在 `RUNNINGHUB_API_KEY`，系统环境变量优先。`.env` 已加入 Git 忽略规则，请勿把这个文件、含 Key 的终端截图或本地密钥配置提交到 Git。

## 2. 创建本地工作流配置

复制安全的工作流配置示例：

```powershell
Copy-Item tools/runninghub.example.json tools/runninghub.json
```

`tools/runninghub.json` 已被 Git 忽略。API Key 应保存在同目录的 `tools/.env`，可参考 `tools/.env.example`。根据目标 RunningHub AI App 修改：

- `workflow_id`：AI App 工作流 ID；
- `prompt_node`：正向提示词字段，如 `134.text`；
- `width_node` / `height_node`：尺寸字段，如 `620.width`、`620.height`；
- `extra_nodes`：固定的额外工作流参数，例如采样器、模型或负面提示词。

`extra_nodes` 示例：

```json
{
  "extra_nodes": [
    {
      "nodeId": "135",
      "fieldName": "text",
      "fieldValue": "blurry, watermark, text",
      "description": "negative prompt"
    }
  ]
}
```

## 3. 一次生成多张不同资源

下面命令为两段不同的提示词分别创建任务，图片尺寸统一为 `512 × 512`。`--concurrency 2` 表示最多同时执行两个 RunningHub 任务；你的账号支持 100 并发时可以改为 `100`。

```powershell
python tools/runninghub_generate.py `
  --config tools/runninghub.json `
  --prompt "ash-white rib bone knife, dark fantasy game card art" `
  --prompt "weathered pilgrim lantern, dark fantasy game card art" `
  --width 512 `
  --height 512 `
  --concurrency 2
```

成功的图片会立即下载到 `art/generated/`，文件名包括该提示词的批次序号、RunningHub 任务 ID 和结果序号，例如：

```text
art/generated/001-2013508786110730241-01.png
```

生成结果 URL 有时效，因此脚本会完成后立即下载而不只打印链接。

## 4. 从文本文件批量读取提示词

新建 `prompts.txt`，每行一段提示词。空行与 `#` 开头的行会跳过：

```text
# weapon cards
short knife carved from an ash-white rib bone, dark fantasy card art
bronze pilgrim lantern with a warm ember core, dark fantasy card art
```

执行：

```powershell
python tools/runninghub_generate.py `
  --config tools/runninghub.json `
  --prompts-file prompts.txt `
  --width 768 `
  --height 1024 `
  --concurrency 100
```

`--prompt` 和 `--prompts-file` 可以同时使用。

## 5. 临时覆盖工作流节点

无需修改配置文件，可用重复的 `--node` 参数覆盖任意字段：

```powershell
python tools/runninghub_generate.py `
  --config tools/runninghub.json `
  --prompt "pilgrim shield, dark fantasy card art" `
  --width 512 --height 512 `
  --node "77.seed=42" `
  --node "135.text=blurry, watermark, text"
```

格式必须是 `节点ID.字段名=值`。

## 6. 消耗额度前检查

使用 `--dry-run` 只检查参数、提示词数量、尺寸与并发，不会读取 API Key 或发起网络请求：

```powershell
python tools/runninghub_generate.py `
  --dry-run `
  --workflow-id 2084605200131780610 `
  --prompt "test one" `
  --prompt "test two" `
  --width 512 --height 512 `
  --concurrency 100
```

## 常见错误

- `RUNNINGHUB_API_KEY is required`：先按第 1 步在当前 PowerShell 窗口设置 Key。
- `Task ... FAILED`：RunningHub 返回了工作流或参数错误；检查节点 ID、字段名和提示词。
- `timed out`：可增大 `--timeout`（默认 900 秒）或检查 RunningHub 队列状态。
- 一批中有任务失败：脚本会继续下载成功结果，最终以非零退出码报告批次存在失败。

运行完整参数说明：

```powershell
python tools/runninghub_generate.py --help
```
