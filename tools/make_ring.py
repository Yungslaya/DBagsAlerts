# Writes a 128x128 white anti-aliased ring (alpha channel) as an uncompressed TGA for WoW.
import math, struct, sys

out = sys.argv[1]
N = 128
c = (N - 1) / 2.0
outer, thick = 60.0, 9.0          # ring radius and thickness, in pixels
inner = outer - thick
px = bytearray()
for y in range(N):
    for x in range(N):
        # 4x4 supersampling for smooth edges
        cover = 0
        for sy in range(4):
            for sx in range(4):
                dx = x + (sx + 0.5) / 4 - 0.5 - c
                dy = y + (sy + 0.5) / 4 - 0.5 - c
                d = math.hypot(dx, dy)
                if inner <= d <= outer:
                    cover += 1
        a = int(round(255 * cover / 16))
        px += bytes((255, 255, 255, a))          # BGRA, white
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8)  # type 2, 32bpp, 8 alpha bits
with open(out, "wb") as f:
    f.write(header)
    f.write(px)
print("wrote", out, len(px) + len(header), "bytes")
