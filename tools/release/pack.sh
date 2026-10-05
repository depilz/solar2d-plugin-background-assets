#!/bin/bash
# Deterministic data.tgz packer: the same tree and epoch give the same bytes.
# usage: tools/release/pack.sh --mtime EPOCH TREE OUT [MEMBER...]
# Packs the MEMBERs (paths relative to TREE; a directory packs recursively) or, with none, everything in TREE into OUT.
# Output: gzip'd USTAR, entries sorted by path with no leading ./, uid/gid 0, empty owner and group names, every mtime
# EPOCH; gzip level 9, header mtime 0, no file name.
# Modes: directories 0755, .so/.dylib 0755, other files 0644; every entry 0755 when the packed set holds a directory.
# Skips ._* entries. Exits 2, writing nothing, on a usage error, a symlink or other non-regular entry, a member outside
# TREE, or an OUT equal to or inside a packed member.
set -uo pipefail

usage() { sed -n '3,9s/^# //p' "$0"; }

[[ "${1:-}" == --help || "${1:-}" == -h ]] && { usage; exit 0; }
[[ $# -ge 4 && "$1" == --mtime ]] || { usage >&2; exit 2; }

exec python3 - "$2" "$3" "$4" "${@:5}" <<'PY'
import gzip, io, os, stat, sys, tarfile

def fail(message):
    print(f"pack.sh: {message}", file=sys.stderr)
    sys.exit(2)

def inside(path, root):
    return path == root or path.startswith(root + os.sep)

def check_member(tree_real, rel):
    if os.path.isabs(rel) or os.path.normpath(rel).split(os.sep)[0] in ("..", "."):
        fail(f"member {rel} is not a path inside the tree")
    if not inside(os.path.realpath(os.path.join(tree_real, rel)), tree_real):
        fail(f"member {rel} resolves outside the tree")
    if not os.path.lexists(os.path.join(tree_real, rel)):
        fail(f"no member {rel}")
    return os.path.normpath(rel)

def collect(tree_real, rel, entries):
    if os.path.basename(rel).startswith("._"):
        return
    mode = os.lstat(os.path.join(tree_real, rel)).st_mode
    if stat.S_ISREG(mode):
        entries[rel] = False
    elif stat.S_ISDIR(mode):
        entries[rel] = True
        for child in os.listdir(os.path.join(tree_real, rel)):
            collect(tree_real, os.path.join(rel, child), entries)
    else:
        fail(f"{rel} is not a regular file or directory")

def entry_mode(name, is_dir, has_dirs):
    return 0o755 if has_dirs or is_dir or name.endswith((".so", ".dylib")) else 0o644

def tar_bytes(tree_real, entries, epoch):
    has_dirs = any(entries.values())
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in sorted(entries):
            path = os.path.join(tree_real, name)
            info = tarfile.TarInfo(name)
            info.type = tarfile.DIRTYPE if entries[name] else tarfile.REGTYPE
            info.size = 0 if entries[name] else os.path.getsize(path)
            info.mode = entry_mode(name, entries[name], has_dirs)
            info.mtime = epoch
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if entries[name]:
                tar.addfile(info)
            else:
                with open(path, "rb") as f:
                    tar.addfile(info, f)
    return buffer.getvalue()

def gzip_bytes(data):
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, compresslevel=9, mtime=0) as gz:
        gz.write(data)
    return buffer.getvalue()

def write_atomically(out, data):
    temp = f"{out}.pack-{os.getpid()}.tmp"
    try:
        with open(temp, "wb") as f:
            f.write(data)
        os.replace(temp, out)
    except OSError as error:
        if os.path.lexists(temp):
            os.remove(temp)
        fail(f"cannot write {out}: {error.strerror}")

def main(epoch_arg, tree, out, *members):
    if not (epoch_arg.isascii() and epoch_arg.isdigit()):
        fail("--mtime needs an integer epoch")
    if not os.path.isdir(tree):
        fail(f"no tree directory {tree}")
    tree_real = os.path.realpath(tree)
    out_real = os.path.realpath(out)
    roots = [check_member(tree_real, m) for m in members] or sorted(os.listdir(tree_real))
    entries = {}
    for root in roots:
        if inside(out_real, os.path.realpath(os.path.join(tree_real, root))):
            fail(f"{out} lies in the packed member {root}")
    try:
        for root in roots:
            collect(tree_real, root, entries)
        data = gzip_bytes(tar_bytes(tree_real, entries, int(epoch_arg)))
    except (OSError, ValueError) as error:
        fail(f"cannot pack {tree}: {error}")
    write_atomically(out, data)

main(*sys.argv[1:])
PY
