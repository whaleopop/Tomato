"""AI cosmetics pipeline: a hat or a hero skin from an English description, straight into the shop.

    D:\\royaltim-ai\\venv\\Scripts\\python.exe tools/ai_models/cosmetics/make_cosmetic.py hat \\
        --id viking_helm --name "Viking Helm" --name-ru "Шлем викинга" --price 400 \\
        --prompt "viking helmet with two curved horns"
    ... make_cosmetic.py skin --id lava --name "Lava" --name-ru "Лава" --price 350 \\
        --prompt "glowing molten lava cracks" [--metal 0.2] [--pattern camo]

hat:  text -> concept picture -> 3D (tools/ai_models/generate.py: LCM Dreamshaper + rembg + TripoSR,
      style "prop") -> models/cosmetics/hats/<id>.glb. Cosmetics.make_hat loads it (paper look, fitted
      to the head like the hand-made hats, never recolored by the skin).
skin: skins are a recolor in the hero shader, not a texture (heroes share one material), so the
      concept picture's palette becomes the parameters: hue / saturation / brightness, tint, metal,
      a glow from its brightest strong color, optionally a pattern (patterns.gdshaderinc) in its
      accent color.
Both: the entry goes into Cosmetics.HATS / SKINS (after the "AI-made" marker, the shop builds the
card from it), the Russian name into LocaleRu, the backend's price list is re-exported
(tools/server/export_catalog.gd) and a preview of a hero wearing it is rendered to
art/cosmetics/<id>_preview.png (and the concept to <id>_concept.png) - look at it before shipping.
Workflow: --candidates 4 first (a sheet of concept pictures with their seeds, nothing written),
look at it, then the real run with the --seed of the good one. --dry-run only shows what would be
written; --force replaces an id.
"""
import argparse
import colorsys
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.dirname(HERE))  # tools/ai_models: generate.py
GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
COSMETICS = os.path.join(ROOT, "ui", "profile", "Cosmetics.gd")
LOCALE = os.path.join(ROOT, "ui", "i18n", "LocaleRu.gd")
ART = os.path.join(ROOT, "art", "cosmetics")
HATS_DIR = os.path.join(ROOT, "models", "cosmetics", "hats")
MARKER = "\t# AI-made (tools/ai_models/cosmetics/make_cosmetic.py)\n"
PATTERNS = {"stripes": 1, "dots": 2, "camo": 3, "checker": 4, "zebra": 5, "galaxy": 6, "waves": 7}
METAL_WORDS = ("metal", "steel", "iron", "gold", "silver", "chrome", "bronze", "copper", "armor", "armour")


def log(*a):
    print("[cosmetic]", *a, flush=True)


# ------------------------------------------------------------------ the catalog (Cosmetics.gd)

def insert_entry(const_name, entry_id, line, force):
    src = open(COSMETICS, encoding="utf-8").read()
    start = src.index("const %s = {" % const_name)
    end = src.index("\n}", start)
    block = src[start:end]
    if re.search(r'^\t"%s":' % re.escape(entry_id), block, re.M):
        if not force:
            raise SystemExit("%s already has '%s' (use --force to replace it)" % (const_name, entry_id))
        block = re.sub(r'^\t"%s":.*\n?' % re.escape(entry_id), "", block, flags=re.M)
    if MARKER not in block:
        block = block.rstrip("\n") + "\n" + MARKER.rstrip("\n")
    block = block.rstrip("\n") + "\n\t" + line
    src = src[:start] + block + src[end:]
    open(COSMETICS, "w", encoding="utf-8", newline="").write(src)


def add_translation(english, russian):
    if not russian:
        return
    src = open(LOCALE, encoding="utf-8").read()
    key = '\t"%s":' % english
    if key in src:
        return
    anchor = '\t"HOST LAN": "СВОЯ ИГРА",\n'
    src = src.replace(anchor, anchor + '\t"%s": "%s",\n' % (english, russian), 1)
    open(LOCALE, "w", encoding="utf-8", newline="").write(src)


def gd_color(rgb, a=None):
    vals = [round(float(x), 3) for x in rgb]
    if a is not None:
        vals.append(round(float(a), 3))
    return "Color(%s)" % ", ".join(str(v) for v in vals)


# ------------------------------------------------------------------ generation

# Prompt template picked from a contact sheet of three: a "product photo of a toy hat lying alone"
# gives the hat by itself; "cartoon hat" / "game icon" drew a whole viking under it (and TripoSR
# turned the bust into part of the hat)
HAT_TEMPLATE = "product photo of one single toy {p} standing alone, one plastic toy hat, simple shapes, white studio background, front view"
NEG_CFG = 2.0
STEPS = 8
HAT_NEGATIVE = "two, pair, multiple, duplicate, set, person, character, face, eyes, body, head, mannequin, bust, neck, beard, hands"


def hat_prompt(p):
    return HAT_TEMPLATE.format(p=p), HAT_NEGATIVE + ", " + gen_default_negative()


def skin_prompt(p):
    return "%s, seamless surface texture, flat, close-up, no objects" % p, gen_default_negative()


def candidates(a):
    """Several concept pictures side by side (seeds under them): pick one with --seed"""
    from PIL import Image, ImageDraw
    prompt, negative = hat_prompt(a.prompt) if a.kind == "hat" else skin_prompt(a.prompt)
    gen, args = gen_args(prompt, "none", 0, ["--negative", negative, "--neg-cfg", str(NEG_CFG), "--steps", str(STEPS)])
    device = gen.pick_device(args)
    base = a.seed if a.seed >= 0 else int.from_bytes(os.urandom(2), "little")
    sheet = Image.new("RGB", (a.candidates * 256, 280), "white")
    draw = ImageDraw.Draw(sheet)
    for i in range(a.candidates):
        img = gen.text_to_image(args, device, base + i)
        sheet.paste(img.resize((256, 256)), (i * 256, 0))
        draw.text((i * 256 + 8, 260), "--seed %d" % (base + i), fill="black")
    os.makedirs(ART, exist_ok=True)
    path = os.path.join(ART, a.id + "_candidates.png")
    sheet.save(path)
    log("candidates:", path, "seeds %d..%d - run again with --seed N" % (base, base + a.candidates - 1))


def gen_default_negative():
    import generate as gen
    return gen.NEGATIVE_PROMPT


def gen_args(prompt, style, seed, extra=()):
    import generate as gen
    argv = ["--prompt", prompt, "--style", style, "--seed", str(seed)] + list(extra)
    return gen, gen.parse_args(argv)


def make_hat(a):
    os.makedirs(HATS_DIR, exist_ok=True)
    out = os.path.join(HATS_DIR, a.id + ".glb")
    prompt, negative = hat_prompt(a.prompt)
    gen, args = gen_args(prompt, "none", a.seed, ["--out", out, "--height", "0.4", "--faces", str(a.faces), "--name", a.id,
                                                  "--negative", negative, "--neg-cfg", str(NEG_CFG), "--steps", str(STEPS)])
    if a.dry_run:
        log("would generate", out, "from:", prompt)
    else:
        gen.generate(args)
        concept = os.path.join(HATS_DIR, a.id + "_concept.png")
        if os.path.exists(concept):
            os.makedirs(ART, exist_ok=True)
            os.replace(concept, os.path.join(ART, a.id + "_concept.png"))
    line = '"%s": {"name": "%s", "price": %d, "model": "res://models/cosmetics/hats/%s.glb"},' % (a.id, a.name, a.price, a.id)
    return "HATS", line


def palette(img, k=5):
    """The picture's main colors: [(share, (r, g, b) 0..1)] biggest first (a few rounds of k-means)."""
    import numpy as np
    px = np.asarray(img.convert("RGB").resize((96, 96))).reshape(-1, 3).astype(np.float32) / 255.0
    rng = np.random.default_rng(1)
    centers = px[rng.choice(len(px), k, replace=False)]
    for _ in range(12):
        d = ((px[:, None, :] - centers[None, :, :]) ** 2).sum(-1)
        lab = d.argmin(1)
        for i in range(k):
            if (lab == i).any():
                centers[i] = px[lab == i].mean(0)
    shares = [(float((lab == i).mean()), tuple(centers[i])) for i in range(k)]
    return sorted(shares, reverse=True)


def skin_params(colors, prompt, metal_arg, pattern):
    """Palette -> the shader's skin uniforms (Cosmetics.SKINS). The base is the picture's plain
    average color - its brightness darkens or lightens the hero, its hue tints it (normalizing the
    near-black main color to full brightness once gave a pink hero); the most vivid bright color
    (the lava in the cracks) becomes the glow and the pattern's color."""
    hsv = [(sh, colorsys.rgb_to_hsv(*rgb), rgb) for sh, rgb in colors]
    # The base: the plain average of the picture (dark rock -> a dark hero, in the rock's own hue)
    base = [sum(sh * rgb[i] for sh, _, rgb in hsv) for i in range(3)]
    bh, bs, bv = colorsys.rgb_to_hsv(*base)
    tint = [min(1.5, x * 1.15) for x in colorsys.hsv_to_rgb(bh, min(bs, 0.6), 1.0)] if bs > 0.15 else [1.0, 1.0, 1.0]
    sat = 0.25 + 0.45 * min(bs, 1.0)
    val = max(0.22, min(1.25, 0.1 + 1.0 * bv))
    vivid = max(hsv, key=lambda e: e[1][1] * e[1][2])
    metal = metal_arg if metal_arg is not None else (0.85 if any(w in prompt.lower() for w in METAL_WORDS) else 0.1)
    glow = (vivid[2], 0.3) if vivid[1][1] > 0.5 and vivid[1][2] > 0.65 else ((0, 0, 0), 0.0)
    params = '"hsv": Vector3(0.0, %.2f, %.2f), "tint": %s, "metal": %.2f, "glow": %s' % (
        sat, val, gd_color(tint), metal, gd_color(glow[0], glow[1]))
    if pattern:
        accent = vivid[2]
        params += ', "pattern": [%d, 6.0, %s]' % (PATTERNS[pattern], gd_color(accent, 0.5))
    return params


def make_skin(a):
    from PIL import Image
    os.makedirs(ART, exist_ok=True)
    concept = os.path.join(ART, a.id + "_concept.png")
    prompt, negative = skin_prompt(a.prompt)
    if a.dry_run:
        log("would draw", concept, "from:", prompt)
        colors = [(0.6, (0.6, 0.3, 0.2)), (0.4, (1.0, 0.6, 0.1))]
    elif a.reuse_concept and os.path.exists(concept):
        colors = palette(Image.open(concept))  # same picture, new mapping
    else:
        gen, args = gen_args(prompt, "none", a.seed, ["--negative", negative, "--neg-cfg", str(NEG_CFG), "--steps", str(STEPS)])
        device = gen.pick_device(args)
        seed = a.seed if a.seed >= 0 else int.from_bytes(os.urandom(3), "little")
        img = gen.text_to_image(args, device, seed)
        img.save(concept)
        colors = palette(Image.open(concept))
        log("palette:", ", ".join("%.0f%% #%02x%02x%02x" % (sh * 100, *(int(c * 255) for c in rgb)) for sh, rgb in colors))
    params = skin_params(colors, a.prompt, a.metal, a.pattern)
    line = '"%s": {"name": "%s", "price": %d, %s},' % (a.id, a.name, a.price, params)
    return "SKINS", line


# ------------------------------------------------------------------ after

def godot(*args, window=False):
    cmd = [GODOT] + ([] if window else ["--headless"]) + ["--path", ROOT] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def finish(a):
    godot("--import")
    r = godot("-s", "tools/server/export_catalog.gd")
    log(next((l for l in r.stdout.splitlines() if "[Catalog]" in l), "catalog: see tools/server/backend/catalog.json"))
    preview = os.path.join(ART, a.id + "_preview.png")
    r = godot("--resolution", "640x360", "-s", "tools/ai_models/cosmetics/preview.gd", "--",
              "--kind=" + a.kind, "--id=" + a.id, "--hero=" + a.hero, "--out=" + preview, window=True)
    log("preview:", preview if os.path.exists(preview) else "FAILED\n" + r.stdout[-800:])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", choices=["hat", "skin"])
    ap.add_argument("--id", required=True, help="snake_case id (goes over the network)")
    ap.add_argument("--name", required=True, help="English name (the source string)")
    ap.add_argument("--name-ru", default="", help="Russian name (LocaleRu)")
    ap.add_argument("--price", type=int, required=True, help="coins (500+ is a legendary card)")
    ap.add_argument("--prompt", required=True, help="what it is, in English")
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--faces", type=int, default=2500, help="hat: triangles after decimation")
    ap.add_argument("--metal", type=float, default=None, help="skin: 0..1 (default: from the prompt's words)")
    ap.add_argument("--pattern", choices=sorted(PATTERNS), help="skin: a pattern in the accent color")
    ap.add_argument("--hero", default="Tomato", help="who wears it in the preview")
    ap.add_argument("--candidates", type=int, default=0, help="only draw N concept pictures to choose from (no 3D, nothing written)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--reuse-concept", action="store_true", help="skin: take the palette from the existing <id>_concept.png")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,30}", a.id):
        raise SystemExit("--id: snake_case, 2-31 characters")
    if a.candidates > 0:
        candidates(a)
        return
    const, line = make_hat(a) if a.kind == "hat" else make_skin(a)
    log(const, "<-", line)
    if a.dry_run:
        return
    insert_entry(const, a.id, line, a.force)
    add_translation(a.name, a.name_ru)
    finish(a)
    log("done: check the preview, then release (the shop and the backend's prices ship with the game)")


if __name__ == "__main__":
    main()
