#!/usr/bin/env python3
"""Build a pinned CPU runtime on macOS and verify official Qwen model files."""
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

LLAMA_COMMIT = "55a1c5a5fdefef808e95aabd3d5563af1068cc80"  # upstream b5808
CMAKE_NAME = "cmake-3.31.8-macos-universal.tar.gz"
CMAKE_SHA256 = "d1449f969c54d5c00886d5b643340d493dfb3c81cb39ee29b35453395c11ebf7"
MODEL_REPO = "Qwen/Qwen2.5-7B-Instruct-GGUF"
RUNTIME = Path.home() / "Library/Application Support/ORBIT/runtime"


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url, destination):
    temp = destination.with_name(destination.name + ".partial")
    # curl uses system HTTPS trust; no insecure flags or credential arguments.
    run("curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "20",
        "--output", temp, url)
    temp.replace(destination)


def verified_download(url, destination, expected):
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
        raise ValueError("配布元の SHA-256 が取得できませんでした。")
    expected = expected.lower()
    if destination.exists() and checksum(destination) == expected:
        print("検証済みファイルを再利用: " + destination.name, flush=True)
        return
    download(url, destination)
    if checksum(destination) != expected:
        destination.unlink()
        raise ValueError("チェックサムが一致しません。ファイルを使用せず削除しました。再実行してください。")


def model_files(metadata):
    revision = metadata.get("sha", "")
    if not re.fullmatch(r"[a-fA-F0-9]{40}", revision):
        raise ValueError("モデルの版を確認できませんでした。")
    selected = []
    for file in metadata.get("siblings", []):
        name = file.get("rfilename", "")
        if name.lower().startswith("qwen2.5-7b-instruct-q4_k_m") and name.lower().endswith(".gguf"):
            if Path(name).name != name or ".." in name:
                raise ValueError("モデルファイル名が不正です。")
            lfs = file.get("lfs", {})
            digest = lfs.get("sha256", lfs.get("oid", ""))
            if not re.fullmatch(r"[a-fA-F0-9]{64}", digest):
                raise ValueError("モデル配布元のチェックサムが取得できませんでした。")
            selected.append((name, digest))
    selected.sort()
    if not selected:
        raise ValueError("公式配布元で Q4_K_M モデルが見つかりませんでした。")
    # GGUF can be a single file or numbered shards; refuse a truncated file list.
    if len(selected) == 1 and not re.search(r"-\d{5}-of-\d{5}\.gguf$", selected[0][0]):
        return revision, selected
    total = len(selected)
    for i, (name, _) in enumerate(selected, 1):
        if not name.endswith(f"-{i:05d}-of-{total:05d}.gguf"):
            raise ValueError("モデルの分割ファイルが揃っていません。")
    return revision, selected


def prepare():
    if platform.system() != "Darwin":
        raise ValueError("この導入手順は Mac 用です。")
    run("xcrun", "--find", "clang")
    RUNTIME.mkdir(parents=True, exist_ok=True)
    cmake = shutil.which("cmake")
    if not cmake:
        archive = RUNTIME / CMAKE_NAME
        verified_download("https://github.com/Kitware/CMake/releases/download/v3.31.8/" + CMAKE_NAME,
                          archive, CMAKE_SHA256)
        cmake_path = RUNTIME / "cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake"
        if not cmake_path.is_file():
            run("tar", "-xzf", archive, "-C", RUNTIME)
        cmake = str(cmake_path)
    source = RUNTIME / "llama.cpp"
    if not source.exists():
        run("git", "clone", "--depth", "1", "--branch", "b5808", "https://github.com/ggml-org/llama.cpp.git", source)
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if actual != LLAMA_COMMIT:
        raise ValueError("AI 実行環境のソースが予定した版と異なります。既存ファイルを確認してください。")
    build = source / "build-orbit-cpu-compatible"
    binary = build / "bin/llama-server"
    if not binary.is_file():
        print("AI 実行環境をビルドしています…", flush=True)
        run(cmake, "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3",
            "-DGGML_NATIVE=OFF", "-DGGML_AVX=ON", "-DGGML_AVX2=ON",
            "-DGGML_FMA=ON", "-DGGML_F16C=ON", "-DGGML_AVX512=OFF",
            "-DGGML_AVX512_VBMI=OFF", "-DGGML_AVX512_VNNI=OFF", "-DGGML_AVX512_BF16=OFF",
            "-DGGML_METAL=OFF", "-DGGML_OPENMP=OFF", "-DLLAMA_CURL=OFF", "-DLLAMA_BUILD_TESTS=OFF")
        run(cmake, "--build", build, "--config", "Release", "--target", "llama-server", "-j", "4")
    model_dir = RUNTIME / "models"
    model_dir.mkdir(exist_ok=True)
    print("公式モデルの配布情報を確認しています…", flush=True)
    manifest = model_dir / "model-info.json"
    if not manifest.is_file():
        download("https://huggingface.co/api/models/" + MODEL_REPO + "?blobs=true", manifest)
    try:
        metadata = json.loads(manifest.read_text())
        revision, files = model_files(metadata)
    except (ValueError, TypeError, AttributeError):
        manifest.unlink()
        raise ValueError("モデルの配布情報を検証できませんでした。再実行すると再取得します。") from None
    print("モデルを取得・検証します。合計数 GB の初回ダウンロードです。", flush=True)
    for name, digest in files:
        url = "https://huggingface.co/" + MODEL_REPO + "/resolve/" + revision + "/" + urllib.parse.quote(name)
        verified_download(url, model_dir / name, digest)
    license_name = next((f["rfilename"] for f in metadata.get("siblings", []) if f.get("rfilename", "").upper() == "LICENSE"), None)
    if license_name and not (model_dir / "LICENSE").is_file():
        download("https://huggingface.co/" + MODEL_REPO + "/resolve/" + revision + "/" + license_name, model_dir / "LICENSE")
    return binary, model_dir / files[0][0]


if __name__ == "__main__":
    try:
        binary, model = prepare()
        print("無料のローカル AI を起動します。このターミナルは開いたままにしてください。", flush=True)
        os.execv(str(binary), [str(binary), "-m", str(model), "-c", "8192", "-t", "4", "--host", "127.0.0.1", "--port", "8080"])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("導入を完了できませんでした: " + str(error), file=sys.stderr)
        sys.exit(1)
