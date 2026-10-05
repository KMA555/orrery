import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import setup_local_ai as setup


class SetupTests(unittest.TestCase):
    def metadata(self, names):
        return {"sha": "a" * 40, "siblings": [{"rfilename": name, "lfs": {"sha256": "b" * 64}} for name in names]}

    def test_single_model_and_complete_shards(self):
        stem = "qwen2.5-7b-instruct-q4_k_m"
        self.assertEqual(len(setup.model_files(self.metadata([stem + ".gguf"]))[1]), 1)
        names = [stem + f"-{i:05d}-of-00002.gguf" for i in (2, 1)]
        self.assertTrue(setup.model_files(self.metadata(names))[1][0][0].endswith("00001-of-00002.gguf"))

    def test_incomplete_shards_missing_checksum_and_traversal_rejected(self):
        stem = "qwen2.5-7b-instruct-q4_k_m"
        cases = [self.metadata([stem + "-00001-of-00002.gguf"]), self.metadata([stem + "/../evil.gguf"]),
                 {"sha": "a" * 40, "siblings": [{"rfilename": stem + ".gguf"}]}]
        for metadata in cases:
            with self.assertRaises(ValueError):
                setup.model_files(metadata)

    def test_verified_reuse_and_checksum_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.gguf"
            path.write_bytes(b"verified")
            digest = setup.checksum(path)
            with patch.object(setup, "download") as download:
                setup.verified_download("https://example.com/model", path, digest)
                download.assert_not_called()
            path.write_bytes(b"corrupted")
            with patch.object(setup, "download", side_effect=lambda _, p: p.write_bytes(b"wrong")):
                with self.assertRaises(ValueError):
                    setup.verified_download("https://example.com/model", path, digest)
                self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
