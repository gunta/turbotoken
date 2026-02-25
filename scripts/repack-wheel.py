#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import shutil
import tempfile
import zipfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Repack a wheel with bundled native library and new platform tag.")
    parser.add_argument("--base-wheel", required=True)
    parser.add_argument("--output-wheel", required=True)
    parser.add_argument("--lib-source", required=True)
    parser.add_argument("--lib-dest", required=True)
    parser.add_argument("--wheel-tag", required=True)
    return parser.parse_args()


def sha256_record(path: Path) -> tuple[str, str]:
    payload = path.read_bytes()
    digest = hashlib.sha256(payload).digest()
    encoded = base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")
    return f"sha256={encoded}", str(len(payload))


def update_wheel_tag(wheel_file: Path, wheel_tag: str) -> None:
    lines = wheel_file.read_text(encoding="utf-8").splitlines()
    kept: list[str] = []
    for line in lines:
        if line.startswith("Tag: "):
            continue
        if line.startswith("Root-Is-Purelib: "):
            kept.append("Root-Is-Purelib: false")
            continue
        kept.append(line)
    kept.append(f"Tag: py3-none-{wheel_tag}")
    wheel_file.write_text("\n".join(kept) + "\n", encoding="utf-8")


def write_record(root: Path, dist_info: Path) -> None:
    record_path = dist_info / "RECORD"
    rows: list[list[str]] = []

    files = sorted(path for path in root.rglob("*") if path.is_file())
    for file_path in files:
        rel = file_path.relative_to(root).as_posix()
        if rel == record_path.relative_to(root).as_posix():
            continue
        hash_value, size = sha256_record(file_path)
        rows.append([rel, hash_value, size])

    rows.append([record_path.relative_to(root).as_posix(), "", ""])
    with record_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def pack_wheel(root: Path, output_wheel: Path) -> None:
    output_wheel.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_wheel, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file_path in sorted(path for path in root.rglob("*") if path.is_file()):
            archive.write(file_path, file_path.relative_to(root).as_posix())


def main() -> int:
    args = parse_args()
    base_wheel = Path(args.base_wheel).resolve()
    output_wheel = Path(args.output_wheel).resolve()
    lib_source = Path(args.lib_source).resolve()
    lib_dest = Path(args.lib_dest)

    if not base_wheel.exists():
        raise FileNotFoundError(f"base wheel does not exist: {base_wheel}")
    if not lib_source.exists():
        raise FileNotFoundError(f"native library does not exist: {lib_source}")

    with tempfile.TemporaryDirectory(prefix="turbotoken-wheel-") as tmp:
        work = Path(tmp) / "work"
        work.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(base_wheel, "r") as archive:
            archive.extractall(work)

        dist_infos = sorted(work.glob("*.dist-info"))
        if len(dist_infos) != 1:
            raise RuntimeError(f"expected exactly one .dist-info directory, found {len(dist_infos)}")
        dist_info = dist_infos[0]

        update_wheel_tag(dist_info / "WHEEL", args.wheel_tag)

        target_lib_path = work / lib_dest
        target_lib_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(lib_source, target_lib_path)

        write_record(work, dist_info)
        pack_wheel(work, output_wheel)

    print(str(output_wheel))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
