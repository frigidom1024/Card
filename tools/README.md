# RunningHub 快捷生图工具

`runninghub_generate.py` 用于把一批不同的提示词提交到**内置且固定的** RunningHub AI App 工作流。该工具使用已写入脚本的工作流 ID、提示词节点和尺寸节点；不读取 `runninghub.json`，也不提供工作流、节点、队列或实例类型的命令行覆盖参数。

每次命令只需输入一次宽度和高度；每个提示词会独立生成一张图，任务可以并发执行，最大并发数是 100。

## 1. 配置 API Key

工具会自动读取 `tools/.env` 文件。请在该文件中填写：

```dotenv
RUNNINGHUB_API_KEY=你的-RunningHub-API-Key
```

也可以在 PowerShell 会话中设置环境变量：

```powershell
$env:RUNNINGHUB_API_KEY = "你的-RunningHub-API-Key"
```

如果系统环境变量中已经存在 `RUNNINGHUB_API_KEY`，系统环境变量优先。`.env` 已加入 Git 忽略规则，请勿把这个文件、含 Key 的终端截图或本地密钥配置提交到 Git。

## 2. 一次生成多张不同资源

下面命令为两段不同的提示词分别创建任务，图片尺寸统一为 `512 × 512`。`--concurrency 2` 表示最多同时执行两个 RunningHub 任务；账号支持 100 并发时可以改为 `100`。

```powershell
python tools/runninghub_generate.py `
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

## 3. 从文本文件批量读取提示词

新建 `prompts.txt`，每行一段提示词。空行与 `#` 开头的行会跳过：

```text
# weapon cards
short knife carved from an ash-white rib bone, dark fantasy card art
bronze pilgrim lantern with a warm ember core, dark fantasy card art
```

执行：

```powershell
python tools/runninghub_generate.py `
  --prompts-file prompts.txt `
  --width 768 `
  --height 1024 `
  --concurrency 100
```

`--prompt` 和 `--prompts-file` 可以同时使用。

## 4. 消耗额度前检查

使用 `--dry-run` 只检查参数、提示词数量、尺寸与并发，不会读取 API Key 或发起网络请求：

```powershell
python tools/runninghub_generate.py `
  --dry-run `
  --prompt "test one" `
  --prompt "test two" `
  --width 512 --height 512 `
  --concurrency 100
```

## 固定工作流说明

本工具的 RunningHub 工作流配置已经写入 `tools/runninghub_generate.py`，并固定使用：

- 工作流 ID：`2084605200131780610`
- 提示词节点：`134.text`
- 宽度节点：`620.width`
- 高度节点：`620.height`
- 实例类型：`default`
- 个人队列：关闭

如果要使用不同的 RunningHub 工作流，应新建独立工具脚本，而不是修改本工具的调用参数。

## 常见错误

- `RUNNINGHUB_API_KEY is required`：先在 `tools/.env` 中填写 Key，或在当前 PowerShell 窗口设置 Key。
- `Task ... FAILED`：RunningHub 返回了工作流或提示词错误。
- `timed out`：可增大 `--timeout`（默认 900 秒）或检查 RunningHub 队列状态。
- 一批中有任务失败：脚本会继续下载成功结果，最终以非零退出码报告批次存在失败。

运行完整参数说明：

```powershell
python tools/runninghub_generate.py --help
```
