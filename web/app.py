#!/usr/bin/env python3
"""Minimal local web UI for bifrost."""

import json
import re
import subprocess
from pathlib import Path

from flask import Flask, Response, render_template, jsonify, request

app = Flask(__name__)
BIFROST_CMD = str(Path(__file__).resolve().parent.parent / "bifrost")
GAMES = ["valheim", "minecraft", "7dtd", "enshrouded"]


def run_bifrost(game, command, timeout=30):
    """Run a bifrost CLI command and return (success, output)."""
    try:
        result = subprocess.run(
            [BIFROST_CMD, f"--game={game}", command],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)


def stream_bifrost(game, action):
    """Run a bifrost CLI command and yield output as SSE lines."""
    process = subprocess.Popen(
        [BIFROST_CMD, f"--game={game}", action],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    for line in process.stdout:
        yield f"data: {line.rstrip()}\n\n"

    process.wait()
    success = process.returncode == 0
    yield f"event: done\ndata: {json.dumps({'success': success})}\n\n"


@app.route("/")
def index():
    return render_template("index.html", games=GAMES)


@app.route("/api/status/<game>")
def status(game):
    """Get server status for a game."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400
    success, output = run_bifrost(game, "status")
    if success:
        try:
            return jsonify(json.loads(output.strip()))
        except json.JSONDecodeError:
            return jsonify({"status": "unknown", "raw": output})
    return jsonify({"status": "error", "message": output})


@app.route("/api/status")
def status_all():
    """Get status for all games."""
    results = {}
    for game in GAMES:
        success, output = run_bifrost(game, "status")
        if success:
            try:
                results[game] = json.loads(output.strip())
            except json.JSONDecodeError:
                results[game] = {"status": "unknown"}
        else:
            results[game] = {"status": "error"}
    return jsonify(results)


@app.route("/api/<game>/<action>", methods=["POST"])
def action(game, action):
    """Run an action (start/stop/backup) and stream output as SSE."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400
    if action not in ("start", "stop", "backup", "update"):
        return jsonify({"error": "Invalid action"}), 400

    return Response(
        stream_bifrost(game, action),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


def stream_modifiers(game, flags):
    """Run update-modifiers with flags, auto-confirming the prompt."""
    cmd = [BIFROST_CMD, f"--game={game}", "update-modifiers"] + flags
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    # Auto-confirm the "Continue? (y/n)" prompt
    process.stdin.write("y\n")
    process.stdin.flush()
    process.stdin.close()

    for line in process.stdout:
        yield f"data: {line.rstrip()}\n\n"

    process.wait()
    success = process.returncode == 0
    yield f"event: done\ndata: {json.dumps({'success': success})}\n\n"


@app.route("/api/<game>/modifiers")
def get_modifiers(game):
    """Get current world modifiers via update-modifiers --list."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400

    try:
        result = subprocess.run(
            [BIFROST_CMD, f"--game={game}", "update-modifiers", "--list"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout + result.stderr
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    modifiers = {}
    for key in ("combat", "deathpenalty", "resources", "raids", "portals"):
        match = re.search(rf"(?i){key}:\s*(\S+)", output)
        if match:
            val = match.group(1).lower()
            if val != "default":
                modifiers[key] = val

    return jsonify(modifiers)


@app.route("/api/<game>/update-modifiers", methods=["POST"])
def update_modifiers(game):
    """Run update-modifiers with selected modifier flags."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400

    data = request.get_json() or {}
    flags = []
    for key in ("combat", "deathpenalty", "resources", "raids", "portals", "preset"):
        val = data.get(key)
        if val:
            flags.append(f"--{key}={val}")

    if data.get("reset"):
        flags = ["--reset"]

    if not flags:
        return jsonify({"error": "No modifiers specified"}), 400

    return Response(
        stream_modifiers(game, flags),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
