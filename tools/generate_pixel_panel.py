"""Generate a pixel-perfect 9-slice panel texture for Godot StyleBoxTexture.

The PNG has a transparent outer area, a 4 px hard shadow on its lower/right
side, a 2 px ink outline, a white interior, and stair-stepped pixel corners.

Godot setup for the output:
  - Create StyleBoxTexture and assign the PNG.
  - Texture Margin Left/Top/Right/Bottom = 8 px.
  - Horizontal/Vertical stretch = Stretch for a flat white centre.
  - Import filter = Nearest; mipmaps = Off.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image

CANVAS_SIZE = 32
NINE_SLICE_MARGIN = 8

# White minimalist STACK//STRIKE UI palette.
TRANSPARENT = (0, 0, 0, 0)
INK = (23, 26, 33, 255)       # #171A21
SURFACE = (255, 255, 255, 255)
HARD_SHADOW = (200, 205, 213, 255)  # #C8CDD5

# The main panel deliberately leaves a transparent gutter on all sides.
PANEL_X = 2
PANEL_Y = 2
PANEL_WIDTH = 25
PANEL_HEIGHT = 25
BORDER_WIDTH = 2
SHADOW_OFFSET_X = 4
SHADOW_OFFSET_Y = 4

# From the edge toward the middle, this is the number of pixels removed from
# each corner. It creates crisp, authored "pixel round" corners -- no anti-alias.
CORNER_INSETS = (5, 3, 2, 1, 0, 0)


def _corner_inset(distance_to_horizontal_edge: int) -> int:
    """Return the horizontal corner cut for a given top/bottom row distance."""
    if distance_to_horizontal_edge < len(CORNER_INSETS):
        return CORNER_INSETS[distance_to_horizontal_edge]
    return 0


def draw_pixel_round_rect(
    image: Image.Image,
    x: int,
    y: int,
    width: int,
    height: int,
    color: tuple[int, int, int, int],
) -> None:
    """Draw an opaque, stair-stepped rounded rectangle without interpolation."""
    pixels = image.load()
    for local_y in range(height):
        edge_distance = min(local_y, height - 1 - local_y)
        inset = _corner_inset(edge_distance)
        start_x = x + inset
        end_x = x + width - inset
        for local_x in range(start_x, end_x):
            pixels[local_x, y + local_y] = color


def generate_panel(output_path: Path) -> None:
    image = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), TRANSPARENT)

    # The shadow is drawn first so the panel fully covers its upper-left edge.
    draw_pixel_round_rect(
        image,
        PANEL_X + SHADOW_OFFSET_X,
        PANEL_Y + SHADOW_OFFSET_Y,
        PANEL_WIDTH,
        PANEL_HEIGHT,
        HARD_SHADOW,
    )

    # Outer ink outline, then a smaller white face.
    draw_pixel_round_rect(image, PANEL_X, PANEL_Y, PANEL_WIDTH, PANEL_HEIGHT, INK)
    draw_pixel_round_rect(
        image,
        PANEL_X + BORDER_WIDTH,
        PANEL_Y + BORDER_WIDTH,
        PANEL_WIDTH - BORDER_WIDTH * 2,
        PANEL_HEIGHT - BORDER_WIDTH * 2,
        SURFACE,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)


def generate_preview(texture_path: Path, preview_path: Path, scale: int = 12) -> None:
    """Save a nearest-neighbour preview for quick visual inspection only."""
    with Image.open(texture_path) as source:
        preview = source.resize((source.width * scale, source.height * scale), Image.Resampling.NEAREST)
        preview.save(preview_path)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    texture = root / "art/ui/styleboxes/panel_white_pixel_9slice.png"
    preview = root / "art/ui/styleboxes/panel_white_pixel_9slice_preview.png"

    generate_panel(texture)
    generate_preview(texture, preview)

    print(f"Generated: {texture}")
    print(f"Preview:   {preview}")
    print(f"Godot StyleBoxTexture texture margins: {NINE_SLICE_MARGIN}px on all sides")
