# Maid whale stage

`maid-whale.svg` / `maid-whale-blink.svg` are original vector layers generated
for ChatVivid's default character stage. They are intentionally kept as plain
SVG so the character can be re-imported into Rive Editor later.

Default animation:
- breathing: Flutter transform (vertical scale + slight lift)
- blinking: timed swap to the closed-eye SVG layer

For the Rive pipeline, import the SVG into Rive Editor, group head/body/eyes/
tail, add a State Machine with idle/blink/breath, and export `.riv`.
