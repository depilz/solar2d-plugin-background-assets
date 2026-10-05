"""usage: members.py ARCHIVE MEMBER...
Exits 1 unless ARCHIVE's entries are exactly the MEMBERs, each a flat regular file with mode 0644 and uid/gid 0."""
import sys
import tarfile

archive, expected = sys.argv[1], sorted(sys.argv[2:])
with tarfile.open(archive) as tar:
    entries = tar.getmembers()

problems = [f"{e.name}: type {e.type!r} mode {e.mode:o} uid/gid {e.uid}/{e.gid}" for e in entries
            if not (e.isfile() and e.mode == 0o644 and e.uid == 0 and e.gid == 0)]
names = sorted(e.name for e in entries)
if names != expected:
    problems.append(f"members {names}, expected {expected}")
for problem in problems:
    print(problem)
sys.exit(1 if problems else 0)
