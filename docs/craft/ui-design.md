# UI design: clean, consistent, not slop

For menus, HUD and overlays in ROYALTIM-3. The template itself (navy / gold, ScreenHeader, GlassPanel, UIScale, icons) is in CLAUDE.md "UI" and `docs/arch/meta-ui.md`; this is how to design within it.

## Start from the job
- One sentence: what does the player decide or do on this screen? Everything that doesn't serve it goes.
- One primary action per screen, in gold (`create_play_button` / `create_primary_button`). Everything else is secondary (navy). Two gold buttons = no hierarchy.
- One focal element (the hero, the card, the map). The eye should land there first; the rest is quieter (smaller, `TEXT_SECONDARY` / `TEXT_MUTED`).

## Use the tokens, never invent values
- Font sizes only from `UITheme.FONT_*` (12 / 14 / 17 / 20 / 22 / 34 / 64). No 13, 15, 18, 26.
- Spacing only `SPACING_*` (8 / 14 / 22) and `MARGIN_*` (12 / 22 / 40); radii `CORNER_RADIUS_SMALL` / `CORNER_RADIUS` / `_PILL`.
- Colors only `UITheme` constants. Gold = call to action, hover, selection. `ACCENT_DANGER` = destructive / damage only. Lime / sky / beet = data categories (rarity, team), not decoration. No new hex colors in screen code.
- Build with the factory helpers (`create_label`, `create_button`, `navy_box`, `create_pill`, `create_icon_chip`...), so a theme change reaches everything.

## Layout
- Proximity shows structure: things that belong together sit closer than things that don't (8 inside a group, 22 between groups).
- Align to few edges. Left-align text blocks; center only titles, single buttons and empty states.
- Containers and anchors, not absolute positions: the canvas is a virtual 1920x1080 that expands to 21:9 and scales x1.33 / x2 for 1440p / 4K.
- Russian runs ~30% longer than English: no fixed widths that clip text; let labels wrap or use `text_overrun_behavior` ellipsis with a tooltip.
- Click targets at least 44 virtual px high. Numbers in columns right-aligned.

## Copy
- Short. Buttons are verbs or verb + object: "BUY", "EQUIP", "PLAY". Not "Click here to purchase this item".
- No filler: no "Welcome!" headers, no subtitles that restate the title, no tooltip that repeats the label.
- No symbol glyphs or emoji in text (Nunito lacks them) - use `UITheme.icon`.
- Every string through `LocaleRu.STRINGS`; uppercase via `Label.uppercase`.

## States (missing states are what makes UI feel cheap)
- Every interactive element: normal, hover, pressed, disabled, selected (gold rim), keyboard focus.
- Every list / panel: empty state (one line + the action that fills it), loading (spinner or skeleton, not a frozen panel), error (what happened + retry).
- Esc / back closes overlays; overlays join group `blocks_game_input`.

## Motion
- 120-200 ms, ease-out (`Tween.TRANS_QUAD` / `EASE_OUT`). Animate a change of state (open, select, value up), not idle decoration.
- One thing moves at a time; no pulsing, bouncing or glowing that never stops (the 3D hero showcase is the exception).

## HUD (glanceable in a fight)
- Corners and edges; the center belongs to the hero and the crosshair. Critical info (health, ammo) near where the eye already is.
- Quiet at rest, loud on change: flash / scale-punch when a value changes, then settle.
- Never color alone: pair it with shape, icon or text (colorblind players, busy backgrounds).
- Readable over bright grass and dark night: text on a `GLASS_TINT_HUD` backing or with outline.

## Slop checklist - reject on sight
- Glow + gradient + shadow + border on everything; every element in its own card; cards inside cards.
- Five accent colors on one screen; decorative icons that mean nothing; icons of mixed styles.
- Random sizes and gaps; centered paragraphs; walls of text; placeholder copy left in.
- Huge empty panels, or everything crammed edge to edge.
- Hover that does nothing visible; disabled buttons that look enabled.

## Check it
Have the tester take windowed screenshots at 1920x1080 and 3840x2160 (and the Russian locale) and look at them next to the main menu. Ask: where does the eye go first? Is it the right thing?
