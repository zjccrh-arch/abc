from __future__ import annotations

import argparse
import copy
import gzip
import io
import tarfile
from pathlib import Path


def read_ar_members(package: Path) -> list[tuple[str, bytes]]:
    raw = package.read_bytes()
    if raw[:8] != b"!<arch>\n":
        raise ValueError(f"{package} is not an ar archive")

    members: list[tuple[str, bytes]] = []
    offset = 8
    while offset < len(raw):
        header = raw[offset : offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError(f"malformed ar member in {package}")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58])
        offset += 60
        members.append((name, raw[offset : offset + size]))
        offset += size + (size & 1)
    return members


def write_ar_members(package: Path, members: list[tuple[str, bytes]]) -> None:
    output = bytearray(b"!<arch>\n")
    for name, data in members:
        encoded_name = f"{name}/".encode("ascii")
        if len(encoded_name) > 16:
            raise ValueError(f"ar member name too long: {name}")
        header = (
            encoded_name.ljust(16, b" ")
            + b"0".ljust(12, b" ")
            + b"0".ljust(6, b" ")
            + b"0".ljust(6, b" ")
            + b"100644".ljust(8, b" ")
            + str(len(data)).encode("ascii").ljust(10, b" ")
            + b"`\n"
        )
        output.extend(header)
        output.extend(data)
        if len(data) & 1:
            output.extend(b"\n")
    package.write_bytes(output)


def rewrite_control_archive(archive: bytes, architecture: str) -> bytes:
    source = tarfile.open(fileobj=io.BytesIO(archive), mode="r:*")
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as gzip_file:
        with tarfile.open(fileobj=gzip_file, mode="w") as target:
            for member in source.getmembers():
                copied = copy.copy(member)
                payload = source.extractfile(member).read() if member.isfile() else None
                if member.isfile() and member.name.endswith("control"):
                    text = payload.decode("utf-8")
                    lines = [line for line in text.splitlines() if not line.lower().startswith("architecture:")]
                    payload = ("\n".join(lines) + f"\nArchitecture: {architecture}\n").encode("utf-8")
                    copied.size = len(payload)
                target.addfile(copied, io.BytesIO(payload) if payload is not None else None)
    return buffer.getvalue()


def package_architecture(package: Path) -> str:
    members = read_ar_members(package)
    control_archive = next(data for name, data in members if name.startswith("control.tar"))
    with tarfile.open(fileobj=io.BytesIO(control_archive), mode="r:*") as control:
        control_file = next(member for member in control.getmembers() if member.isfile() and member.name.endswith("control"))
        for line in control.extractfile(control_file).read().decode("utf-8").splitlines():
            if line.lower().startswith("architecture:"):
                return line.split(":", 1)[1].strip()
    raise ValueError("control file has no Architecture field")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("architecture")
    args = parser.parse_args()

    members = read_ar_members(args.package)
    rewritten = []
    for name, data in members:
        rewritten.append(("control.tar.gz", rewrite_control_archive(data, args.architecture)) if name.startswith("control.tar") else (name, data))
    write_ar_members(args.package, rewritten)
    actual = package_architecture(args.package)
    if actual != args.architecture:
        raise SystemExit(f"expected {args.architecture}, got {actual}")
    print(f"{args.package.name}: Architecture={actual}")


if __name__ == "__main__":
    main()
