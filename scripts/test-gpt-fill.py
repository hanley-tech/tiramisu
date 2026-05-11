#!/usr/bin/env python3
"""
Standalone test: Azure OpenAI (gpt-image-1) as an expand/fill backend.

Tests whether the model can extend an image outward using the images/edits
endpoint with a transparent-alpha mask. Transparency = fill here.

Usage:
    python3 scripts/test-gpt-fill.py --base-url <azure-endpoint> \
            --api-key <key> --model <deployment-name> \
            [--image path/to/image.png] [--expand-fraction 0.2]

The script creates a synthetic test image if no --image is given.
Output is saved to /tmp/gpt-fill-result.png and opened in Preview.
"""

import argparse
import io
import os
import subprocess
import sys
import uuid
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow not installed. Run: pip install Pillow requests")
    sys.exit(1)

try:
    import requests
except ImportError:
    print("requests not installed. Run: pip install Pillow requests")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def make_test_image(size: tuple[int, int] = (512, 512)) -> Image.Image:
    """Create a simple colourful test image so the model has real content to extend."""
    img = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)
    w, h = size
    # gradient-ish bands
    for y in range(0, h, 40):
        r = int(200 * y / h)
        g = int(150 * (1 - y / h))
        b = 180
        draw.rectangle([0, y, w, y + 38], fill=(r, g, b, 255))
    # central subject
    draw.ellipse([w // 4, h // 4, 3 * w // 4, 3 * h // 4], fill=(255, 200, 50, 255))
    draw.rectangle([w // 3, h // 3, 2 * w // 3, 2 * h // 3], fill=(50, 150, 255, 255))
    return img


def make_expand_mask(image: Image.Image, expand_fraction: float = 0.25) -> Image.Image:
    """
    Right-side expand mask: the rightmost `expand_fraction` of the image
    is transparent (= tell OpenAI to fill it). Rest is opaque white.

    OpenAI's convention: transparent = fill, opaque = preserve.
    """
    w, h = image.size
    band = int(w * expand_fraction)
    mask = Image.new("RGBA", (w, h), (255, 255, 255, 255))  # fully opaque
    draw = ImageDraw.Draw(mask)
    draw.rectangle([w - band, 0, w, h], fill=(0, 0, 0, 0))  # transparent band
    return mask


def extend_image_right(image: Image.Image, expand_fraction: float = 0.25) -> Image.Image:
    """
    To test outpainting: create a wider canvas (original + right band) and
    position the original on the left. The right band is white.
    Return the wider canvas and a mask (transparent in the right band).
    """
    w, h = image.size
    band = int(w * expand_fraction)
    new_w = w + band

    canvas = Image.new("RGBA", (new_w, h), (255, 255, 255, 255))
    canvas.paste(image, (0, 0))

    mask = Image.new("RGBA", (new_w, h), (255, 255, 255, 255))  # opaque = preserve
    draw = ImageDraw.Draw(mask)
    draw.rectangle([w, 0, new_w, h], fill=(0, 0, 0, 0))  # transparent = fill

    return canvas, mask


def to_png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def pick_size(w: int, h: int) -> str:
    """Pick closest OpenAI-supported size."""
    supported = [(1024, 1024), (1536, 1024), (1024, 1536)]
    aspect = w / h
    best = min(supported, key=lambda s: abs(s[0] / s[1] - aspect))
    return f"{best[0]}x{best[1]}"


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------

def call_images_edits(base_url: str, api_key: str, model: str,
                      image_png: bytes, mask_png: bytes,
                      prompt: str, size: str) -> bytes:
    base = base_url.rstrip("/")
    # Azure URL shape
    if ".cognitiveservices.azure.com" in base or ".openai.azure.com" in base:
        url = f"{base}/openai/deployments/{model}/images/edits?api-version=2025-04-01-preview"
        headers = {"api-key": api_key}
    else:
        url = f"{base}/v1/images/edits"
        headers = {"Authorization": f"Bearer {api_key}"}

    print(f"→ POST {url}")
    print(f"   image: {len(image_png):,} bytes  mask: {len(mask_png):,} bytes  size: {size}")

    resp = requests.post(
        url,
        headers=headers,
        files={
            "image": ("image.png", image_png, "image/png"),
            "mask":  ("mask.png",  mask_png,  "image/png"),
        },
        data={
            "prompt": prompt,
            "n": "1",
            "size": size,
            "quality": "high",
            **({"model": model} if ".cognitiveservices.azure.com" not in base
                                and ".openai.azure.com" not in base else {}),
        },
        timeout=300,
    )

    print(f"   HTTP {resp.status_code}")
    if resp.status_code != 200:
        print("ERROR response:", resp.text[:1000])
        sys.exit(1)

    import base64
    data = resp.json()["data"][0]["b64_json"]
    return base64.b64decode(data)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Test GPT Image outpainting via images/edits")
    parser.add_argument("--base-url", required=True, help="Azure endpoint or api.openai.com")
    parser.add_argument("--api-key",  required=True)
    parser.add_argument("--model",    required=True, help="Deployment name or gpt-image-1")
    parser.add_argument("--image",    help="Path to source PNG (default: generated test image)")
    parser.add_argument("--expand-fraction", type=float, default=0.25,
                        help="Fraction of width to expand on the right (default 0.25 = 25%%)")
    parser.add_argument("--prompt",   default="seamless continuation of the scene, same style and lighting")
    parser.add_argument("--out",      default="/tmp/gpt-fill-result.png")
    args = parser.parse_args()

    # 1. Load or generate source image
    if args.image:
        src = Image.open(args.image).convert("RGBA")
        print(f"Loaded source: {args.image} ({src.size[0]}×{src.size[1]})")
    else:
        src = make_test_image((768, 512))
        print(f"Using generated test image ({src.size[0]}×{src.size[1]})")

    # 2. Build outpaint canvas + mask (right-side expand)
    canvas, mask = extend_image_right(src, args.expand_fraction)
    print(f"Canvas with band: {canvas.size[0]}×{canvas.size[1]}  "
          f"(band = {canvas.size[0] - src.size[0]}px on right)")

    # Save debug images
    canvas.save("/tmp/gpt-fill-input.png")
    mask.save("/tmp/gpt-fill-mask.png")
    print("Debug: input → /tmp/gpt-fill-input.png  mask → /tmp/gpt-fill-mask.png")

    # 3. Pick size and resize both to it
    size_label = pick_size(canvas.size[0], canvas.size[1])
    tw, th = map(int, size_label.split("x"))
    canvas_r = canvas.resize((tw, th), Image.LANCZOS)
    mask_r   = mask.resize((tw, th),   Image.NEAREST)
    print(f"Resized to {size_label} for API")

    # 4. Encode
    canvas_png = to_png_bytes(canvas_r)
    mask_png   = to_png_bytes(mask_r)

    # 5. Call API
    result_bytes = call_images_edits(
        args.base_url, args.api_key, args.model,
        canvas_png, mask_png, args.prompt, size_label
    )

    # 6. Save + open
    out_path = args.out
    with open(out_path, "wb") as f:
        f.write(result_bytes)
    result = Image.open(io.BytesIO(result_bytes))
    print(f"Result: {result.size[0]}×{result.size[1]} → {out_path}")
    subprocess.run(["open", out_path])
    # Also open inputs side by side for comparison
    subprocess.run(["open", "/tmp/gpt-fill-input.png"])


if __name__ == "__main__":
    main()
