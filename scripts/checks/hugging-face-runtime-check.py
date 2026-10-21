"""Checks model reuse, replacement lifetime, and failed-load recovery through the helper's actual JSON request loop without downloading models."""

import gc
import importlib.util
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch
import weakref


def main() -> None:
    helper = (
        Path(__file__).resolve().parents[2]
        / "Sources/VhraseApp/Transcription/Local/HuggingFaceRuntime/asr.py"
    )
    spec = importlib.util.spec_from_file_location("asr", helper)
    assert spec is not None
    assert spec.loader is not None
    asr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(asr)
    references: list[weakref.ReferenceType] = []
    builds: list[str] = []

    class Recognizer:
        def __init__(self, model: str) -> None:
            self.model = model

    def build(model: str) -> Recognizer:
        assert not any(reference() is not None for reference in references), (
            "Previous model is still held while its replacement loads"
        )
        builds.append(model)
        if model == "broken/model":
            raise ValueError("Model could not load")
        recognizer = Recognizer(model)
        references.append(weakref.ref(recognizer))
        return recognizer

    requests = [
        {"op": "load", "model": "first/model"},
        {"op": "transcribe", "model": "first/model", "path": "recording.wav"},
        {"op": "load", "model": "second/model"},
        {"op": "load", "model": "second/model"},
        {"op": "load", "model": "broken/model"},
        {"op": "load", "model": "third/model"},
        {"op": "transcribe", "model": "third/model", "path": "recording.wav"},
    ]
    protocol = io.StringIO()
    with (
        patch.object(sys, "stdin", io.StringIO("\n".join(map(json.dumps, requests)))),
        patch.object(sys, "stderr", io.StringIO()),
        patch.object(asr, "build_recognizer", build),
        patch.object(asr, "release_model_memory", gc.collect),
        patch.object(asr, "runtime_description", lambda _: {}),
        patch.object(asr, "transcribe", lambda recognizer, *_: recognizer.model),
    ):
        assert asr.serve(protocol) == 0
    replies = [json.loads(line) for line in protocol.getvalue().splitlines()]
    assert [reply["ok"] for reply in replies] == [
        True,
        True,
        True,
        True,
        False,
        True,
        True,
    ], replies
    assert replies[1]["text"] == "first/model"
    assert replies[6]["text"] == "third/model"
    assert replies[4]["error"] == "Model could not load"
    assert builds == ["first/model", "second/model", "broken/model", "third/model"]
    assert not any(reference() is not None for reference in references)
    print("hugging face runtime model lifetime ok")


if __name__ == "__main__":
    main()
