# Card Artwork Path Binding Design

## Goal

Allow each `CardData` resource to store an optional card-art image path and let `CardView` display that image consistently, while preserving the existing native Godot frame, labels, tags, and interaction behavior.

## Scope

- Add an Inspector-selectable `artwork_path` string to `CardData` for `res://` PNG, WebP, JPG, and JPEG paths.
- Add a card-art `TextureRect` below the frame host and above the card surface.
- Load a valid `Texture2D` when `CardView` receives or refreshes a `CardInstance`.
- Display a single native-Control placeholder marked `UNILLUSTRATED` when the path is empty, invalid, missing, or does not load as a texture.
- Add focused scene coverage for valid-image and fallback behavior.

## Non-Goals

- Do not create or migrate card illustration assets.
- Do not update the user's uncommitted Ribwood card resources.
- Do not add a central card-art registry or modify card combat data.
- Do not change frame rarity logic, stat tags, zoom interaction, or drag behavior.

## Data and Presentation

`CardData.artwork_path` is an exported file path rather than a `Texture2D` reference, so designers can see and edit the source path directly in the Inspector. `CardView` resolves it through the Godot resource loader. The `Artwork` node fills the existing card art area using centered, aspect-covered cropping; it stays below `FrameHost` so existing native frames remain visible above the illustration.

If no usable texture is available, `Artwork` is hidden and `ArtworkPlaceholder` is shown. The placeholder is a dark restrained panel with the English label `UNILLUSTRATED`; it does not capture mouse input. A successful image load reverses those visibilities. The fallback must never prevent the rest of the card from rendering.

## Acceptance Criteria

- A designer can select an image file for `artwork_path` from the `CardData` Inspector.
- A valid `res://` texture path appears in `CardView` after `set_value` or `refresh_display`.
- Empty, missing, or invalid paths show the shared placeholder without runtime errors.
- The card frame still draws above the artwork.
- Existing no-image cards remain usable and the card view does not capture new input.