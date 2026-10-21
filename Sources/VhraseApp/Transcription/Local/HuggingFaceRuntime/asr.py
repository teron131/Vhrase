# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "huggingface-hub>=2.2.0",
#     "librosa>=1.0.0",
#     "numpy>=2.5.1",
#     "torch>=2.14.1",
#     "transformers>=5.19.0",
# ]
# ///
"""Runs Hugging Face speech recognition for Vhrase: any model the transformers automatic-speech-recognition (ASR) pipeline accepts, on the Apple GPU or the CPU.

Vhrase starts this script through uv, which builds the Python environment from the dependencies above the first time.
After changing them, run `uv lock --script` on this file, because uv cannot update the lockfile inside the signed app.
`download MODEL` fetches a model into the cache named by HF_HUB_CACHE and proves it runs on this machine; `serve` keeps one model loaded and transcribes recordings on request.
Vhrase sets HF_HUB_DISABLE_SHARED_BLOBS, so each model's files stay inside its own cache folder, which is what progress measures and what removing a model deletes.
Both write JSON lines to standard output, and everything a library prints goes to standard error so it cannot corrupt that stream.
The heavy libraries are imported inside the functions that need them, so a malformed command fails before paying for them.
"""

from __future__ import annotations

import gc
import json
import os
from pathlib import Path
import re
import sys
import threading
import traceback
from typing import TYPE_CHECKING, Any, TextIO
import wave

if TYPE_CHECKING:
    import numpy as np

SAMPLE_RATE = 16_000
# The pipeline's own chunking is right for Whisper and CTC models but repeats text for Parakeet, and without it Whisper refuses long audio and Parakeet stalls.
# Pieces under Whisper's 30-second window were correct for all three model families in youtube-toolkit, where this splitting comes from.
MAX_PIECE_SECONDS = 28
# How far back from a piece's length limit to look for the quietest moment to cut at.
CUT_SEARCH_SECONDS = 5
PROGRESS_INTERVAL_SECONDS = 0.5
ERROR_MESSAGE_LIMIT = 300
# transformers loads safetensors weights when a repository has them and PyTorch weights otherwise, as one file or as shards such as `model-00001-of-00002.safetensors`; other frameworks' copies are never fetched.
SAFETENSORS_WEIGHTS = re.compile(r"model(-\d+-of-\d+)?\.safetensors")
PYTORCH_WEIGHTS = re.compile(r"pytorch_model(-\d+-of-\d+)?\.bin")
SMALL_FILE_SUFFIXES = (".json", ".txt", ".model")


def main() -> int:
    match sys.argv[1:]:
        case ["download", model]:
            return download(model, claim_protocol_stream())
        case ["serve"]:
            return serve(claim_protocol_stream())
        case _:
            sys.stderr.write("usage: asr.py download MODEL | serve\n")
            return 2


def claim_protocol_stream() -> TextIO:
    """Keep the real standard output for JSON lines and point file descriptor 1 at standard error, so nothing a library prints can interleave with them."""
    protocol = os.fdopen(os.dup(1), "w", encoding="utf-8")
    os.dup2(2, 1)
    return protocol


def emit(protocol: TextIO, **message: Any) -> None:
    """Write one JSON line to Vhrase, ending this process when Vhrase has gone away.

    A closed pipe is the only sign that the app quit, and a download must not carry on for minutes with no one to report to.
    """
    try:
        protocol.write(json.dumps(message) + "\n")
        protocol.flush()
    except BrokenPipeError:
        os._exit(1)


def download(model: str, protocol: TextIO) -> int:
    """Fetch a model by building its pipeline, then run one second of silence through it.

    transformers chooses the files, so every model the pipeline accepts downloads the same way it would load.
    Any failure, from an unknown model ID to a model that is not a speech recognizer, ends as one `error` event carrying the library's first line.
    """
    import numpy as np

    finished = threading.Event()
    watcher = threading.Thread(
        target=report_download_progress,
        args=(model, protocol, finished),
        daemon=True,
    )
    watcher.start()
    try:
        try:
            recognizer = build_recognizer(model)
        finally:
            finished.set()
            watcher.join()
        emit(protocol, event="preparing")
        recognizer(
            {
                "raw": np.zeros(SAMPLE_RATE, dtype=np.float32),
                "sampling_rate": SAMPLE_RATE,
            }
        )
    except Exception as error:
        # The process boundary turns every library failure into one reported event; the traceback goes to standard error.
        traceback.print_exc()
        emit(protocol, event="error", message=first_line(error))
        return 1
    emit(protocol, event="installed", **runtime_description(recognizer))
    return 0


def serve(protocol: TextIO) -> int:
    """Answer one JSON request per line until standard input closes, which is both how Vhrase stops the server and how the server learns Vhrase is gone.

    Each request names its model, so the server holds whichever one was asked for last and releases the previous one first.
    """
    model: str | None = None
    recognizer = None
    for line in sys.stdin:
        request = json.loads(line)
        try:
            if recognizer is None or model != request["model"]:
                # Drop the pipeline itself before loading another; a second local reference would keep the previous model alive.
                recognizer = None
                release_model_memory()
                recognizer = build_recognizer(request["model"])
                model = request["model"]
            if request["op"] == "transcribe":
                text = transcribe(
                    recognizer, Path(request["path"]), request.get("language")
                )
                emit(protocol, ok=True, text=text)
            else:
                emit(protocol, ok=True, **runtime_description(recognizer))
        except Exception as error:
            # One failed request must not end the server; the reply carries the failure and the traceback goes to standard error.
            traceback.print_exc()
            emit(protocol, ok=False, error=first_line(error))
    return 0


def build_recognizer(model: str) -> Any:
    """transformers downloads whatever is not in the cache yet, unless HF_HUB_OFFLINE forbids it, in which case a missing file is an error."""
    import torch
    from transformers import pipeline
    from transformers.utils import logging as transformers_logging

    transformers_logging.set_verbosity_error()
    if torch.cuda.is_available():
        device = "cuda"
    elif torch.backends.mps.is_available():
        device = "mps"
    else:
        device = "cpu"
    # GPUs run half precision fastest and in half the memory; CPUs need full precision.
    dtype = torch.float32 if device == "cpu" else torch.float16
    return pipeline(
        "automatic-speech-recognition", model=model, device=device, dtype=dtype
    )


def release_model_memory() -> None:
    """Return a dropped model's memory to the system before the next one loads, so two large models are never held at once."""
    import torch

    gc.collect()
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()


def runtime_description(recognizer: Any) -> dict[str, str]:
    return {
        "device": str(recognizer.device),
        "precision": str(recognizer.model.dtype).removeprefix("torch."),
    }


def transcribe(recognizer: Any, audio_path: Path, language: str | None) -> str:
    """Pieces run one at a time: batching them on an Apple GPU returned truncated text."""
    pieces = split_at_quiet_points(read_recording(audio_path))
    results = recognizer(
        [{"raw": piece, "sampling_rate": SAMPLE_RATE} for piece in pieces],
        **whisper_language_options(recognizer, language),
    )
    return " ".join(text for result in results if (text := result["text"].strip()))


def whisper_language_options(recognizer: Any, language: str | None) -> dict[str, Any]:
    """Pass a language hint only to multilingual Whisper models; other architectures detect the language themselves and reject the option.

    Whisper's temperature fallback stays off: in transformers 5.19 it raised an internal error on a degenerate clip and still returned "Thank you." for silence.
    """
    model = recognizer.model
    is_multilingual_whisper = model.config.model_type == "whisper" and getattr(
        model.generation_config, "is_multilingual", False
    )
    if not language or not is_multilingual_whisper:
        return {}
    return {"generate_kwargs": {"language": language}}


def read_recording(audio_path: Path) -> np.ndarray:
    """Read Vhrase's recording format, 16 kHz mono 16-bit PCM WAV, as the float samples speech models take."""
    import numpy as np

    with wave.open(str(audio_path), "rb") as recording:
        audio_format = (
            recording.getframerate(),
            recording.getnchannels(),
            recording.getsampwidth(),
        )
        if audio_format != (SAMPLE_RATE, 1, 2):
            raise ValueError("The recording is not 16 kHz mono 16-bit PCM WAV")
        frames = recording.readframes(recording.getnframes())
    samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768
    if not len(samples):
        raise ValueError("The recording is empty")
    return samples


def split_at_quiet_points(
    samples: np.ndarray, *, max_seconds: int = MAX_PIECE_SECONDS
) -> list[np.ndarray]:
    """Cut audio into consecutive pieces no longer than max_seconds without splitting words.

    Each cut lands on the quietest tenth of a second in the last few seconds before the limit, which is usually a pause between sentences.
    Pieces do not overlap, so their transcripts join without any merging.
    """
    limit = max_seconds * SAMPLE_RATE
    search_window = CUT_SEARCH_SECONDS * SAMPLE_RATE
    frame = SAMPLE_RATE // 10
    pieces: list[np.ndarray] = []
    start = 0
    while len(samples) - start > limit:
        search_start = start + limit - search_window
        loudness = abs(samples[search_start : start + limit]).reshape(-1, frame)
        quietest_frame = int(loudness.mean(axis=1).argmin())
        cut = search_start + quietest_frame * frame + frame // 2
        pieces.append(samples[start:cut])
        start = cut
    pieces.append(samples[start:])
    return pieces


def report_download_progress(
    model: str, protocol: TextIO, finished: threading.Event
) -> None:
    """Emit the fraction of the expected download that has reached the cache, until the pipeline is built.

    Nothing is emitted for a model whose size cannot be estimated, which leaves Vhrase showing progress without a percentage.
    """
    expected = expected_download_bytes(model)
    if not expected:
        return
    while not finished.wait(PROGRESS_INTERVAL_SECONDS):
        # The last percent belongs to loading, so a finished transfer never reads as a finished setup.
        fraction = min(cached_bytes(model) / expected, 0.99)
        emit(protocol, event="progress", fraction=fraction)


def expected_download_bytes(model: str) -> int | None:
    """Estimate what transformers will fetch for a model from the repository's file list.

    Progress is cosmetic, so any failure to reach or read the list yields no estimate; building the pipeline reports the real problem.
    """
    from huggingface_hub import HfApi

    try:
        siblings = HfApi().model_info(model, files_metadata=True).siblings or []
    except Exception:
        return None
    sizes = {
        file.rfilename: file.size or 0 for file in siblings if "/" not in file.rfilename
    }
    weights = [name for name in sizes if SAFETENSORS_WEIGHTS.fullmatch(name)] or [
        name for name in sizes if PYTORCH_WEIGHTS.fullmatch(name)
    ]
    if not weights:
        return None
    small_files = [name for name in sizes if name.endswith(SMALL_FILE_SUFFIXES)]
    return sum(sizes[name] for name in {*weights, *small_files})


def cached_bytes(model: str) -> int:
    """Measure how much of a model has been written to the Hub cache, including files still downloading."""
    from huggingface_hub.constants import HF_HUB_CACHE

    blobs = Path(HF_HUB_CACHE) / f"models--{model.replace('/', '--')}" / "blobs"
    total = 0
    for blob in blobs.glob("*"):
        try:
            total += blob.stat().st_size
        except FileNotFoundError:
            # A finished file is renamed from its partial name between the listing and the measurement.
            continue
    return total


def first_line(error: Exception) -> str:
    """Reduce a library error to the opening worth showing beside a setting; some first lines run to a list of a hundred languages."""
    lines = str(error).strip().splitlines()
    return lines[0][:ERROR_MESSAGE_LIMIT] if lines else type(error).__name__


if __name__ == "__main__":
    raise SystemExit(main())
