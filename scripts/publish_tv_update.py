#!/usr/bin/env python3
"""Publish one verified release over stdin: a JSON line followed by APK bytes."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

PACKAGE = "com.kkkunny.blt.tcl.stability"
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
MANAGED_APK = re.compile(r"blt-ng-[0-9]+\.[0-9]+\.[0-9]+-armeabi-v7a\.apk")
MAX_SIZE = 300 * 1024 * 1024


def validate(record):
    version = record["version"]
    if (
        record["packageName"] != PACKAGE
        or not VERSION.fullmatch(version)
        or record["apk"] != f"blt-ng-{version}-armeabi-v7a.apk"
        or type(record["versionCode"]) is not int
        or record["versionCode"] <= 0
        or type(record["size"]) is not int
        or not 0 < record["size"] <= MAX_SIZE
        or not re.fullmatch(r"[0-9a-f]{64}", record["sha256"])
    ):
        raise ValueError("Invalid release metadata")
    return record


def write_json(path, record, staging):
    with tempfile.NamedTemporaryFile(dir=staging, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write((json.dumps(record, indent=2) + "\n").encode())
            output.flush()
            os.fchmod(output.fileno(), 0o644)
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def publish(root, staging, stream):
    header = stream.readline(8193)
    if len(header) > 8192 or not header.endswith(b"\n"):
        raise ValueError("Missing release metadata")
    incoming = validate(json.loads(header))

    with tempfile.NamedTemporaryFile(dir=staging) as payload:
        remaining = incoming["size"]
        digest = hashlib.sha256()
        while remaining:
            chunk = stream.read(min(remaining, 1024 * 1024))
            if not chunk:
                raise ValueError("Incomplete APK")
            payload.write(chunk)
            digest.update(chunk)
            remaining -= len(chunk)
        if stream.read(1) or digest.hexdigest() != incoming["sha256"]:
            raise ValueError("APK size or SHA-256 does not match metadata")
        payload.flush()
        os.fsync(payload.fileno())

        with (staging / "publish.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            publish_locked(root, staging, incoming, Path(payload.name))


def publish_locked(root, staging, incoming, payload):
    records = {}
    latest = root / "latest.json"
    sources = list(staging.glob("release-*.json"))
    if latest.exists():
        sources.append(latest)
    for path in sources:
        record = validate(json.loads(path.read_text()))
        apk = root / record["apk"]
        if not apk.is_file() or apk.stat().st_size != record["size"]:
            raise ValueError(f"Existing APK is missing or truncated: {apk.name}")
        code = record["versionCode"]
        if code in records and records[code] != record:
            raise ValueError("Existing release metadata conflicts")
        records[code] = record

    code = incoming["versionCode"]
    previous = records.get(code)
    if previous is not None and previous != incoming:
        raise ValueError("This Android version code already belongs to a different APK")
    if any(r["apk"] == incoming["apk"] and r != incoming for r in records.values()):
        raise ValueError("This release name already belongs to a different APK")

    records[code] = incoming
    keep = [records[key] for key in sorted(records, reverse=True)[:2]]
    if incoming in keep:
        destination = root / incoming["apk"]
        # The original staged file remains available for automatic cleanup.
        publish_path = payload.with_suffix(".publish")
        try:
            os.link(payload, publish_path)
            publish_path.chmod(0o644)
            os.replace(publish_path, destination)
        finally:
            publish_path.unlink(missing_ok=True)

    for record in keep:
        write_json(staging / f"release-{record['versionCode']}.json", record, staging)
    write_json(latest, keep[0], staging)

    kept_metadata = {f"release-{record['versionCode']}.json" for record in keep}
    for path in staging.glob("release-*.json"):
        if path.name not in kept_metadata:
            path.unlink()
    kept_names = {record["apk"] for record in keep}
    for path in root.iterdir():
        if MANAGED_APK.fullmatch(path.name) and path.name not in kept_names:
            path.unlink()
    print("Retained:", ", ".join(record["version"] for record in keep))


if __name__ == "__main__":
    publish(Path("/srv/blt-updates"), Path("/srv/blt-update-staging"), sys.stdin.buffer)
