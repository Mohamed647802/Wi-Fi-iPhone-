from PIL import Image, ImageDraw
S = 1024
img = Image.new("RGB", (S, S))
px = img.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = (int(10 + 40 * t), int(14 + 10 * t), int(40 + 100 * t))
d = ImageDraw.Draw(img)
cx, cy = 512, 700
for i, r in enumerate([170, 330, 490]):
    col = [(64, 204, 255), (80, 220, 255), (110, 235, 255)][i]
    d.arc([cx - r, cy - r, cx + r, cy + r], 225, 315, fill=col, width=64)
d.ellipse([cx - 50, cy - 50, cx + 50, cy + 50], fill=(102, 255, 153))
img.save("Sources/Assets.xcassets/AppIcon.appiconset/icon.png")
