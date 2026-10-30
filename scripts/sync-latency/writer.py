#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Mac A: writes a small and a 5 MB file into the folder every interval, the way Pesto does (a .partial file, then a
rename), and logs when each was finished. The log stays on this Mac, never in the synced folder.

  writer.py --folder <the iCloud Drive folder> --offset $(clock-offset.sh)
"""
import argparse
import json
import os
import struct
import sys
import time

MAGIC = b"PSTOLAT1"
SIZES = {"small": 4 * 1024, "large": 5 * 1024 * 1024}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", required=True)
    parser.add_argument("--log", default="writer.log")
    parser.add_argument("--offset", type=float, default=0.0, help="seconds to add to this clock (clock-offset.sh)")
    parser.add_argument("--interval", type=float, default=30.0)
    parser.add_argument("--duration", type=float, default=3600.0)
    parser.add_argument("--run", default=time.strftime("%Y%m%d-%H%M%S"), help="names this run")
    args = parser.parse_args()
    os.makedirs(args.folder, exist_ok=True)
    started = time.time()
    seq = 0
    with open(args.log, "a") as log:
        while time.time() - started < args.duration:
            tick = time.time()
            for kind, size in SIZES.items():
                seq += 1
                name = f"{args.run}-{seq:05d}-{kind}.lat"
                final = os.path.join(args.folder, name)
                partial = final + ".partial"
                done = time.time() + args.offset
                header = MAGIC + struct.pack(">Qd", seq, done)  # 8 + 8 + 8 bytes
                with open(partial, "wb") as handle:
                    handle.write(header + os.urandom(size - len(header)))
                    handle.flush()
                    os.fsync(handle.fileno())
                os.rename(partial, final)
                written = time.time() + args.offset
                log.write(json.dumps({"file": name, "seq": seq, "kind": kind, "bytes": size, "written": written}) + "\n")
                log.flush()
            time.sleep(max(0.0, args.interval - (time.time() - tick)))
    print(f"wrote {seq} files to {args.folder}; log {args.log}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
