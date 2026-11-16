"""Join base64 job_part dumps (JSON {part,bytes,data}) into one file: join_parts.py out.bin part_files..."""
import sys, json, base64
out = sys.argv[1]
parts = {}
for f in sys.argv[2:]:
    d = json.load(open(f))
    parts[d["part"]] = base64.b64decode(d["data"])
data = b"".join(parts[k] for k in sorted(parts))
open(out, "wb").write(data)
print(out, len(data), sorted(parts))
