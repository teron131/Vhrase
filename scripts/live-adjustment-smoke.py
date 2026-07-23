#!/usr/bin/env python3
"""Exercise LLM adjustment with a saved Vhrase Keychain credential or environment fallback."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_BASE_URL = "https://ai-gateway.vercel.sh/v1"
DEFAULT_MODEL = "xai/grok-4.3"
DEFAULTS = "/usr/bin/defaults"
SCREENCAPTURE = "/usr/sbin/screencapture"
SECURITY = "/usr/bin/security"
KEYCHAIN_SERVICE = "Vhrase"


def defaults_value(key: str) -> str:
    result = subprocess.run(  # noqa: S603
        [DEFAULTS, "read", "local.codex.Vhrase", key],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


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


def config_value(
    *,
    cli_value: str | None,
    env_name: str,
    defaults_key: str,
    fallback: str,
) -> str:
    if cli_value:
        return cli_value
    if value := os.environ.get(env_name):
        return value
    if value := defaults_value(defaults_key):
        return value
    return fallback


def capture_screenshot(cache_dir: Path) -> str | None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / "screen.png"
    result = subprocess.run(  # noqa: S603
        [SCREENCAPTURE, "-x", str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0 or not path.exists() or path.stat().st_size == 0:
        return None
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def endpoint(base_url: str, path: str) -> str:
    return f"{base_url.rstrip('/')}/{path.lstrip('/')}"


def open_json_request(request: urllib.request.Request, *, timeout: int) -> dict:
    if urllib.parse.urlparse(request.full_url).scheme != "https":
        raise ValueError(f"refusing non-HTTPS URL: {request.full_url}")
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def request_chat_adjustment(
    *,
    api_key: str,
    base_url: str,
    model: str,
    transcript: str,
    prompt: str,
    keyterms: list[str],
    screenshot_data_url: str | None,
) -> str:
    prompt_parts = [prompt]
    if keyterms:
        prompt_parts.append("Preferred vocabulary spellings:\n" + "\n".join(keyterms))
    prompt_text = "\n\n".join(prompt_parts)

    content = []
    if screenshot_data_url:
        content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": screenshot_data_url,
                    "detail": "high",
                },
            }
        )
    content.append(
        {
            "type": "text",
            "text": f"{prompt_text}\n\nTranscript:\n{transcript}",
        }
    )
    payload = {
        "model": model,
        "reasoning_effort": "low",
        "messages": [
            {
                "role": "user",
                "content": content,
            }
        ],
        "stream": False,
    }

    request = urllib.request.Request(  # noqa: S310
        endpoint(base_url, "chat/completions"),
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        data = open_json_request(request, timeout=60)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc

    texts = []
    for choice in data.get("choices", []):
        message = choice.get("message") or {}
        text = message.get("content")
        if text:
            texts.append(text)
    return "\n".join(texts).strip()


def list_models(
    *,
    api_key: str,
    base_url: str,
) -> list[str]:
    request = urllib.request.Request(  # noqa: S310
        endpoint(base_url, "models"),
        headers={"Authorization": f"Bearer {api_key}"},
        method="GET",
    )
    try:
        data = open_json_request(request, timeout=30)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc

    return [item.get("id", "") for item in data.get("data", []) if item.get("id")]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--transcript",
        default="please send this custom dictation demo to open AI and x AI using eleven labs",
    )
    parser.add_argument("--base-url")
    parser.add_argument("--model")
    parser.add_argument(
        "--prompt",
        default=(
            "Rewrite the transcript into polished prose. Fix obvious speech-to-text mistakes, "
            "punctuation, casing, and product names. Use the screenshot only as context. "
            "Return only the final text."
        ),
    )
    parser.add_argument("--expect", default="OpenAI")
    parser.add_argument("--keyterm", action="append", default=[])
    parser.add_argument("--no-screenshot", action="store_true")
    parser.add_argument("--require-screenshot", action="store_true")
    parser.add_argument("--list-models", action="store_true")
    args = parser.parse_args()

    api_key = key_value("LLM_API_KEY")
    if not api_key:
        raise RuntimeError("LLM API key is missing")

    base_url = config_value(
        cli_value=args.base_url,
        env_name="VHRASE_LLM_BASE_URL",
        defaults_key="adjustmentBaseURL",
        fallback=DEFAULT_BASE_URL,
    )
    model = config_value(
        cli_value=args.model,
        env_name="VHRASE_LLM_MODEL",
        defaults_key="adjustmentModel",
        fallback=DEFAULT_MODEL,
    )

    if args.list_models:
        models = list_models(api_key=api_key, base_url=base_url)
        if not models:
            raise RuntimeError("LLM endpoint returned no models for this API key")
        for model_id in models:
            print(model_id)
        return 0

    screenshot_data_url = None
    if not args.no_screenshot:
        screenshot_data_url = capture_screenshot(Path(".cache/live-adjustment-smoke"))
        if args.require_screenshot and not screenshot_data_url:
            raise RuntimeError("screenshot capture failed")

    text = request_chat_adjustment(
        api_key=api_key,
        base_url=base_url,
        model=model,
        transcript=args.transcript,
        prompt=args.prompt,
        keyterms=args.keyterm,
        screenshot_data_url=screenshot_data_url,
    )

    if not text:
        raise RuntimeError("LLM endpoint returned an empty adjustment")
    if args.expect and args.expect.lower() not in text.lower():
        raise RuntimeError(f"adjustment did not include {args.expect!r}: {text}")

    print(f"Base URL: {base_url}")
    print(f"Model: {model}")
    print(f"Screenshot: {'included' if screenshot_data_url else 'not included'}")
    print(f"Adjusted: {text}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"live-adjustment-smoke: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
