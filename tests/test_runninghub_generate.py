import io
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.runninghub_generate import (
    API_BASE_URL,
    DEFAULT_CONFIG,
    GenerationResult,
    RunningHubClient,
    RunningHubError,
    build_node_info_list,
    build_submit_payload,
    collect_prompts,
    get_api_key,
    load_config,
    make_output_path,
    parse_args,
    redact_secret,
    run_batch,
    validate_concurrency,
)


class CliInputTests(unittest.TestCase):
    def test_collects_repeated_prompts_and_prompt_file_in_order(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            prompt_file = Path(temp_dir) / "prompts.txt"
            prompt_file.write_text("\n# ignored\nfrom-file\n", encoding="utf-8")
            args = parse_args([
                "--prompt", "first",
                "--prompt", "second",
                "--prompts-file", str(prompt_file),
                "--width", "768",
                "--height", "1024",
            ])
            self.assertEqual(collect_prompts(args), ["first", "second", "from-file"])

    def test_comments_and_blank_prompt_file_lines_are_ignored(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            prompt_file = Path(temp_dir) / "prompts.txt"
            prompt_file.write_text("  # comment\n  \n  one  \n", encoding="utf-8")
            args = parse_args(["--prompts-file", str(prompt_file)])
            self.assertEqual(collect_prompts(args), ["one"])

    def test_shared_dimensions_are_encoded_for_each_prompt(self):
        nodes = build_node_info_list("knife", 768, 1024, DEFAULT_CONFIG, [])
        self.assertIn({"nodeId": "620", "fieldName": "width", "fieldValue": "768", "description": "width"}, nodes)
        self.assertIn({"nodeId": "620", "fieldName": "height", "fieldValue": "1024", "description": "height"}, nodes)

    def test_extra_node_override_is_encoded(self):
        nodes = build_node_info_list("knife", 512, 512, DEFAULT_CONFIG, ["77.seed=42"])
        self.assertIn({"nodeId": "77", "fieldName": "seed", "fieldValue": "42", "description": "seed"}, nodes)


class ConfigurationTests(unittest.TestCase):
    def test_missing_api_key_is_actionable(self):
        with self.assertRaisesRegex(ValueError, "RUNNINGHUB_API_KEY"):
            get_api_key({})

    def test_api_key_is_never_present_in_redacted_output(self):
        self.assertNotIn("secret", redact_secret("secret"))

    def test_concurrency_accepts_100_but_rejects_101_and_zero(self):
        self.assertEqual(validate_concurrency(100), 100)
        with self.assertRaises(ValueError):
            validate_concurrency(101)
        with self.assertRaises(ValueError):
            validate_concurrency(0)

    def test_payload_contains_common_options_without_stringifying_booleans(self):
        payload = build_submit_payload("wf", [], {"instance_type": "default", "use_personal_queue": False})
        self.assertEqual(payload["nodeInfoList"], [])
        self.assertEqual(payload["instanceType"], "default")
        self.assertIs(payload["usePersonalQueue"], False)

    def test_load_config_rejects_invalid_json_object(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "config.json"
            path.write_text("[]", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_config(path)


class FakeTransport:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, method, url, headers, body, timeout):
        self.calls.append((method, url, headers, body, timeout))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class ClientTests(unittest.TestCase):
    def test_submit_query_and_download_use_bearer_auth_and_json(self):
        transport = FakeTransport([
            (200, b'{"taskId":"task-1","status":"QUEUED"}'),
            (200, b'PNGDATA'),
        ])
        client = RunningHubClient("secret", transport=transport)
        task_id = client.submit_task("wf", {"nodeInfoList": []})
        with tempfile.TemporaryDirectory() as temp_dir:
            destination = Path(temp_dir) / "image.png"
            client.download("https://example.test/image.png", destination)
            self.assertEqual(destination.read_bytes(), b"PNGDATA")
        self.assertEqual(task_id, "task-1")
        self.assertEqual(transport.calls[0][0:2], ("POST", f"{API_BASE_URL}/run/ai-app/wf"))
        self.assertEqual(transport.calls[0][2]["Authorization"], "Bearer secret")
        self.assertEqual(json.loads(transport.calls[0][3].decode()), {"nodeInfoList": []})
        self.assertEqual(transport.calls[1][0:2], ("GET", "https://example.test/image.png"))

    def test_wait_for_task_polls_queued_then_running_then_success(self):
        transport = FakeTransport([
            (200, b'{"taskId":"task-1","status":"QUEUED"}'),
            (200, b'{"taskId":"task-1","status":"RUNNING"}'),
            (200, b'{"taskId":"task-1","status":"SUCCESS","results":[{"url":"https://example.test/image.png","outputType":"png"}]}'),
        ])
        client = RunningHubClient("secret", transport=transport)
        result = client.wait_for_task("task-1", poll_interval=0, timeout=10, sleep=lambda _: None)
        self.assertEqual(result["status"], "SUCCESS")
        self.assertEqual(len(transport.calls), 3)
        self.assertTrue(all(call[0] == "POST" and call[1].endswith("/query") for call in transport.calls))

    def test_failed_task_raises_error_with_server_message(self):
        transport = FakeTransport([(200, b'{"taskId":"task-1","status":"FAILED","errorMessage":"bad prompt"}')])
        client = RunningHubClient("secret", transport=transport)
        with self.assertRaisesRegex(RunningHubError, "bad prompt"):
            client.wait_for_task("task-1", poll_interval=0, timeout=10, sleep=lambda _: None)

    def test_timeout_raises_without_infinite_polling(self):
        transport = FakeTransport([(200, b'{"taskId":"task-1","status":"RUNNING"}')])
        client = RunningHubClient("secret", transport=transport)
        with patch("tools.runninghub_generate.time.monotonic", side_effect=[0, 11]):
            with self.assertRaisesRegex(RunningHubError, "timed out"):
                client.wait_for_task("task-1", poll_interval=0, timeout=10, sleep=lambda _: None)


class BatchTests(unittest.TestCase):
    class FakeClient:
        def __init__(self, fail_prompt=None):
            self.fail_prompt = fail_prompt
            self.payloads = []
            self.downloaded = []
            self.active = 0
            self.max_active = 0
            self.lock = threading.Lock()

        def submit_task(self, workflow_id, payload):
            prompt = next(node["fieldValue"] for node in payload["nodeInfoList"] if node["fieldName"] == "text")
            with self.lock:
                self.payloads.append((workflow_id, payload))
                self.active += 1
                self.max_active = max(self.max_active, self.active)
            time.sleep(0.01)
            with self.lock:
                self.active -= 1
            if prompt == self.fail_prompt:
                raise RunningHubError("failed prompt")
            return f"task-{prompt}"

        def wait_for_task(self, task_id, poll_interval, timeout):
            return {"status": "SUCCESS", "results": [{"url": f"https://example.test/{task_id}.png", "outputType": "png"}]}

        def download(self, url, destination):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(url.encode())
            self.downloaded.append(destination)

    def test_each_prompt_is_submitted_once_with_same_dimensions(self):
        client = self.FakeClient()
        args = parse_args(["--workflow-id", "wf", "--width", "512", "--height", "768", "--concurrency", "2"])
        with tempfile.TemporaryDirectory() as temp_dir:
            results = run_batch(client, ["a", "b"], args, DEFAULT_CONFIG, Path(temp_dir))
        self.assertEqual(len(results), 2)
        self.assertEqual(len(client.payloads), 2)
        for _, payload in client.payloads:
            fields = {(node["nodeId"], node["fieldName"]): node["fieldValue"] for node in payload["nodeInfoList"]}
            self.assertEqual(fields[("620", "width")], "512")
            self.assertEqual(fields[("620", "height")], "768")

    def test_batch_uses_requested_concurrency_and_collects_all_results(self):
        client = self.FakeClient()
        args = parse_args(["--workflow-id", "wf", "--width", "512", "--height", "512", "--concurrency", "2"])
        with tempfile.TemporaryDirectory() as temp_dir:
            results = run_batch(client, ["a", "b", "c", "d"], args, DEFAULT_CONFIG, Path(temp_dir))
        self.assertEqual(len(results), 4)
        self.assertLessEqual(client.max_active, 2)
        self.assertTrue(all(result.status == "SUCCESS" for result in results))

    def test_one_failed_prompt_does_not_hide_successful_prompt(self):
        client = self.FakeClient(fail_prompt="bad")
        args = parse_args(["--workflow-id", "wf", "--width", "512", "--height", "512"])
        with tempfile.TemporaryDirectory() as temp_dir:
            results = run_batch(client, ["bad", "good"], args, DEFAULT_CONFIG, Path(temp_dir))
        self.assertEqual({result.status for result in results}, {"FAILED", "SUCCESS"})

    def test_output_names_are_unique_and_include_task_id(self):
        path = make_output_path(Path("art/generated"), 2, "abc", 1, "png")
        self.assertEqual(path.name, "002-abc-01.png")


class MainTests(unittest.TestCase):
    def test_dry_run_does_not_require_api_key_or_make_transport_calls(self):
        from tools import runninghub_generate
        with patch.object(runninghub_generate, "RunningHubClient") as client_class:
            exit_code = runninghub_generate.main([
                "--dry-run", "--workflow-id", "wf", "--prompt", "one", "--prompt", "two",
                "--width", "512", "--height", "512", "--concurrency", "100",
            ])
        self.assertEqual(exit_code, 0)
        client_class.assert_not_called()


if __name__ == "__main__":
    unittest.main()
