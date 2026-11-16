"""Join the newest job_part dumps (from one parallel batch) into a file: join_latest.py out.bin [max_n]"""
import sys, json, base64, glob, os
D = "/root/.claude/projects/-home-claude/60ccb364-bc23-5aec-8751-13c38b9b3b3b/tool-results/"
fl = sorted(glob.glob(D + "mcp-Whiteboard_Images-job_part-*.txt"), key=os.path.getmtime, reverse=True)
n = int(sys.argv[2]) if len(sys.argv) > 2 else 7
parts = {}
for f in fl[:n]:
    d = json.load(open(f))
    if d["part"] in parts:
        break
    parts[d["part"]] = base64.b64decode(d["data"])
keys = sorted(parts)
assert keys == list(range(len(keys))), keys
data = b"".join(parts[k] for k in keys)
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
open(sys.argv[1], "wb").write(data)
for f in fl[:len(keys)]:
    os.remove(f)
print(sys.argv[1], len(data), keys, data[:4])
