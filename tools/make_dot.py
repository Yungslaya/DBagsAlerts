# 64x64 round dot (white fill with soft top shine, dark rim) for vertex coloring in WoW.
import math, struct, sys
out = sys.argv[1]; N = 64; c = N / 2; R = N / 2 - 2
px = bytearray()
for y in range(N):
    for x in range(N):
        d = math.hypot(x + 0.5 - c, y + 0.5 - c)
        a = max(0.0, min(1.0, R - d + 0.5))           # anti-aliased edge
        if d > R - 4:   v = 0.15                      # dark rim
        else:
            # TGA rows go bottom-up: y small = bottom. Shine at the top.
            shine = max(0.0, (y - c) / R) * 0.25
            v = 0.85 + shine
        v = max(0.0, min(1.0, v))
        g = int(round(255 * v))
        px += bytes((g, g, g, int(round(255 * a))))
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8)
open(out, "wb").write(hdr + px); print("wrote", out)
