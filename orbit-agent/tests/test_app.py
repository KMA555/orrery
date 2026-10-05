import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class ModelFixture(BaseHTTPRequestHandler):
    requests = []
    ready = True
    fail = False
    stream_gate = None
    truncated = False

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok" if self.ready else "loading"}).encode())

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.requests.append(payload)
        self.send_response(429 if self.fail else 200)
        self.end_headers()
        if payload.get("stream") and not self.fail:
            for i, piece in enumerate(["検証用", "の返答"]):
                self.wfile.write(("data: " + json.dumps({"choices": [{"delta": {"content": piece}}]}, ensure_ascii=False) + "\n\n").encode())
                self.wfile.flush()
                if i == 0 and self.stream_gate is not None:
                    self.stream_gate.wait(5)
            if not self.truncated:
                self.wfile.write(b"data: [DONE]\n\n")
        else:
            self.wfile.write(json.dumps({"choices": [{"message": {"content": "検証用の返答"}}]}, ensure_ascii=False).encode())


class AppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        spec = importlib.util.spec_from_file_location("orbit_test", Path(__file__).resolve().parents[1] / "server.py")
        cls.app = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.app)
        cls.app.DATA = Path(cls.temp.name)
        cls.app.PROVIDER = "local"
        cls.app.initialize()
        cls.model = ThreadingHTTPServer(("127.0.0.1", 0), ModelFixture)
        cls.app.LOCAL_PORT = cls.model.server_address[1]
        cls.http = ThreadingHTTPServer(("127.0.0.1", 0), cls.app.Handler)
        cls.app.PORT = cls.http.server_address[1]
        cls.origin = f"http://127.0.0.1:{cls.app.PORT}"
        for server in (cls.model, cls.http):
            threading.Thread(target=server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        for server in (cls.http, cls.model):
            server.shutdown()
            server.server_close()
        cls.temp.cleanup()

    def setUp(self):
        with self.app.database() as db:
            for table in ("messages", "memories", "tasks", "feedback", "jobs", "recipes"):
                db.execute(f"DELETE FROM {table}")
        ModelFixture.ready = True
        ModelFixture.fail = False
        ModelFixture.requests.clear()
        ModelFixture.stream_gate = None
        ModelFixture.truncated = False

    def request(self, route, body=None, origin=None):
        headers = {"Origin": origin or self.origin, "Content-Type": "application/json"}
        req = urllib.request.Request(self.origin + route, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as e:
            return e.code, json.load(e)

    def test_stream_delivers_before_model_finishes_and_saves_only_complete_reply(self):
        ModelFixture.stream_gate = threading.Event()
        request = urllib.request.Request(self.origin + "/api/chat/stream", data=json.dumps({"content": "こんにちは"}).encode(), headers={"Origin": self.origin, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                first = json.loads(response.readline())
                self.assertEqual(first, {"type": "delta", "text": "検証用"})
                self.assertEqual(self.app.state()["messages"], [])
                ModelFixture.stream_gate.set()
                events = [json.loads(line) for line in response]
            self.assertEqual(events[-1]["type"], "done")
            self.assertEqual(events[-1]["state"]["messages"][-1]["content"], "検証用の返答")
        finally:
            ModelFixture.stream_gate.set()

    def test_truncated_stream_reports_error_without_saving_partial_reply(self):
        ModelFixture.truncated = True
        request = urllib.request.Request(self.origin + "/api/chat/stream", data=json.dumps({"content": "こんにちは"}).encode(), headers={"Origin": self.origin, "Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=3) as response:
            events = [json.loads(line) for line in response]
        self.assertEqual(events[0]["type"], "delta")
        self.assertEqual(events[-1]["type"], "error")
        self.assertEqual(self.app.state()["messages"], [])

    def test_memory_persists_and_can_be_deleted(self):
        _, s = self.request("/api/memories", {"content": "回答は短めが好き"})
        self.app.initialize()
        self.assertEqual(self.app.state()["memories"][0]["content"], "回答は短めが好き")
        _, s = self.request("/api/memories/delete", {"id": s["memories"][0]["id"]})
        self.assertEqual(s["memories"], [])

    def test_tasks_complete_and_delete(self):
        _, s = self.request("/api/tasks", {"title": "提案書の下書き"})
        task_id = s["tasks"][0]["id"]
        _, s = self.request("/api/tasks/toggle", {"id": task_id})
        self.assertEqual(s["tasks"][0]["done"], 1)
        _, s = self.request("/api/tasks/delete", {"id": task_id})
        self.assertEqual(s["tasks"], [])

    def test_memory_task_and_feedback_reach_next_ai_request(self):
        self.request("/api/memories", {"content": "回答は短めが好き"})
        self.request("/api/tasks", {"title": "提案書を書く"})
        code, s = self.request("/api/chat", {"content": "仕事を相談したい"})
        self.assertEqual(code, 200)
        self.assertEqual([m["role"] for m in s["messages"]], ["user", "assistant"])
        self.request("/api/feedback", {"message_id": s["messages"][-1]["id"], "rating": -1, "note": "具体例を増やして"})
        self.request("/api/chat", {"content": "次は？"})
        prompt = ModelFixture.requests[-1]["messages"][0]["content"]
        for text in ("回答は短めが好き", "提案書を書く", "具体例を増やして"):
            self.assertIn(text, prompt)
        self.assertEqual(len(ModelFixture.requests[-1]["messages"]), 4)

    def test_no_model_no_fabricated_chat(self):
        ModelFixture.ready = False
        code, _ = self.request("/api/chat", {"content": "こんにちは"})
        self.assertEqual(code, 503)
        self.assertEqual(self.app.state()["messages"], [])

    def test_failed_provider_request_does_not_save_reply(self):
        ModelFixture.fail = True
        code, _ = self.request("/api/chat", {"content": "こんにちは"})
        self.assertEqual(code, 502)
        self.assertEqual(self.app.state()["messages"], [])

    def test_cross_origin_post_is_rejected(self):
        code, _ = self.request("/api/tasks", {"title": "外部からの操作"}, "https://example.com")
        self.assertEqual(code, 403)
        self.assertEqual(self.app.state()["tasks"], [])

    def test_invalid_input_and_nonexistent_feedback(self):
        for route, body in (("/api/memories", {"content": ""}), ("/api/tasks", {"title": "a" * 1001}), ("/api/feedback", {"message_id": 999, "rating": 1})):
            self.assertEqual(self.request(route, body)[0], 400)

    def test_local_context_data_is_parameterized(self):
        content = "'); DROP TABLE memories; -- <script>alert(1)</script>"
        _, s = self.request("/api/memories", {"content": content})
        self.assertEqual(s["memories"][0]["content"], content)

    def test_procedure_activation_and_rollback(self):
        with self.app.database() as db:
            ids = [db.execute("INSERT INTO recipes(name,instructions,reason,checks,job_id) VALUES(?,?,?,?,?)", (f"版{i}", f"手順{i}", "理由", '["確認"]', 1)).lastrowid for i in (1, 2)]
        for recipe_id in ids:
            code, s = self.request("/api/recipes/activate", {"id": recipe_id})
            self.assertEqual(code, 200)
            self.assertEqual([r["id"] for r in s["recipes"] if r["active"]], [recipe_id])
        self.request("/api/recipes/activate", {"id": ids[0]})
        self.assertEqual([r["id"] for r in self.app.state()["recipes"] if r["active"]], [ids[0]])
        _, s = self.request("/api/recipes/reset", {})
        self.assertFalse(any(r["active"] for r in s["recipes"]))

    def test_disconnected_agent_does_not_claim_work(self):
        ModelFixture.ready = False
        code, _ = self.request("/api/jobs", {"goal": "自分で作業して"})
        self.assertEqual(code, 503)
        self.assertEqual(self.app.state()["jobs"], [])


if __name__ == "__main__":
    unittest.main()
