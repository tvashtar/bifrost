#!/usr/bin/env python3
"""Minimal local web UI for bifrost."""

import json
import subprocess
import os
from pathlib import Path

from flask import Flask, render_template, jsonify, request

app = Flask(__name__)
VAL_CMD = str(Path(__file__).resolve().parent.parent / "val")
GAMES = ["valheim", "minecraft", "7dtd", "enshrouded"]


def run_val(game, command, timeout=30):
    """Run a val CLI command and return (success, output)."""
    try:
        result = subprocess.run(
            [VAL_CMD, f"--game={game}", command],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)


@app.route("/")
def index():
    return render_template("index.html", games=GAMES)


@app.route("/api/status/<game>")
def status(game):
    """Get server status for a game."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400
    success, output = run_val(game, "status")
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
        success, output = run_val(game, "status")
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
    """Run an action (start/stop/backup) for a game."""
    if game not in GAMES:
        return jsonify({"error": "Unknown game"}), 400
    if action not in ("start", "stop", "backup"):
        return jsonify({"error": "Invalid action"}), 400

    # Start can take a long time (first boot downloads game files)
    timeout = 900 if action == "start" else 120
    success, output = run_val(game, action, timeout=timeout)
    return jsonify({"success": success, "output": output})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
