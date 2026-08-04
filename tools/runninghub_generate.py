"""Run a batch of shared-size image prompts through a RunningHub AI App workflow."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, MutableMapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

API_BASE_URL = "https://www.runninghub.cn/openapi/v2"
FIXED_WORKFLOW_CONFIG: dict[str, Any] = {
    "workflow_id": "2084605200131780610",
    "prompt_node": "134.text",
    "width_node": "620.width",
    "height_node": "620.height",
    "instance_type": "default",
    "use_personal_queue": False,
    "retain_seconds": None,
    "extra_nodes": [],
}


Transport = Callable[[str, str, Mapping[str, str], bytes | None, float], tuple[int, bytes]]


class RunningHubError(RuntimeError):
    """A request, task, or result from RunningHub could not be completed."""


@dataclass(frozen=True)
class GenerationResult:
    index: int
    prompt: str
    task_id: str | None
    status: str
    files: list[Path]
    error: str | None
    elapsed_seconds: float


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Batch-generate images with the embedded RunningHub AI App workflow.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--prompt", action="append", default=[], help="Prompt to generate; repeat for a batch.")
    parser.add_argument(
        "--prompts-file",
        action="append",
        type=Path,
        default=[],
        help="UTF-8 file containing one prompt per line; blank and # comment lines are ignored.",
    )
    parser.add_argument("--width", type=int, help="Shared output width for every prompt.")
    parser.add_argument("--height", type=int, help="Shared output height for every prompt.")
    parser.add_argument("--concurrency", type=int, default=8, help="Maximum active tasks, from 1 to 100.")
    parser.add_argument("--poll-interval", type=float, default=5.0, help="Seconds between task status queries.")
    parser.add_argument("--timeout", type=float, default=900.0, help="Maximum seconds to wait for one task.")
    parser.add_argument("--output-dir", type=Path, default=Path("art/generated"), help="Downloaded image directory.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print the planned batch without network calls.")
    return parser.parse_args(argv)


def default_env_path() -> Path:
    """Return the ignored local env file stored alongside this tool."""
    return Path(__file__).resolve().parent / ".env"
def load_env_file(path: Path, environ: MutableMapping[str, str]) -> None:
    """Load simple KEY=VALUE entries without overriding existing environment values."""
    if not path.is_file():
        return
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"Unable to read env file {path}: {exc}") from exc
    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise ValueError(f"Invalid .env entry at {path}:{line_number}; expected KEY=VALUE.")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key or not (key[0].isalpha() or key[0] == "_") or not all(character.isalnum() or character == "_" for character in key):
            raise ValueError(f"Invalid .env variable name at {path}:{line_number}.")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        environ.setdefault(key, value)
def collect_prompts(args: argparse.Namespace) -> list[str]:
    prompts = [prompt.strip() for prompt in args.prompt if prompt and prompt.strip()]
    for path in args.prompts_file:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            raise ValueError(f"Unable to read prompts file {path}: {exc}") from exc
        prompts.extend(line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#"))
    if not prompts:
        raise ValueError("Provide at least one --prompt or --prompts-file entry.")
    return prompts


def get_api_key(environ: Mapping[str, str]) -> str:
    api_key = environ.get("RUNNINGHUB_API_KEY", "").strip()
    if not api_key:
        raise ValueError("RUNNINGHUB_API_KEY is required. Set it in your shell before running this command.")
    return api_key


def redact_secret(_: str) -> str:
    return "<redacted>"


def validate_concurrency(value: int) -> int:
    if not 1 <= value <= 100:
        raise ValueError("--concurrency must be an integer from 1 to 100.")
    return value


def _parse_node_reference(value: str, option_name: str) -> tuple[str, str]:
    try:
        node_id, field_name = value.rsplit(".", 1)
    except ValueError as exc:
        raise ValueError(f"{option_name} must use NODE_ID.FIELD_NAME format, received {value!r}.") from exc
    if not node_id or not field_name:
        raise ValueError(f"{option_name} must use NODE_ID.FIELD_NAME format, received {value!r}.")
    return node_id, field_name


def _node_entry(node_id: str, field_name: str, value: object, description: str | None = None) -> dict[str, str]:
    return {
        "nodeId": str(node_id),
        "fieldName": str(field_name),
        "fieldValue": str(value),
        "description": description or str(field_name),
    }


def build_node_info_list(prompt: str, width: int, height: int) -> list[dict[str, str]]:
    """Build this tool's fixed workflow inputs for one prompt."""
    prompt_id, prompt_field = _parse_node_reference(FIXED_WORKFLOW_CONFIG["prompt_node"], "prompt_node")
    width_id, width_field = _parse_node_reference(FIXED_WORKFLOW_CONFIG["width_node"], "width_node")
    height_id, height_field = _parse_node_reference(FIXED_WORKFLOW_CONFIG["height_node"], "height_node")
    return [
        _node_entry(prompt_id, prompt_field, prompt, "prompt"),
        _node_entry(width_id, width_field, width, "width"),
        _node_entry(height_id, height_field, height, "height"),
    ]


def build_submit_payload(node_info_list: list[dict[str, str]]) -> dict[str, object]:
    """Build the non-editable request payload for the embedded workflow."""
    payload: dict[str, object] = {"nodeInfoList": node_info_list}
    instance_type = FIXED_WORKFLOW_CONFIG["instance_type"]
    if instance_type:
        payload["instanceType"] = instance_type
    payload["usePersonalQueue"] = FIXED_WORKFLOW_CONFIG["use_personal_queue"]
    retain_seconds = FIXED_WORKFLOW_CONFIG["retain_seconds"]
    if retain_seconds is not None:
        payload["retainSeconds"] = retain_seconds
    return payload


def _default_transport(
    method: str,
    url: str,
    headers: Mapping[str, str],
    body: bytes | None,
    timeout: float,
) -> tuple[int, bytes]:
    request = Request(url, data=body, headers=dict(headers), method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            return int(response.status), response.read()
    except HTTPError as exc:
        return exc.code, exc.read()
    except URLError as exc:
        raise RunningHubError(f"Network request to RunningHub failed: {exc.reason}") from exc


class RunningHubClient:
    def __init__(
        self,
        api_key: str,
        base_url: str = API_BASE_URL,
        transport: Transport | None = None,
        request_timeout: float = 30.0,
    ) -> None:
        self._api_key = api_key
        self.base_url = base_url.rstrip("/")
        self._transport = transport or _default_transport
        self.request_timeout = request_timeout

    @property
    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def _request_json(self, method: str, url: str, payload: Mapping[str, object] | None = None) -> dict[str, Any]:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
        status, response_body = self._transport(method, url, self._headers, body, self.request_timeout)
        try:
            data = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RunningHubError(f"RunningHub returned invalid JSON (HTTP {status}).") from exc
        if not 200 <= status < 300:
            message = data.get("errorMessage") if isinstance(data, Mapping) else None
            raise RunningHubError(f"RunningHub request failed (HTTP {status}): {message or data}")
        if not isinstance(data, dict):
            raise RunningHubError("RunningHub returned a JSON response that is not an object.")
        return data

    def submit_task(self, workflow_id: str, payload: dict[str, object]) -> str:
        data = self._request_json("POST", f"{self.base_url}/run/ai-app/{workflow_id}", payload)
        task_id = data.get("taskId")
        if not task_id:
            message = data.get("errorMessage") or data.get("message") or "response did not contain taskId"
            raise RunningHubError(f"RunningHub did not accept the task: {message}")
        return str(task_id)

    def query_task(self, task_id: str) -> dict[str, Any]:
        return self._request_json("POST", f"{self.base_url}/query", {"taskId": task_id})

    def wait_for_task(
        self,
        task_id: str,
        poll_interval: float,
        timeout: float,
        sleep: Callable[[float], None] = time.sleep,
    ) -> dict[str, Any]:
        if poll_interval < 0:
            raise ValueError("poll_interval must not be negative.")
        if timeout <= 0:
            raise ValueError("timeout must be greater than zero.")
        deadline = time.monotonic() + timeout
        while True:
            data = self.query_task(task_id)
            status = str(data.get("status", "")).upper()
            if status == "SUCCESS":
                results = data.get("results")
                if not isinstance(results, list) or not results:
                    raise RunningHubError(f"Task {task_id} completed but returned no results.")
                return data
            if status not in {"QUEUED", "RUNNING"}:
                message = data.get("errorMessage") or data.get("failedReason") or "unknown task error"
                raise RunningHubError(f"Task {task_id} finished with status {status or 'UNKNOWN'}: {message}")
            if time.monotonic() >= deadline:
                raise RunningHubError(f"Task {task_id} timed out after {timeout:g} seconds.")
            sleep(poll_interval)

    def download(self, url: str, destination: Path) -> None:
        headers = {"Authorization": f"Bearer {self._api_key}"}
        status, body = self._transport("GET", url, headers, None, self.request_timeout)
        if not 200 <= status < 300:
            raise RunningHubError(f"Unable to download generated result (HTTP {status}).")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(f".{destination.name}.part")
        try:
            temporary.write_bytes(body)
            temporary.replace(destination)
        except OSError as exc:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
            raise RunningHubError(f"Unable to save generated result to {destination}: {exc}") from exc


def make_output_path(output_dir: Path, index: int, task_id: str, result_index: int, output_type: str) -> Path:
    extension = output_type.strip().lower().lstrip(".") or "bin"
    safe_task_id = "".join(character if character.isalnum() or character in "-_" else "_" for character in task_id)
    return output_dir / f"{index:03d}-{safe_task_id}-{result_index:02d}.{extension}"


def _result_extension(result: Mapping[str, Any]) -> str:
    output_type = str(result.get("outputType") or "").strip()
    if output_type:
        return output_type
    url = str(result.get("url") or "")
    suffix = Path(urlparse(url).path).suffix
    return suffix.lstrip(".") or "bin"


def run_one(
    client: RunningHubClient,
    index: int,
    prompt: str,
    args: argparse.Namespace,
    output_dir: Path,
) -> GenerationResult:
    started_at = time.monotonic()
    task_id: str | None = None
    try:
        workflow_id = FIXED_WORKFLOW_CONFIG["workflow_id"]
        node_info_list = build_node_info_list(prompt, args.width, args.height)
        task_id = client.submit_task(workflow_id, build_submit_payload(node_info_list))
        completed = client.wait_for_task(task_id, args.poll_interval, args.timeout)
        files: list[Path] = []
        for result_index, output in enumerate(completed["results"], start=1):
            if not isinstance(output, Mapping) or not output.get("url"):
                continue
            destination = make_output_path(output_dir, index, task_id, result_index, _result_extension(output))
            client.download(str(output["url"]), destination)
            files.append(destination)
        if not files:
            raise RunningHubError(f"Task {task_id} completed but did not provide downloadable files.")
        return GenerationResult(index, prompt, task_id, "SUCCESS", files, None, time.monotonic() - started_at)
    except (RunningHubError, OSError, ValueError) as exc:
        return GenerationResult(index, prompt, task_id, "FAILED", [], str(exc), time.monotonic() - started_at)


def run_batch(
    client: RunningHubClient,
    prompts: Sequence[str],
    args: argparse.Namespace,
    output_dir: Path,
) -> list[GenerationResult]:
    concurrency = validate_concurrency(args.concurrency)
    output_dir.mkdir(parents=True, exist_ok=True)
    results: list[GenerationResult] = []
    with ThreadPoolExecutor(max_workers=concurrency, thread_name_prefix="runninghub") as executor:
        futures = {
            executor.submit(run_one, client, index, prompt, args, output_dir): index
            for index, prompt in enumerate(prompts, start=1)
        }
        for future in as_completed(futures):
            results.append(future.result())
    return sorted(results, key=lambda item: item.index)


def format_summary(results: Sequence[GenerationResult]) -> str:
    lines = []
    for result in sorted(results, key=lambda item: item.index):
        if result.status == "SUCCESS":
            paths = ", ".join(str(path) for path in result.files)
            lines.append(f"[{result.index:03d}] SUCCESS task={result.task_id} files={paths} ({result.elapsed_seconds:.1f}s)")
        else:
            lines.append(f"[{result.index:03d}] FAILED prompt={result.prompt!r}: {result.error}")
    succeeded = sum(result.status == "SUCCESS" for result in results)
    lines.append(f"Completed {succeeded}/{len(results)} prompts successfully.")
    return "\n".join(lines)


def _validate_run_inputs(args: argparse.Namespace) -> None:
    if args.width is None or args.width <= 0:
        raise ValueError("--width must be a positive integer.")
    if args.height is None or args.height <= 0:
        raise ValueError("--height must be a positive integer.")
    validate_concurrency(args.concurrency)
    if args.poll_interval < 0:
        raise ValueError("--poll-interval must not be negative.")
    if args.timeout <= 0:
        raise ValueError("--timeout must be greater than zero.")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        prompts = collect_prompts(args)
        _validate_run_inputs(args)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    workflow_id = FIXED_WORKFLOW_CONFIG["workflow_id"]
    print(
        f"Batch plan: {len(prompts)} prompt(s), {args.width}x{args.height}, "
        f"concurrency={args.concurrency}, workflow={workflow_id}."
    )
    if args.dry_run:
        for index, prompt in enumerate(prompts, start=1):
            print(f"[{index:03d}] {prompt}")
        return 0

    try:
        env_path = default_env_path()
        load_env_file(env_path, os.environ)
        api_key = get_api_key(os.environ)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    client = RunningHubClient(api_key)
    results = run_batch(client, prompts, args, args.output_dir)
    print(format_summary(results))
    return 0 if all(result.status == "SUCCESS" for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
