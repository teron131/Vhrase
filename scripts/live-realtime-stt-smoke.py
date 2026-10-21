#!/usr/bin/env python3
"""Exercise realtime STT with saved Vhrase Keychain credentials or environment fallbacks."""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import struct
import subprocess
import sys
import urllib.parse
from pathlib import Path

import websockets

SECURITY = "/usr/bin/security"
KEYCHAIN_SERVICE = "Vhrase"
ELEVENLABS_REALTIME_MODEL_ID = "scribe_v2_realtime"
PCM_FRAME_BYTES = 3_200


def key_value(name: str) -> str:
    result = subprocess.run(  # noqa: S603
        [
            SECURITY,
            "find-generic-password",
            "-s",
            KEYCHAIN_SERVICE,
            "-a",
            name,
            "-w",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode == 0 and (value := result.stdout.strip()):
        return value
    return os.environ.get(name, "")


def wav_pcm_data(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path} is not a WAV file")

    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(data):
            break
        if chunk_id == b"data":
            return data[chunk_start:chunk_end]
        offset = chunk_end + (chunk_size % 2)

    raise ValueError(f"{path} has no data chunk")


def pcm_frames(data: bytes):
    """Yield exact 100 ms PCM16 frames, padding the last frame with silence."""

    size = PCM_FRAME_BYTES
    for offset in range(0, len(data), size):
        frame = data[offset : offset + size]
        yield frame.ljust(size, b"\0")


def query_url(base_url: str, items: list[tuple[str, str]]) -> str:
    return f"{base_url}?{urllib.parse.urlencode(items)}"


def merge_incremental_text(existing: str, update: str) -> str:
    """Keep whichever xAI revision extends the other and join unrelated fragments with a space: ("Hello", "Hello world"), ("Hello world", "Hello"), and ("Hello", "world") all give "Hello world"."""

    if not existing:
        return update
    if not update or update == existing:
        return existing
    if update.startswith(existing):
        return update
    if existing.startswith(update):
        return existing
    return f"{existing} {update}"


def joined_xai_text(
    final_segments: list[str],
    locked_utterance: str,
    latest_partial: str,
) -> str:
    """Assemble the fallback transcript while keeping speech-final utterances distinct."""

    uncommitted = merge_incremental_text(locked_utterance, latest_partial)
    segments = [*final_segments]
    if uncommitted and segments[-1:] != [uncommitted]:
        segments.append(uncommitted)
    return " ".join(segments)


async def connect(url: str, headers: dict[str, str]):
    try:
        return await websockets.connect(url, additional_headers=headers)
    except TypeError:
        return await websockets.connect(url, extra_headers=headers)


async def send_pcm_binary(websocket, pcm: bytes):
    for chunk in pcm_frames(pcm):
        await websocket.send(chunk)
        await asyncio.sleep(0.1)


async def send_pcm_elevenlabs(websocket, pcm: bytes):
    for chunk in pcm_frames(pcm):
        await websocket.send(
            json.dumps(
                {
                    "message_type": "input_audio_chunk",
                    "audio_base_64": base64.b64encode(chunk).decode("ascii"),
                    "commit": False,
                    "sample_rate": 16000,
                }
            )
        )
        await asyncio.sleep(0.1)
    await websocket.send(
        json.dumps(
            {
                "message_type": "input_audio_chunk",
                "audio_base_64": "",
                "commit": True,
                "sample_rate": 16000,
            }
        )
    )


async def transcribe_xai(args: argparse.Namespace, pcm: bytes) -> str:
    api_key = key_value("XAI_API_KEY")
    if not api_key:
        raise RuntimeError("XAI_API_KEY is missing")

    query_items = [
        ("sample_rate", "16000"),
        ("encoding", "pcm"),
        ("interim_results", "true"),
    ]
    if language := args.language.strip():
        query_items.append(("language", language))
    query_items.extend(("keyterm", keyterm) for keyterm in args.keyterm)

    url = query_url("wss://api.x.ai/v1/stt", query_items)
    async with await connect(url, {"Authorization": f"Bearer {api_key}"}) as websocket:
        final_segments: list[str] = []
        locked_utterance = ""
        latest_partial = ""
        while True:
            event = json.loads(await asyncio.wait_for(websocket.recv(), timeout=20))
            if args.verbose:
                print(f"[xai] {event}", file=sys.stderr)
            event_type = event.get("type")
            if event_type == "transcript.created":
                await send_pcm_binary(websocket, pcm)
                await websocket.send(json.dumps({"type": "audio.done"}))
            elif event_type == "transcript.partial":
                text = event.get("text", "").strip()
                if not text:
                    continue
                if event.get("speech_final"):
                    if final_segments[-1:] != [text]:
                        final_segments.append(text)
                    locked_utterance = ""
                    latest_partial = ""
                elif event.get("is_final"):
                    locked_utterance = merge_incremental_text(locked_utterance, text)
                    latest_partial = ""
                else:
                    latest_partial = text
            elif event_type == "transcript.done":
                return event.get("text") or joined_xai_text(
                    final_segments,
                    locked_utterance,
                    latest_partial,
                )
            elif event_type == "error":
                raise RuntimeError(event.get("message", "xAI realtime error"))


async def transcribe_elevenlabs(args: argparse.Namespace, pcm: bytes) -> str:
    api_key = key_value("ELEVENLABS_API_KEY")
    if not api_key:
        raise RuntimeError("ELEVENLABS_API_KEY is missing")

    query_items = [
        ("model_id", ELEVENLABS_REALTIME_MODEL_ID),
        ("audio_format", "pcm_16000"),
        ("commit_strategy", args.elevenlabs_commit_strategy),
        ("no_verbatim", "true" if args.elevenlabs_no_verbatim else "false"),
        ("vad_silence_threshold_secs", str(args.elevenlabs_vad_silence_threshold)),
        ("vad_threshold", str(args.elevenlabs_vad_threshold)),
        ("min_speech_duration_ms", str(args.elevenlabs_min_speech_duration)),
        ("min_silence_duration_ms", str(args.elevenlabs_min_silence_duration)),
    ]
    if language := args.language.strip():
        query_items.append(("language_code", language))
    query_items.extend(("keyterms", keyterm) for keyterm in args.keyterm)

    url = query_url("wss://api.elevenlabs.io/v1/speech-to-text/realtime", query_items)
    async with await connect(url, {"xi-api-key": api_key}) as websocket:
        committed_segments: list[str] = []
        while True:
            timeout = 0.35 if committed_segments else 20
            try:
                message = await asyncio.wait_for(websocket.recv(), timeout=timeout)
            except asyncio.TimeoutError:
                return " ".join(committed_segments)
            event = json.loads(message)
            if args.verbose:
                print(f"[elevenlabs] {event}", file=sys.stderr)
            message_type = event.get("message_type")
            if message_type == "session_started":
                await send_pcm_elevenlabs(websocket, pcm)
            elif message_type in {
                "committed_transcript",
                "committed_transcript_with_timestamps",
            }:
                text = event.get("text", "").strip()
                if text and committed_segments[-1:] != [text]:
                    committed_segments.append(text)
            elif message_type in {
                "auth_error",
                "chunk_size_exceeded",
                "commit_throttled",
                "error",
                "input_error",
                "insufficient_audio_activity",
                "queue_overflow",
                "quota_exceeded",
                "rate_limited",
                "resource_exhausted",
                "session_time_limit_exceeded",
                "transcriber_error",
                "unaccepted_terms",
            }:
                detail = (
                    event.get("error")
                    or event.get("text")
                    or "ElevenLabs realtime error"
                )
                raise RuntimeError(f"{message_type}: {detail}")


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["xai", "elevenlabs"], required=True)
    parser.add_argument("--audio", required=True)
    parser.add_argument("--language", default="en")
    parser.add_argument("--keyterm", action="append", default=[])
    parser.add_argument("--expect")
    parser.add_argument(
        "--elevenlabs-commit-strategy",
        choices=["manual", "vad"],
        default="manual",
    )
    parser.add_argument("--elevenlabs-no-verbatim", action="store_true")
    parser.add_argument("--elevenlabs-vad-silence-threshold", type=float, default=1.5)
    parser.add_argument("--elevenlabs-vad-threshold", type=float, default=0.4)
    parser.add_argument("--elevenlabs-min-speech-duration", type=int, default=100)
    parser.add_argument("--elevenlabs-min-silence-duration", type=int, default=100)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    pcm = wav_pcm_data(Path(args.audio))
    if args.provider == "xai":
        text = await transcribe_xai(args, pcm)
    else:
        text = await transcribe_elevenlabs(args, pcm)

    text = text.strip()
    if not text:
        raise RuntimeError("provider returned an empty transcript")
    if args.expect and args.expect.lower() not in text.lower():
        raise RuntimeError(f"transcript did not include {args.expect!r}: {text}")

    print(f"Provider: {args.provider}")
    print("Mode: realtime")
    print(f"Transcript: {text}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:
        detail = str(exc) or exc.__class__.__name__
        print(f"live-realtime-stt-smoke: {detail}", file=sys.stderr)
        raise SystemExit(1) from None
