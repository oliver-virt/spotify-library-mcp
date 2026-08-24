# Record Room assets — generation pipeline

Generated with fal.ai FLUX schnell (same setup as storybo; adapter reference: ~/code/tools/orbit-stack/packages/ai/src/adapters/fal.ts).
Key: FAL_KEY from a local .env — never commit it.

```bash
curl -s -X POST "https://fal.run/fal-ai/flux/schnell" \
  -H "Authorization: Key $FAL_KEY" -H "Content-Type: application/json" \
  -d '{"prompt": "<PROMPT>", "image_size": {"width": 1024, "height": 576}, "num_images": 1}'
```

Palette brief used in every prompt: warm browns + cream, ONE red-orange accent (#E8461B), SNES-era pixel art, no text.

| File | Prompt gist |
|---|---|
| store-scene.png | cozy vinyl store interior, crates, counter, turntable, hanging sign, amber light, no people |
| clerk.png | clerk sprite: dark hair, red-orange headphones, cream shirt, behind counter, head-bob |
| icon-pixel.png | app icon: vinyl with red-orange label leaning in wooden crate, cream bg |

Next batch (same style words for consistency): clerk poses (pointing, flipping records, printing receipt), store at night, empty crate, receipt printer close-up, a cat on the counter. For pose-consistent characters use fal-ai/nano-banana-2 with the clerk image as reference (queue mode — see the orbit-stack adapter).
