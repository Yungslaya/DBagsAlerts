# 256x32 flat bar texture, faint top-to-bottom shade, white for vertex coloring.
import struct, sys
W, H = 256, 32; px = bytearray()
for y in range(H):              # TGA rows bottom-up
    v = int(round(255 * (0.78 + 0.22 * y / (H - 1))))
    px += bytes((v, v, v, 255)) * W
open(sys.argv[1], "wb").write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8) + px)
