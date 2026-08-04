# RunningHub Batch Image CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Python command-line tool that accepts multiple prompts, applies one shared image size, runs the prompts concurrently through RunningHub, and downloads every successful image into the project.

**Architecture:** Keep the RunningHub HTTP protocol in a small client class with an injectable transport function so tests never contact the real service. Keep CLI parsing/configuration separate from task orchestration; use `ThreadPoolExecutor` for one worker per active RunningHub task, with a hard maximum of 100. Store only non-secret workflow defaults in a local JSON config example; read `RUNNINGHUB_API_KEY` from the environment at runtime.

**Tech Stack:** Python 3.10+ standard library (`argparse`, `concurrent.futures`, `json`, `urllib.request`, `unittest`, `unittest.mock`); PowerShell-compatible commands; no third-party runtime dependency.

## Global Constraints

- API Key must be read from `RUNNINGHUB_API_KEY`; never hard-code, print, serialize, or commit it.
- RunningHub API base URL is `https://www.runninghub.cn/openapi/v2`.
- Submission endpoint is `/run/ai-app/{workflow_id}` and query endpoint is `/query`.
- Prompt/width/height are one `nodeInfoList` entry each; default mappings are `134.text`, `620.width`, and `620.height`.
- One input prompt produces one task; all prompts in a batch share the same width and height.
- User-visible concurrency is capped at 100; default is 8.
- A failed task must not cancel or hide results from other tasks; the process exits non-zero if any task fails.
- Successful result URLs are downloaded immediately into `art/generated/` unless `--output-dir` is provided.
- Do not modify existing Godot scenes, scripts, card data, or current unrelated working-tree changes.
- Every production behavior is introduced through a failing test first.

## File Map

- Create `tools/runninghub_generate.py`: CLI entry point, config loading, request payload construction, RunningHub client, batch orchestration, download naming, and exit-code handling.
- Create `tools/runninghub.example.json`: safe, non-secret workflow defaults and node mappings; no API Key.
- Create `tests/test_runninghub_generate.py`: stdlib unit tests for parsing, payloads, transport behavior, concurrency validation, polling, download, and batch failure isolation.
- Modify `.gitignore`: ignore local `tools/runninghub.json` and generated image output while keeping the example config tracked.
- Create `docs/superpowers/specs/2026-08-04-runninghub-image-cli-design.md` (already committed): source design specification.

---

### Task 1: Add CLI/data-model tests for prompts, shared size, and config

**Files:**
- Create: `tests/test_runninghub_generate.py`
- Create: `tools/runninghub_generate.py` (module skeleton only after tests fail)

**Interfaces:**
- `parse_args(argv: list[str]) -> argparse.Namespace`
- `load_config(path: Path | None) -> dict[str, object]`
- `collect_prompts(args: argparse.Namespace) -> list[str]`
- `build_node_info_list(prompt: str, width: int, height: int, config: dict, overrides: list[str]) -> list[dict[str, str]]`

- [ ] **Step 1: Write the failing tests**

```python
class CliInputTests(unittest.TestCase):
    def test_collects_repeated_prompts_and_prompt_file_in_order(self):
        args = parse_args([
            "--prompt", "first",
            "--prompt", "second",
            "--prompts-file", str(self.prompts_file),
            "--width", "768",
            "--height", "1024",
        ])
        self.assertEqual(collect_prompts(args), ["first", "second", "from-file"])

    def test_shared_dimensions_are_encoded_for_each_prompt(self):
        nodes = build_node_info_list("knife", 768, 1024, DEFAULT_CONFIG, [])
        self.assertIn({"nodeId": "620", "fieldName": "width", "fieldValue": "768", "description": "width"}, nodes)
        self.assertIn({"nodeId": "620", "fieldName": "height", "fieldValue": "1024", "description": "height"}, nodes)

    def test_comments_and_blank_prompt_file_lines_are_ignored(self):
        ...
```

The test fixture writes a temporary `prompts.txt` containing blank lines, a `# comment`, and one prompt. The tests must assert that dimensions are not read once per prompt or omitted from any payload.

- [ ] **Step 2: Run the focused tests and verify the expected failure**

Run:

```powershell
python -m unittest tests.test_runninghub_generate.CliInputTests -v
```

Expected: FAIL because `tools.runninghub_generate` and its public functions do not exist yet.

- [ ] **Step 3: Add the smallest module skeleton and CLI parser**

Define `DEFAULT_CONFIG` with the documented node mappings, an `argparse.ArgumentParser`, and the four interfaces above. `collect_prompts` must preserve argument/file order, strip whitespace, ignore blank and `#` lines, and raise `ValueError` when no prompts are provided. `build_node_info_list` must emit prompt, width, height, then configured extra nodes and `--node` overrides.

- [ ] **Step 4: Re-run the focused tests**

Run the same command. Expected: PASS.

- [ ] **Step 5: Commit the isolated CLI input behavior**

```powershell
git add tests/test_runninghub_generate.py tools/runninghub_generate.py
git commit -m "test: define RunningHub batch CLI inputs"
```

### Task 2: Implement configuration, payload validation, and secret handling

**Files:**
- Modify: `tools/runninghub_generate.py`
- Modify: `.gitignore`
- Create: `tools/runninghub.example.json`
- Test: `tests/test_runninghub_generate.py`

**Interfaces:**
- `get_api_key(environ: Mapping[str, str]) -> str`
- `build_submit_payload(workflow_id: str, node_info_list: list[dict[str, str]], config: dict) -> dict[str, object]`
- `validate_concurrency(value: int) -> int`
- `redact_secret(value: str) -> str`

- [ ] **Step 1: Write failing tests**

```python
class ConfigurationTests(unittest.TestCase):
    def test_missing_api_key_is_actionable(self):
        with self.assertRaisesRegex(ValueError, "RUNNINGHUB_API_KEY"):
            get_api_key({})

    def test_api_key_is_never_present_in_redacted_output(self):
        self.assertNotIn("secret", redact_secret("secret"))

    def test_concurrency_accepts_100_but_rejects_101_and_zero(self):
        self.assertEqual(validate_concurrency(100), 100)
        with self.assertRaises(ValueError): validate_concurrency(101)
        with self.assertRaises(ValueError): validate_concurrency(0)

    def test_payload_contains_common_options_without_stringifying_booleans(self):
        payload = build_submit_payload("wf", [], {"instance_type": "default", "use_personal_queue": False})
        self.assertEqual(payload["instanceType"], "default")
        self.assertIs(payload["usePersonalQueue"], False)
```

- [ ] **Step 2: Run the focused tests and observe failure**

```powershell
python -m unittest tests.test_runninghub_generate.ConfigurationTests -v
```

Expected: FAIL with missing functions or incorrect behavior.

- [ ] **Step 3: Implement minimal configuration behavior**

Support a JSON config with `workflow_id`, `prompt_node`, `width_node`, `height_node`, `instance_type`, `use_personal_queue`, `retain_seconds`, and `extra_nodes`. `get_api_key` trims and rejects missing/blank values. `validate_concurrency` accepts only integers 1–100. `.gitignore` adds:

```gitignore
art/generated/
tools/runninghub.json
```

The example config must contain the documented workflow ID only as an example and use no credentials.

- [ ] **Step 4: Run focused tests and inspect the diff**

```powershell
python -m unittest tests.test_runninghub_generate.ConfigurationTests -v

git diff -- .gitignore tools/runninghub.example.json tools/runninghub_generate.py tests/test_runninghub_generate.py
```

Expected: all focused tests pass and no API key appears in the diff.

- [ ] **Step 5: Commit**

```powershell
git add .gitignore tools/runninghub.example.json tools/runninghub_generate.py tests/test_runninghub_generate.py
git commit -m "feat: add RunningHub CLI configuration"
```

### Task 3: Implement the RunningHub HTTP client with polling and immediate download

**Files:**
- Modify: `tools/runninghub_generate.py`
- Test: `tests/test_runninghub_generate.py`

**Interfaces:**
- `class RunningHubError(RuntimeError)`
- `class RunningHubClient:`
  - `__init__(api_key: str, base_url: str = API_BASE_URL, transport: Callable[..., tuple[int, bytes]] | None = None)`
  - `submit_task(workflow_id: str, payload: dict[str, object]) -> str`
  - `query_task(task_id: str) -> dict[str, object]`
  - `wait_for_task(task_id: str, poll_interval: float, timeout: float, sleep: Callable[[float], None] = time.sleep) -> dict[str, object]`
  - `download(url: str, destination: Path) -> None`

- [ ] **Step 1: Write failing mocked-transport tests**

```python
class ClientTests(unittest.TestCase):
    def test_submit_query_and_download_use_bearer_auth_and_json(self):
        ...

    def test_wait_for_task_polls_queued_then_running_then_success(self):
        client = RunningHubClient("secret", transport=FakeTransport([...]))
        result = client.wait_for_task("task-1", poll_interval=0, timeout=10, sleep=lambda _: None)
        self.assertEqual(result["status"], "SUCCESS")

    def test_failed_task_raises_error_with_server_message(self):
        ...

    def test_timeout_raises_without_infinite_polling(self):
        ...
```

Fake transport records method/URL/headers/body and returns predefined JSON/bytes. Tests must assert the Authorization header is `Bearer secret` internally but never printed by CLI output.

- [ ] **Step 2: Run client tests and verify failure**

```powershell
python -m unittest tests.test_runninghub_generate.ClientTests -v
```

Expected: FAIL because `RunningHubClient` is not implemented.

- [ ] **Step 3: Implement the HTTP client**

Use `urllib.request.Request` and `urlopen` with JSON encoding for submit/query. Convert non-2xx responses, invalid JSON, missing `taskId`, failed statuses, and missing successful `results` into `RunningHubError` messages. Poll only `QUEUED` and `RUNNING`; treat `SUCCESS` as terminal success and every other status as terminal failure. Enforce the timeout with a monotonic deadline. Download with a binary request and write atomically through a temporary file in the destination directory, then rename it.

- [ ] **Step 4: Run client tests and full current Python test discovery**

```powershell
python -m unittest tests.test_runninghub_generate.ClientTests -v
python -m unittest discover -s tests -p "test_*.py" -v
```

Expected: client tests and all Python tests pass. Existing Godot tests are not modified by this task.

- [ ] **Step 5: Commit**

```powershell
git add tools/runninghub_generate.py tests/test_runninghub_generate.py
git commit -m "feat: add RunningHub task polling and download client"
```

### Task 4: Implement concurrent batch orchestration and result naming

**Files:**
- Modify: `tools/runninghub_generate.py`
- Test: `tests/test_runninghub_generate.py`

**Interfaces:**
- `@dataclass class GenerationResult`: `index`, `prompt`, `task_id`, `status`, `files`, `error`, `elapsed_seconds`
- `run_one(client, index, prompt, args, config, output_dir) -> GenerationResult`
- `run_batch(client, prompts, args, config, output_dir) -> list[GenerationResult]`
- `make_output_path(output_dir: Path, index: int, task_id: str, result_index: int, output_type: str) -> Path`

- [ ] **Step 1: Write failing concurrency and isolation tests**

```python
class BatchTests(unittest.TestCase):
    def test_each_prompt_is_submitted_once_with_same_dimensions(self):
        ...

    def test_batch_uses_requested_concurrency_and_collects_all_results(self):
        ...

    def test_one_failed_prompt_does_not_hide_successful_prompt(self):
        ...

    def test_output_names_are_unique_and_include_task_id(self):
        path = make_output_path(Path("art/generated"), 2, "abc", 1, "png")
        self.assertEqual(path.name, "002-abc-01.png")
```

Use a fake client whose submit/query/download methods are deterministic and whose active-call counter records the maximum concurrent calls. Do not use real network or arbitrary long sleeps.

- [ ] **Step 2: Run batch tests and verify failure**

```powershell
python -m unittest tests.test_runninghub_generate.BatchTests -v
```

Expected: FAIL because orchestration functions are absent.

- [ ] **Step 3: Implement bounded concurrent execution**

Create the output directory once, instantiate `ThreadPoolExecutor(max_workers=validate_concurrency(args.concurrency))`, submit one `run_one` future per prompt, and collect results as futures complete. `run_one` builds one payload, submits exactly once, waits, downloads each result, and catches `RunningHubError`/`OSError` into a failed `GenerationResult`. Use a stable zero-padded prompt index and task ID in filenames.

- [ ] **Step 4: Run batch tests and full tests**

```powershell
python -m unittest tests.test_runninghub_generate.BatchTests -v
python -m unittest discover -s tests -p "test_*.py" -v
```

Expected: PASS, including failure isolation and concurrency bound assertions.

- [ ] **Step 5: Commit**

```powershell
git add tools/runninghub_generate.py tests/test_runninghub_generate.py
git commit -m "feat: support concurrent RunningHub prompt batches"
```

### Task 5: Wire the CLI, dry-run, documentation, and verification

**Files:**
- Modify: `tools/runninghub_generate.py`
- Modify: `tests/test_runninghub_generate.py`
- Modify: `README.md` if present; otherwise create `tools/README.md`
- Modify: `.gitignore` only if verification finds missing secret/output patterns

**Interfaces:**
- `main(argv: Sequence[str] | None = None) -> int`
- `format_summary(results: Sequence[GenerationResult]) -> str`

- [ ] **Step 1: Write failing CLI integration tests**

```python
class MainTests(unittest.TestCase):
    def test_dry_run_prints_batch_plan_without_transport_calls(self):
        ...

    def test_main_returns_nonzero_when_any_prompt_fails(self):
        ...
```

Patch the client factory and capture stdout. Assert the output includes prompt count, shared dimensions, and concurrency but not the API key.

- [ ] **Step 2: Run integration tests and verify failure**

```powershell
python -m unittest tests.test_runninghub_generate.MainTests -v
```

Expected: FAIL until `main` and summary formatting are wired.

- [ ] **Step 3: Implement the CLI entry point**

Merge config values with explicit CLI overrides, require `--workflow-id` either from CLI or config, require one or more prompts, require positive width/height, load the API key only when not in `--dry-run`, call `run_batch`, print a concise per-task summary, and return `0` only when all tasks succeed. Add the standard `if __name__ == "__main__": raise SystemExit(main())` entry point.

Document Windows PowerShell setup, environment variable usage, config creation by copying `tools/runninghub.example.json` to ignored `tools/runninghub.json`, repeated `--prompt`, `--prompts-file`, shared `--width/--height`, and concurrency examples. Include a clear warning that generated URLs expire and the tool downloads them immediately.

- [ ] **Step 4: Run all verification commands**

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
python tools/runninghub_generate.py --help
python tools/runninghub_generate.py --dry-run --workflow-id 2084605200131780610 --prompt "test" --prompt "test 2" --width 512 --height 512 --concurrency 100

git diff --check
git status --short
```

Expected: all tests pass, help is readable, dry-run shows two planned prompts with shared 512x512 dimensions, no API key is printed, and the status contains only intended new/modified files plus the user’s pre-existing changes.

- [ ] **Step 5: Commit the completed CLI**

```powershell
git add tools/runninghub_generate.py tests/test_runninghub_generate.py tools/runninghub.example.json .gitignore README.md tools/README.md
git commit -m "feat: add RunningHub batch image generation CLI"
```

## Self-Review Checklist

- Spec coverage: prompt batching, shared dimensions, concurrency cap, task polling, immediate download, output directory, errors, dry-run, secret handling, and tests are covered by Tasks 1–5.
- Placeholder scan: all tasks specify concrete paths, interfaces, test commands, and expected outcomes; no TODO/TBD steps remain.
- Type consistency: client, orchestration, and CLI function signatures are defined before they are consumed.
- Scope safety: only new tooling/docs and `.gitignore` are touched; existing Godot gameplay changes remain untouched.
