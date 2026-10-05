import json
import tempfile
import threading
import unittest
from pathlib import Path

import agent


class AgentTests(unittest.TestCase):
    def setUp(self):
        import server
        self.app = server
        self.temp = tempfile.TemporaryDirectory()
        self.old_data = server.DATA
        server.DATA = Path(self.temp.name)
        server.initialize()

    def tearDown(self):
        self.app.DATA = self.old_data
        self.temp.cleanup()

    def create_job(self):
        with self.app.database() as conn:
            return conn.execute("INSERT INTO jobs(goal,status) VALUES('最初の活動計画','queued')").lastrowid

    def run_agent(self, job_id):
        requests = []

        def completion(messages):
            requests.append(messages)
            if "実行計画" in messages[0]["content"]:
                return json.dumps({"steps": [{"tool": "calculate", "args": {"expression": "12*3"}}, {"tool": "write_draft", "args": {"title": "活動計画", "content": "まず現状を整理する。"}}, {"tool": "create_task", "args": {"title": "現状を整理する"}}]}, ensure_ascii=False)
            return json.dumps({"summary": "計算、下書き保存、タスク登録が完了。", "recipe": {"name": "具体的な初手", "instructions": "最初に実行できる小さなタスクを用意する。", "reason": "作業開始の迷いを減らす。", "checks": ["具体的な初手が1つあること"]}}, ensure_ascii=False)

        agent.run_job(job_id, self.app.database, self.app.DATA, completion, threading.Lock())
        return requests

    def test_execution_proposal_activation_and_next_run(self):
        first = self.create_job()
        self.run_agent(first)
        with self.app.database() as conn:
            job = conn.execute("SELECT * FROM jobs WHERE id=?", (first,)).fetchone()
            proposal = conn.execute("SELECT * FROM recipes").fetchone()
            self.assertEqual(job["status"], "completed")
            self.assertEqual(proposal["active"], 0)
            self.assertEqual(conn.execute("SELECT title FROM tasks").fetchone()["title"], "現状を整理する")
            result = json.loads(job["result"])
            self.assertEqual(result["actions"][0]["output"]["result"], 36)
            self.assertTrue((self.app.DATA / result["actions"][1]["output"]["file"]).is_file())
            conn.execute("UPDATE recipes SET active=1 WHERE id=?", (proposal["id"],))
        requests = self.run_agent(self.create_job())
        self.assertIn("最初に実行できる小さなタスク", requests[0][1]["content"])

    def test_unknown_tool_cannot_run(self):
        job_id = self.create_job()
        agent.run_job(job_id, self.app.database, self.app.DATA, lambda _: '{"steps":[{"tool":"shell","args":{"command":"touch pwned"}}]}', threading.Lock())
        with self.app.database() as conn:
            self.assertEqual(conn.execute("SELECT status FROM jobs").fetchone()["status"], "failed")
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM recipes").fetchone()[0], 0)

    def test_calculator_rejects_code_and_huge_operations(self):
        for expression in ("__import__('os').system('echo bad')", "2**10000000", "1/0", "1e300"):
            with self.assertRaises((ValueError, ZeroDivisionError)):
                agent.calculate(expression)

    def test_review_failure_preserves_real_outputs(self):
        job_id = self.create_job()
        calls = []

        def completion(_):
            calls.append(1)
            return '{"steps":[{"tool":"create_task","args":{"title":"保存される作業"}}]}' if len(calls) == 1 else 'not JSON'

        agent.run_job(job_id, self.app.database, self.app.DATA, completion, threading.Lock())
        with self.app.database() as conn:
            job = conn.execute("SELECT * FROM jobs").fetchone()
            self.assertEqual(job["status"], "completed")
            self.assertIn("review_error", json.loads(job["result"]))
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0], 1)
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM recipes").fetchone()[0], 0)

    def test_restart_marks_incomplete_job_interrupted(self):
        self.create_job()
        self.app.initialize()
        with self.app.database() as conn:
            self.assertEqual(conn.execute("SELECT status FROM jobs").fetchone()["status"], "interrupted")


if __name__ == "__main__":
    unittest.main()
