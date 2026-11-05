# 128x128 square proc-glow frame (white + alpha) for WoW: a bright edge line where the
# icon border is, fading out softly outside it. The icon covers the middle 64%.
import math, struct, sys

out = sys.argv[1]
N = 128
lo, hi = N * 0.18, N * 0.82          # icon square edges (icon = 64% of the texture)
px = bytearray()
for y in range(N):
    for x in range(N):
        fx, fy = x + 0.5, y + 0.5
        # signed distance to the square edge (negative = inside the icon)
        dx = max(lo - fx, fx - hi)
        dy = max(lo - fy, fy - hi)
        if dx > 0 and dy > 0:
            d = math.hypot(dx, dy)          # rounded outer corners
        else:
            d = max(dx, dy)
        if d < -3:
            a = 0.0                           # keep the icon itself clear
        elif d <= 1:
            a = 1.0                           # bright edge line
        else:
            a = math.exp(-((d - 1) / 7.0) ** 2)   # soft glow outside
        px += bytes((255, 255, 255, int(round(255 * max(0.0, min(1.0, a))))))
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8)
with open(out, "wb") as f:
    f.write(header)
    f.write(px)
print("wrote", out)
