# Memo onboarding pose prompts

All three assets use the built-in image generation path. `MemoMascot` is the
identity and rendering reference; `approved-direction.png` is the pose and
proportion reference. Each source was generated on a flat `#00ff00` background,
then converted to RGBA with the bundled chroma-key helper and exported at
1x/2x/3x.

## Clue

Create the canonical SAV-E baby mammoth leaning over the top edge of an
envelope: both front paws visible, head slightly tilted, trunk relaxed forward,
and a curious expression. Isolate only the waist-up mascot; no envelope, books,
card, text, shadow, or white sticker border. Preserve the canonical caramel fur,
cream tusks, dark-brown outline, face, ears, and rendering.

## Review

Create the canonical SAV-E baby mammoth peeking from the lower-right edge of an
envelope and holding a slim wooden pointer diagonally upward in one front paw.
The other paw rests at the edge and the expression is friendly and instructive.
Isolate only the waist-up mascot and pointer; no envelope, books, card, text,
shadow, or white sticker border. Preserve the canonical identity and rendering.

## Stamp

Create the canonical SAV-E baby mammoth lying relaxed across the top edge of an
envelope: head and front paws visible, trunk curled gently left, eyes happily
closed, and a satisfied expression. Isolate only the horizontal waist-up
mascot; no envelope, books, card, text, shadow, or white sticker border.
Preserve the canonical identity and rendering.

## Blank onboarding front pocket

Use the production `SavesEnvelope` as the identity and construction reference.
Preserve its recessed opening, stitched edge, rounded lower corners, kraft
paper, left airplane cancellation, lighting, and shadow. Remove only the empty
right wax-seal ring and rebuild that region as uninterrupted kraft paper. The
generated white background is removed mechanically, then the isolated pocket
is resampled deterministically to 1x/2x/3x. This asset is onboarding-only; it
does not replace `SavesEnvelope` elsewhere in the app.
