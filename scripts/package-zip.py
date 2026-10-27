#!/usr/bin/env python3
"""Create a verified app ZIP with mandatory UTF-8 Release Notes.txt alongside the app."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]


def read_notes(path):
    text = Path(path).read_text(encoding="utf-8")
    header = re.compile(r"^(\d{4}-\d{2}-\d{2}) \(([1-9]\d*)차 배포\)$")
    previous = {}; active = None; count = 0
    for line in text.splitlines():
        if not line.strip():
            continue
        match = header.fullmatch(line)
        if match:
            if active is not None and count == 0:
                raise ValueError("Each release needs at least one change bullet")
            date, number = match[1], int(match[2])
            datetime.date.fromisoformat(date)
            if active is not None and date > active[0]:
                raise ValueError("Release dates must appear newest first")
            if date in previous and number >= previous[date]:
                raise ValueError("Release numbers must appear in descending order within each date")
            previous[date] = number; active = (date, number); count = 0
        elif active is not None and line.startswith("- ") and line[2:].strip():
            count += 1
        else:
            raise ValueError("Use 'YYYY-MM-DD (N차 배포)' followed only by '- 변경사항' bullets")
    if active is None or count == 0:
        raise ValueError("Release notes require a dated release and at least one change bullet")
    return text.rstrip() + "\n"


def package_zip(app, notes, output):
    app, output = Path(app).resolve(), Path(output).resolve()
    text = read_notes(notes)
    if output.suffix.lower() != ".zip":
        raise ValueError("Output must be a .zip file")
    if output.exists():
        raise FileExistsError(f"Output already exists: {output}")
    if app in output.parents:
        raise ValueError("Output ZIP cannot be inside the app")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    executable_sha = hashlib.sha256(executable.read_bytes()).hexdigest()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    now = datetime.datetime.now(ZoneInfo("Asia/Seoul")).isoformat(timespec="seconds")
    metadata = {"archive": output.name, "version": version, "packagedAt": now,
                "timezone": "Asia/Seoul", "sourceHEAD": revision, "workingTreeModified": dirty,
                "executableSHA256": executable_sha}
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".ptb-package-", suffix=".zip", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary)
    temporary.unlink()
    try:
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(temporary)], check=True)
        with zipfile.ZipFile(temporary, "a", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Release Notes.txt", text.encode("utf-8"))
            archive.writestr("Release Metadata.json", json.dumps(metadata, ensure_ascii=False, indent=2).encode("utf-8"))
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("ZIP integrity check failed")
            if archive.read("Release Notes.txt").decode("utf-8") != text:
                raise ValueError("Release notes verification failed")
            packaged = archive.read(f"{app.name}/Contents/MacOS/{info['CFBundleExecutable']}")
            if hashlib.sha256(packaged).hexdigest() != executable_sha:
                raise ValueError("Packaged executable differs from the built app")
        # Same-directory hard-link publication is atomic and refuses an existing destination.
        os.link(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    return {"path": str(output), "version": version, "packagedAt": now,
            "bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="build/PokeTokenBar.app")
    parser.add_argument("--notes", required=True, help="Finished UTF-8 release notes; required for every ZIP")
    parser.add_argument("--output")
    parser.add_argument("--check-notes", action="store_true", help="Validate note format without creating an archive")
    args = parser.parse_args()
    try:
        if args.check_notes:
            read_notes(args.notes)
            print("Release note format verified")
            return
        if not args.output:
            parser.error("--output is required for packaging")
        print(json.dumps(package_zip(args.app, args.notes, args.output), ensure_ascii=False))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"ZIP packaging: {error}\n")


if __name__ == "__main__":
    main()
