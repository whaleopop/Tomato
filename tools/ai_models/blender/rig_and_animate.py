"""Blender (5.x) batch script: clean up a character mesh, auto-rig it, add a toy animation set.

    blender -b --factory-startup -P rig_and_animate.py -- IN.glb OUT.glb [--remesh] [--faces 5000]
    ... -- IN.glb OUT.glb --palette P.palette.txt --concept INPUT.png [--faces 2500]   (concept look)
    ... -- --anim-only IN.glb [OUT.glb]                                               (re-bake clips only)
    ... -- --extract CONCEPT.png OUT.palette.txt                                      (palette only)

Made for ROYALTIM's veggie mascots (round body, optional stubby arms/legs):
  1. joins all meshes and applies transforms
  2. --palette/--concept: dense remesh, every face snapped to a flat palette color (the front
     straight from the concept picture), decimated to low-poly with color borders protected
     --remesh: voxel remesh, smooth, decimate, then copies the vertex colors back
     (for AI-generated meshes; leave it off for hand-made low-poly models with materials)
  3. finds legs/arms from the shape and builds a small armature
     (root > body > head, body > arm.L/R, root > leg.L/R; limbs only if detected)
  4. skins with automatic weights and repairs vertices left without weights
  5. keyframes (key pose tables) idle, walk, run, jump, fall, land, attack, hit, death, 5 casts
  6. exports a GLB with the skeleton and all actions (Godot: AnimationPlayer)

Prints "PROGRESS: <pct> <msg>" and a final "RESULT: <path>" like generate.py.
"""
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

FPS = 30


def log(pct, msg):
    print(f"PROGRESS: {pct} {msg}", flush=True)


def info(msg):
    print(f"INFO: {msg}", flush=True)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        raise SystemExit("usage: ... -- IN.glb OUT.glb [--remesh] [--faces N]")
    def value(flag, default=None):
        return argv[argv.index(flag) + 1] if flag in argv else default

    opts = {"src": argv[0], "dst": argv[1], "remesh": "--remesh" in argv, "faces": 5000,
            "faces_given": "--faces" in argv,
            "flat": "--flat" in argv, "posterize": 0, "vivid": 1.0,
            "limbs": value("--limbs", "auto"),
            "merge_l": float(value("--merge-l", 0.25)),
            "palette": value("--palette"), "concept": value("--concept"),
            "protect": float(value("--protect", 1.0)),
            "voxel": int(value("--voxel", 110)), "smooth": int(value("--smooth", 3))}
    for key, cast in (("faces", int), ("posterize", int), ("vivid", float)):
        flag = "--" + key
        if flag in argv:
            opts[key] = cast(argv[argv.index(flag) + 1])
    return opts


# ----------------------------------------------------------------------------- mesh


def import_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("ERROR: no mesh in " + path)
    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Drop leftover empties from the glTF hierarchy
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.name = "Body"
    return obj


def read_point_colors(mesh):
    """Per-vertex colors (averaging corner colors if needed), or None."""
    if not mesh.color_attributes:
        return None
    attr = mesh.color_attributes.active_color or mesh.color_attributes[0]
    if attr.domain == "POINT":
        return [tuple(d.color) for d in attr.data]
    sums = [[0.0, 0.0, 0.0, 0.0, 0] for _ in mesh.vertices]
    for loop in mesh.loops:
        c = attr.data[loop.index].color
        s = sums[loop.vertex_index]
        for i in range(4):
            s[i] += c[i]
        s[4] += 1
    return [tuple(v / max(s[4], 1) for v in s[:4]) for s in sums]


def remesh(obj, faces, flat=False, posterize=0, vivid=1.0, merge_l=0.25):
    """Voxel remesh + smooth + decimate; vertex colors are copied from the original."""
    src_mesh = obj.data.copy()
    colors = read_point_colors(src_mesh)
    height = max(obj.dimensions)

    mod = obj.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = height / 90.0
    mod.use_smooth_shade = True
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 4
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)

    # Target is in triangles (what the game renders); remesh output is mostly quads
    current = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if faces > 0 and current > faces:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = faces / current
        bpy.ops.object.modifier_apply(modifier=dec.name)

    if colors and flat:
        _flat_face_colors(obj, src_mesh, colors, posterize, vivid, merge_l)
    elif colors:
        tree = KDTree(len(src_mesh.vertices))
        for i, v in enumerate(src_mesh.vertices):
            tree.insert(v.co, i)
        tree.balance()
        attr = obj.data.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
        for i, v in enumerate(obj.data.vertices):
            # Average the few nearest original vertices: smooth, no speckles
            near = tree.find_n(v.co, 4)
            acc = [0.0, 0.0, 0.0, 0.0]
            for _co, idx, _d in near:
                for k in range(4):
                    acc[k] += colors[idx][k]
            attr.data[i].color = [a / len(near) for a in acc]
        obj.data.color_attributes.active_color = attr
    bpy.data.meshes.remove(src_mesh)
    for p in obj.data.polygons:
        p.use_smooth = not flat
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    info(f"remeshed: {current} -> {tris} triangles")



def simplify(obj, faces, flat=False, vivid=1.0):
    """Decimate the original mesh (Blender keeps the vertex colors while collapsing edges) and
    optionally switch to flat faces with one color per face taken from the face's own corners.
    Sharper than remesh(): no resampling, so small features like pupils survive."""
    import numpy as np
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode="OBJECT")
    current = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if faces > 0 and current > faces:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = faces / current
        bpy.ops.object.modifier_apply(modifier=dec.name)
    mesh = obj.data
    colors = read_point_colors(mesh)
    if flat and colors:
        attr = mesh.color_attributes.new("FaceColor", "FLOAT_COLOR", "CORNER")
        for p in mesh.polygons:
            c = np.mean([colors[v][:3] for v in p.vertices], axis=0)
            if vivid != 1.0:
                grey = c.mean()
                c = np.clip(grey + (c - grey) * vivid, 0.0, 1.0)
            for li in p.loop_indices:
                attr.data[li].color = list(c) + [1.0]
        mesh.color_attributes.active_color = attr
    for p in mesh.polygons:
        p.use_smooth = not flat
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    info(f"simplified: {current} -> {tris} triangles ({'flat' if flat else 'smooth'})")


# ----------------------------------------------------------------------------- low-poly look


def _to_oklab(rgb):
    """Linear sRGB (N,3) -> OKLab (N,3); perceptual space for clustering colors."""
    import numpy as np
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    lms = np.cbrt(np.clip(rgb @ m1.T, 0.0, None))
    return lms @ m2.T


def _kmeans(x, k, iters=25, seed=7):
    import numpy as np
    rng = np.random.default_rng(seed)
    centers = [x[rng.integers(len(x))]]
    for _ in range(1, k):  # k-means++ init
        d = np.min([((x - c) ** 2).sum(1) for c in centers], axis=0)
        centers.append(x[rng.choice(len(x), p=d / d.sum())])
    centers = np.array(centers)
    for _ in range(iters):
        labels = ((x[:, None, :] - centers[None]) ** 2).sum(2).argmin(1)
        for j in range(k):
            if (labels == j).any():
                centers[j] = x[labels == j].mean(0)
    return labels


def _merge_shades(lab, labels, merge_l):
    """Clusters that differ mainly in lightness are the same material under different light.
    Biggest clusters become groups; a smaller cluster joins the first group whose representative
    has nearly the same hue/chroma and a close lightness. No chaining, so red never slides into
    brown into green."""
    import numpy as np
    ids, counts = np.unique(labels, return_counts=True)
    order = ids[np.argsort(-counts)]
    means = {j: lab[labels == j].mean(0) for j in ids}
    groups = []  # representative cluster ids
    assign = {}
    for j in order:
        for g in groups:
            da = np.linalg.norm(means[j][1:] - means[g][1:])
            dl = abs(means[j][0] - means[g][0])
            if da < 0.03 and dl < merge_l:
                assign[j] = g
                break
        else:
            groups.append(j)
            assign[j] = j
    return np.array([assign[j] for j in labels])


def _face_neighbours(mesh):
    """Faces sharing an edge, per face."""
    edge_faces = {}
    for p in mesh.polygons:
        for ek in p.edge_keys:
            edge_faces.setdefault(ek, []).append(p.index)
    neighbours = [[] for _ in mesh.polygons]
    for faces_on_edge in edge_faces.values():
        for a in faces_on_edge:
            neighbours[a].extend(f for f in faces_on_edge if f != a)
    return neighbours


def _majority_filter(mesh, labels, passes=2, neighbours=None):
    """Faces whose color disagrees with most neighbours take the neighbours' color."""
    import numpy as np
    if neighbours is None:
        neighbours = _face_neighbours(mesh)
    for _ in range(passes):
        new = labels.copy()
        for i, nb in enumerate(neighbours):
            if nb:
                vals, counts = np.unique(labels[nb], return_counts=True)
                if counts.max() >= 2 and vals[counts.argmax()] != labels[i]:
                    new[i] = vals[counts.argmax()]
        labels = new
    return labels


def _flat_face_colors(obj, src_mesh, colors, posterize, vivid, merge_l=0.25):
    """One color per face (paper-craft look). With posterize > 0 the face colors are clustered
    into that many flat colors, which also removes the lighting baked into the AI colors."""
    import numpy as np
    tree = KDTree(len(src_mesh.vertices))
    for i, v in enumerate(src_mesh.vertices):
        tree.insert(v.co, i)
    tree.balance()
    mesh = obj.data
    face_rgb = np.zeros((len(mesh.polygons), 3))
    for p in mesh.polygons:
        near = tree.find_n(p.center, 6)
        face_rgb[p.index] = np.mean([colors[idx][:3] for _c, idx, _d in near], axis=0)

    if posterize > 0:
        lab = _to_oklab(face_rgb)
        labels = _merge_shades(lab, _kmeans(lab, max(posterize * 2, 10)), merge_l)
        labels = _majority_filter(mesh, labels)
        uniq = np.unique(labels)
        palette = {}
        for j in uniq:
            members = labels == j
            # Lit side of the region = closest to the flat albedo of the concept
            lit = members & (lab[:, 0] >= np.median(lab[members, 0]))
            palette[j] = face_rgb[lit].mean(0)
        if vivid != 1.0:
            for j, col in palette.items():
                grey = col.mean()
                palette[j] = np.clip(grey + (col - grey) * vivid, 0.0, 1.0)
        face_rgb = np.array([palette[j] for j in labels])
        info("palette (%d colors): " % len(palette) + " ".join(
            "#%02x%02x%02x" % tuple(int(255 * (c ** (1 / 2.2))) for c in col) for col in palette.values()))

    attr = mesh.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    for p in mesh.polygons:
        c = list(face_rgb[p.index]) + [1.0]
        for li in p.loop_indices:
            attr.data[li].color = c
    mesh.color_attributes.active_color = attr


# ----------------------------------------------------------------------------- concept palette
# The concept style: a few flat colors (body, leaf, stem, eye white, pupils...) on big facets.
# The AI vertex colors are blurry and carry the concept's lighting, so every face is snapped to a
# palette color instead. Palette file, one material per line:
#     #cf4a30 body  ~#e36143 ~#832917   ; comment
# the first color is painted; "~" shades are how the material looks lit / shadowed on the AI
# model and map to it too. Flags: "front" = only where the concept picture shows it (eyes,
# pupils, brows - the AI invents blotches of them elsewhere); "anchored" = on the sides and back
# only as a continuation of what the picture shows (leaf, stem). Other lines are ignored.


def _srgb_to_linear(c):
    import numpy as np
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_hex(c):
    import numpy as np
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    s = np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
    return "#%02x%02x%02x" % tuple(int(round(v * 255)) for v in s)


def _hex(token):
    if len(token) < 7 or token[0] != "#":
        return None
    try:
        return _srgb_to_linear([int(token[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])
    except ValueError:
        return None


FLAGS = ("front", "anchored", "nomouth")


def _is_flag(word):
    return word in FLAGS or word.startswith("stripes:")


def read_palette(path):
    """[(name, linear rgb, [reference shades], {flags})] from a palette file."""
    pal = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            tokens = line.split(";")[0].split()
            rgb = _hex(tokens[0]) if tokens else None
            if rgb is None:
                continue
            words = [t for t in tokens[1:] if not t.startswith("~")]
            name = next((t for t in words if not _is_flag(t)), "color%d" % len(pal))
            refs = [r for r in (_hex(t[1:]) for t in tokens[1:] if t.startswith("~")) if r is not None]
            pal.append((name, rgb, [rgb] + refs, {t for t in words if _is_flag(t)}))
    if not pal:
        raise SystemExit("ERROR: no colors in palette " + path)
    return pal


def _concept_pixels(image_path):
    """Linear rgb (h, w, 3) with row 0 at the TOP, and the foreground mask (plain background)."""
    import numpy as np
    img = bpy.data.images.load(image_path)
    w, h = img.size
    ch = img.channels
    px = np.empty(w * h * ch, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    px = px.reshape(h, w, ch)[::-1]  # Blender stores the bottom row first
    rgb = px[:, :, :3]
    alpha = px[:, :, 3] if ch == 4 else np.ones((h, w), dtype=np.float32)
    corners = np.array([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    bg = np.median(corners, axis=0)
    mask = (alpha > 0.9) & (np.abs(rgb - bg).max(2) > 0.08)
    for _ in range(2):  # drop anti-aliased edge pixels (half background)
        mask = mask & np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1)
    return _srgb_to_linear(rgb), mask


def extract_palette(image_path, k=12, min_share=0.002):
    """Flat colors of a concept picture on a plain background: foreground pixels clustered in
    OKLab. Each cluster's color is its lit half (the concept's facets carry light and shadow).
    Shades of one material come out as separate entries; merge or rename them in the file."""
    import numpy as np
    rgb, mask = _concept_pixels(image_path)
    lin = rgb[mask]
    rng = np.random.default_rng(3)
    if len(lin) > 40000:
        lin = lin[rng.choice(len(lin), 40000, replace=False)]
    lab = _to_oklab(lin)
    labels = _kmeans(lab, k)
    out = []
    for j in np.unique(labels):
        members = labels == j
        share = members.mean()
        if share < min_share:
            continue
        lit = members & (lab[:, 0] >= np.median(lab[members, 0]))
        col = lin[lit].mean(0)
        L, a, b = _to_oklab(col[None])[0]
        out.append((share, col, L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360))
    out.sort(key=lambda o: -o[0])
    return out


def write_palette(path, clusters):
    with open(path, "w", encoding="utf-8") as f:
        f.write("; flat colors for rig_and_animate.py --palette (edit freely: '#rrggbb name')\n")
        for i, (share, col, L, C, hue) in enumerate(clusters):
            f.write("%s  color%d   ; %.1f%%  L=%.2f C=%.3f hue=%.0f\n" % (_linear_to_hex(col), i, share * 100, L, C, hue))
    info("palette written: " + path)


def _nearest_material(lab, palette, weights=(0.8, 1.0, 1.0), allowed=None):
    import numpy as np
    use = [i for i in range(len(palette)) if allowed is None or i in allowed]
    ref_rgb = [r for i in use for r in palette[i][2]]
    ref_owner = np.array([i for i in use for _r in palette[i][2]])
    ref_lab = _to_oklab(np.array(ref_rgb))
    out = np.empty(len(lab), dtype=int)
    for s in range(0, len(lab), 20000):  # chunks keep the distance matrix small
        chunk = lab[s:s + 20000]
        d = (((chunk[:, None, :] - ref_lab[None]) * np.array(weights)) ** 2).sum(2)
        out[s:s + 20000] = ref_owner[d.argmin(1)]
    return out


def _mode_filter(img_labels, passes=2):
    """3x3 majority on a label image (-1 = background stays): removes the concept's paper grain."""
    import numpy as np
    ids = [i for i in np.unique(img_labels) if i >= 0]
    for _ in range(passes):
        counts = []
        for i in ids:
            m = (img_labels == i).astype(np.int16)
            s = sum(np.roll(np.roll(m, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
            counts.append(s)
        best = np.array(ids)[np.argmax(np.array(counts), axis=0)]
        img_labels = np.where(img_labels >= 0, best, -1)
    return img_labels


def _keep_features_on_face(img_labels, mask, concept_lab, palette, free):
    """Face features ("front" materials: pupils, brows, mouth) only exist around the eyes.
    Deep shadows elsewhere in the picture (watermelon stripes, creases) look just as dark, so
    outside a box around the eye whites they fall back to the nearest ordinary material."""
    import numpy as np
    eye = next((i for i, m in enumerate(palette) if m[0] == "eyes"), None)
    front = [i for i, m in enumerate(palette) if "front" in m[3] and i != eye]
    if eye is None or not front or (img_labels == eye).sum() < 50:
        return
    ys, xs = np.nonzero(img_labels == eye)
    x0, x1 = np.percentile(xs, [1, 99])
    y0, y1 = np.percentile(ys, [1, 99])
    ew, eh = x1 - x0, y1 - y0
    rows, cols = np.indices(img_labels.shape)
    below = 0.4 if "nomouth" in palette[eye][3] else 1.8  # room for the mouth under the eyes
    on_face = (cols > x0 - 0.2 * ew) & (cols < x1 + 0.2 * ew) & (rows > y0 - 1.0 * eh) & (rows < y1 + below * eh)
    # ...and leaf / stem colors never sit on the face (shadows at the eye edges look olive)
    anchored = [i for i, m in enumerate(palette) if "anchored" in m[3]]
    idx = np.full(mask.shape, -1, dtype=int)
    idx[mask] = np.arange(mask.sum())
    total = 0
    for stray, allowed in ((np.isin(img_labels, front) & ~on_face, free),
                           (np.isin(img_labels, anchored) & on_face, set(range(len(palette))) - set(anchored))):
        if stray.any() and allowed:
            img_labels[stray] = _nearest_material(concept_lab[idx[stray]], palette, allowed=allowed)
            total += stray.sum()
    info("face box %dx%d px; %d stray pixels recolored" % (ew * 1.4, eh * (2.0 + below), total))


def _fit_front_projection(co, mask):
    """TripoSR's mesh seen from the front (-Y, Blender) is the input picture. Find the image
    placement of the X/Z silhouette (bbox fit + small search for scale, shift and mirroring)."""
    import numpy as np
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    bx, by = (xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0
    x, z = co[:, 0], co[:, 2]
    mx, mz = (x.min() + x.max()) / 2.0, (z.min() + z.max()) / 2.0
    sx0 = (xs.max() - xs.min()) / max(x.max() - x.min(), 1e-6)
    sz0 = (ys.max() - ys.min()) / max(z.max() - z.min(), 1e-6)
    grow = mask | np.roll(mask, 1, 0) | np.roll(mask, 1, 1)

    def place(p, flip, s, dx, dy):
        col = bx + dx + (p[:, 0] - mx) * sx0 * s * (-1.0 if flip else 1.0)
        row = by + dy - (p[:, 2] - mz) * sz0 * s
        return col, row

    sample = co[::2]

    def score(flip, s, dx, dy):
        col, row = place(sample, flip, s, dx, dy)
        ok = (col >= 0) & (col < w - 1) & (row >= 0) & (row < h - 1)
        proj = np.zeros_like(mask)
        proj[row[ok].astype(int), col[ok].astype(int)] = True
        proj = proj | np.roll(proj, 1, 0) | np.roll(proj, 1, 1) | np.roll(proj, -1, 0) | np.roll(proj, -1, 1)
        return (proj & grow).sum() / max((proj | mask).sum(), 1)

    # coarse, then fine around the best
    best = max(((score(f, s, dx, dy), (f, s, dx, dy)) for f in (False, True)
                for s in np.arange(0.85, 1.151, 0.05) for dx in range(-16, 17, 4) for dy in range(-16, 17, 4)),
               key=lambda b: b[0])
    f0, s0, dx0, dy0 = best[1]
    best = max(((score(f0, s, dx, dy), (f0, s, dx, dy)) for s in np.arange(s0 - 0.025, s0 + 0.026, 0.0125)
                for dx in range(dx0 - 2, dx0 + 3) for dy in range(dy0 - 2, dy0 + 3)), key=lambda b: b[0])
    info("front projection fit: IoU %.3f (mirror=%s scale=%.3f shift=%d,%d)" % (best[0], *best[1]))
    params = best[1]
    return lambda p: place(p, *params)


def _calibrate(lab, target_lab):
    """Match the AI colors' lightness histogram and chroma to the concept (TripoSR bakes darker,
    duller colors than the picture it was given)."""
    import numpy as np
    qs = np.linspace(0.0, 1.0, 201)
    out = lab.copy()
    out[:, 0] = np.interp(lab[:, 0], np.quantile(lab[:, 0], qs), np.quantile(target_lab[:, 0], qs))
    c_src = np.median(np.hypot(lab[:, 1], lab[:, 2]))
    c_dst = np.median(np.hypot(target_lab[:, 1], target_lab[:, 2]))
    out[:, 1:] *= c_dst / max(c_src, 1e-6)
    return out


def lowpoly_paint(obj, faces, palette, protect=1.0, concept=None, voxel=110, smooth=3):
    """Concept low-poly look: dense clean surface -> each face gets a palette material (front
    faces straight from the concept picture, the rest from the AI colors) -> speckles removed ->
    decimated while color borders (eyes, brows, mouth, leaf) are protected -> flat faces with
    one palette color each."""
    import numpy as np
    src = obj.data.copy()
    colors = read_point_colors(src)
    if not colors:
        raise SystemExit("ERROR: --palette needs a mesh with vertex colors")
    height = max(obj.dimensions)
    mod = obj.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = height / float(voxel)  # finer keeps thin arms and legs
    sm = obj.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = smooth
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    mesh = obj.data

    # 1) every dense face: palette material from its AI color (lightness counts less: shading)
    tree = KDTree(len(src.vertices))
    for i, v in enumerate(src.vertices):
        tree.insert(v.co, i)
    tree.balance()
    face_rgb = np.array([np.mean([colors[idx][:3] for _c, idx, _d in tree.find_n(p.center, 6)], axis=0)
                         for p in mesh.polygons])
    bpy.data.meshes.remove(src)
    lab = _to_oklab(face_rgb)
    projected = np.zeros(len(mesh.polygons), dtype=bool)
    img_labels = None
    # Eye / pupil colors only come from the picture: the AI invents blotches of them elsewhere
    free = {i for i, m in enumerate(palette) if not (concept and "front" in m[3])}
    if concept:
        rgb, mask = _concept_pixels(concept)
        concept_lab = _to_oklab(rgb[mask])
        lab = _calibrate(lab, concept_lab)
        img_labels = np.full(mask.shape, -1, dtype=int)
        img_labels[mask] = _nearest_material(concept_lab, palette)
        _keep_features_on_face(img_labels, mask, concept_lab, palette, free)
        img_labels = _mode_filter(img_labels)
    labels = _nearest_material(lab, palette, allowed=free)
    neighbours = _face_neighbours(mesh)
    labels = _majority_filter(mesh, labels, passes=3, neighbours=neighbours)

    # 2) front faces take the concept picture itself: crisp eyes, brows and mouth
    if img_labels is not None:
        h, w = img_labels.shape
        centers = np.array([p.center[:] for p in mesh.polygons])
        normals = np.array([p.normal[:] for p in mesh.polygons])
        project = _fit_front_projection(np.array([v.co[:] for v in mesh.vertices]), mask)
        col, row = project(centers)
        c = np.clip(np.round(col).astype(int), 0, w - 1)
        r = np.clip(np.round(row).astype(int), 0, h - 1)
        # Depth buffer from the camera side (-Y): only the frontmost surface sees the picture
        depth = np.full((h, w), np.inf)
        np.minimum.at(depth, (r, c), centers[:, 1])
        for _ in range(2):
            depth = np.minimum.reduce([depth, np.roll(depth, 1, 0), np.roll(depth, -1, 0),
                                       np.roll(depth, 1, 1), np.roll(depth, -1, 1)])
        tol = 0.03 * max(obj.dimensions)
        # Grazing faces and the silhouette rim would pick up the picture's rim shadows
        inner = mask.copy()
        for _ in range(3):
            inner = inner & np.roll(inner, 1, 0) & np.roll(inner, -1, 0) & np.roll(inner, 1, 1) & np.roll(inner, -1, 1)
        # ...but face features sitting on the curve of the body still need the picture
        feature = np.isin(img_labels[r, c], [i for i, m in enumerate(palette) if "front" in m[3]])
        facing = (normals[:, 1] < -0.45) | (feature & (normals[:, 1] < 0.05))
        projected = facing & (centers[:, 1] <= depth[r, c] + tol) & inner[r, c]
        labels[projected] = img_labels[r[projected], c[projected]]
        # Holes inside eyes / brows (faces on the back of a bump of the AI mesh) close up
        front_ids = [i for i, m in enumerate(palette) if "front" in m[3]]
        filled = 0
        for _ in range(6):
            new = labels.copy()
            grown = projected.copy()
            for i in np.flatnonzero(~projected):
                around = [labels[j] for j in neighbours[i] if projected[j] and labels[j] in front_ids]
                if len(around) >= 2:
                    new[i] = max(set(around), key=around.count)
                    grown[i] = True
            filled += int(grown.sum() - projected.sum())
            labels, projected = new, grown
        info("front faces painted from the concept: %d of %d (%d holes filled)" % (projected.sum(), len(labels), filled))

    # 3) small islands join their surroundings; leaf/stem patches unconnected to the picture too
    labels = _remove_islands(neighbours, labels, max(8, len(labels) // 3000))
    if img_labels is not None:
        anchored = {i for i, m in enumerate(palette) if m[3] & {"front", "anchored"}}
        labels = _drop_unanchored(neighbours, labels, projected, anchored)

    labels = _apply_stripes(mesh, labels, palette)

    # 4) decimate; vertices on the borders of face features / leaf / stem are locked (weight 0
    # in the "free" group). Pattern borders (stripes) stay free: faceted stripes look right.
    locked = {i for i, m in enumerate(palette) if m[3] & {"front", "anchored"}}
    first = {}
    border = set()
    for p in mesh.polygons:
        lab = labels[p.index]
        for v in p.vertices:
            other = first.setdefault(v, lab)
            if other != lab and (other in locked or lab in locked):
                border.add(v)
    vg = obj.vertex_groups.new(name="DecimateFree")
    vg.add([i for i in range(len(mesh.vertices)) if i not in border], 1.0, "REPLACE")
    centers = [p.center.copy() for p in mesh.polygons]
    dense_labels = labels
    current = sum(len(p.vertices) - 2 for p in mesh.polygons)
    if faces > 0 and current > faces:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = faces / current
        dec.vertex_group = vg.name
        dec.vertex_group_factor = protect
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)
    obj.vertex_groups.remove(obj.vertex_groups[vg.name])
    mesh = obj.data

    # 5) low-poly faces take the dense labels around their center; lone faces follow neighbours
    ftree = KDTree(len(centers))
    for i, c in enumerate(centers):
        ftree.insert(c, i)
    ftree.balance()
    labels = np.zeros(len(mesh.polygons), dtype=int)
    for p in mesh.polygons:
        vals = [int(dense_labels[idx]) for _c, idx, _d in ftree.find_n(p.center, 3)]
        labels[p.index] = max(set(vals), key=vals.count)
    neighbours = _face_neighbours(mesh)
    for _ in range(2):
        new = labels.copy()
        for i, nb in enumerate(neighbours):
            if nb and not any(labels[j] == labels[i] for j in nb):
                vals, counts = np.unique(labels[nb], return_counts=True)
                new[i] = vals[counts.argmax()]
        labels = new

    attr = mesh.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    for p in mesh.polygons:
        c = list(palette[labels[p.index]][1]) + [1.0]
        for li in p.loop_indices:
            attr.data[li].color = c
    mesh.color_attributes.active_color = attr
    for p in mesh.polygons:
        p.use_smooth = False
    used = np.bincount(labels, minlength=len(palette))
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    info("low-poly: %d -> %d triangles, %d border verts protected; faces per color: %s" % (
        current, tris, len(border), ", ".join("%s=%d" % (palette[i][0], n) for i, n in enumerate(used))))


def _apply_stripes(mesh, labels, palette):
    """Flag "stripes:N" on a material paints N wavy meridian bands of it over the base material
    (the first palette line), like a watermelon. The AI only guesses the stripes on the back,
    so they are drawn for the whole body; the top cap (leaves, stem) keeps its colors."""
    import numpy as np
    for idx, (name, _c, _r, flags) in enumerate(palette):
        count = next((int(f.split(":")[1]) for f in flags if f.startswith("stripes:")), 0)
        if count <= 0:
            continue
        body = (labels == 0) | (labels == idx)
        centers = np.array([p.center[:] for p in mesh.polygons])
        cx, cy = centers[body, 0].mean(), centers[body, 1].mean()
        z0, z1 = centers[:, 2].min(), centers[:, 2].max()
        zn = (centers[:, 2] - z0) / max(z1 - z0, 1e-6)
        az = np.arctan2(centers[:, 1] - cy, centers[:, 0] - cx)
        wiggle = 0.07 * np.sin(zn * 9.0 + az * 2.0) + 0.03 * np.sin(zn * 23.0)
        band = np.sin(count * (az + wiggle)) > 0.2
        paint = body & (zn < 0.9)
        labels = labels.copy()
        labels[paint] = np.where(band[paint], idx, 0)
        info("%s: %d stripes" % (name, count))
    return labels


def _islands(neighbours, labels):
    """Connected patches of one color: [face indices], ..."""
    import numpy as np
    seen = np.zeros(len(labels), dtype=bool)
    out = []
    for start in range(len(labels)):
        if seen[start]:
            continue
        lab = labels[start]
        island = [start]
        seen[start] = True
        k = 0
        while k < len(island):
            for n in neighbours[island[k]]:
                if not seen[n] and labels[n] == lab:
                    seen[n] = True
                    island.append(n)
            k += 1
        out.append(island)
    return out


def _absorb(neighbours, labels, island):
    """The patch takes the most common color around it."""
    import numpy as np
    members = set(island)
    around = [labels[n] for f in island for n in neighbours[f] if n not in members]
    if around:
        vals, counts = np.unique(around, return_counts=True)
        labels[island] = vals[counts.argmax()]
        return True
    return False


def _remove_islands(neighbours, labels, min_size):
    """Connected same-color patches smaller than min_size faces take the color around them."""
    labels = labels.copy()
    changed = sum(_absorb(neighbours, labels, isl) for isl in _islands(neighbours, labels) if len(isl) < min_size)
    info("removed %d color islands under %d faces" % (changed, min_size))
    return labels


def _drop_unanchored(neighbours, labels, projected, materials):
    """Patches of these materials that the concept picture shows nowhere are AI blotches."""
    labels = labels.copy()
    changed = sum(_absorb(neighbours, labels, isl) for isl in _islands(neighbours, labels)
                  if labels[isl[0]] in materials and not projected[isl].any())
    info("removed %d unanchored patches (leaf/stem/eye colors not seen in the concept)" % changed)
    return labels


# ----------------------------------------------------------------------------- rig


def detect_limbs(obj, force_arms=False, force_legs=False):
    """Very small shape analysis. Blender space: Z up, the character faces -Y."""
    co = [v.co.copy() for v in obj.data.vertices]
    zmin = min(c.z for c in co)
    zmax = max(c.z for c in co)
    h = zmax - zmin
    cx = sum(c.x for c in co) / len(co)
    cy = sum(c.y for c in co) / len(co)
    width = max(c.x for c in co) - min(c.x for c in co)
    shape = {"zmin": zmin, "zmax": zmax, "h": h, "cx": cx, "cy": cy, "legs": None, "arms": None}

    # Legs: two separate clusters touching the ground, with little mesh between them
    low = [c for c in co if c.z < zmin + 0.18 * h]
    left = [c for c in low if c.x < cx - 0.05 * width]
    right = [c for c in low if c.x > cx + 0.05 * width]
    middle = [c for c in low if abs(c.x - cx) < 0.06 * width and c.z < zmin + 0.06 * h]
    separated = len(left) > 0.2 * len(low) and len(right) > 0.2 * len(low) and len(middle) < 0.08 * len(low)
    if separated or (force_legs and left and right):
        def foot(pts):
            return Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), zmin))
        shape["legs"] = (foot(left), foot(right))

    # Arms: the side silhouette sticks out clearly more than the body does elsewhere
    slices = 24
    half = [0.0] * slices
    for c in co:
        i = min(int((c.z - zmin) / h * slices), slices - 1)
        half[i] = max(half[i], abs(c.x - cx))
    body_r = sorted(x for x in half if x > 0)[len([x for x in half if x > 0]) // 2]
    # Hands/fists of mascots hang low, next to the lower half of the body
    band = [c for c in co if zmin + 0.2 * h < c.z < zmin + 0.7 * h]
    arms = []
    for sign in (-1, 1):
        side = [c for c in band if (c.x - cx) * sign > 0]
        if not side:
            break
        extreme = max(abs(c.x - cx) for c in side)
        info("arm check side %+d: reach %.3f vs body %.3f" % (sign, extreme, body_r))
        if extreme < body_r * 1.25 and not force_arms:
            break
        tip = [c for c in side if abs(c.x - cx) > extreme * 0.88]
        hand = Vector((sum(p.x for p in tip) / len(tip), sum(p.y for p in tip) / len(tip),
                       sum(p.z for p in tip) / len(tip)))
        # Arms hang: the shoulder sits above the fist, a bit closer to the body center
        shoulder = Vector((cx + (hand.x - cx) * 0.72, cy, min(hand.z + 0.2 * h, zmin + 0.72 * h)))
        arms.append((shoulder, hand))
    if len(arms) == 2:
        shape["arms"] = tuple(arms)

    info("limbs: legs=%s arms=%s" % (shape["legs"] is not None, shape["arms"] is not None))
    return shape


def _add_end_bones(eb):
    """A small child bone at the tip of each arm bone (hand.L / hand.R, not deforming): a leaf bone has
    no length in a glTF skeleton, so the game (WeaponGripModifier.bone_length) reads the arm length
    from the distance to this child. Idempotent. Named without "arm" so the arm lookup skips them."""
    for side in ("L", "R"):
        p = eb.get("arm." + side)
        if p is None or ("hand." + side) in eb:
            continue
        d = (p.tail - p.head).normalized()
        b = eb.new("hand." + side)
        b.head = p.tail
        b.tail = p.tail + d * 0.05
        b.parent = p
        b.use_connect = True
        b.use_deform = False


def build_armature(obj, s):
    zmin, h, cx, cy = s["zmin"], s["h"], s["cx"], s["cy"]
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.view_layer.objects.active
    arm.name = "Rig"
    eb = arm.data.edit_bones
    root = eb[0]
    root.name = "root"
    root.head = (cx, cy, zmin)
    root.tail = (cx, cy, zmin + 0.12 * h)
    root.use_deform = False

    def bone(name, head, tail, parent, connect=False):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.parent = parent
        b.use_connect = connect
        return b

    body = bone("body", (cx, cy, zmin + 0.22 * h), (cx, cy, zmin + 0.68 * h), root)
    bone("head", body.tail, (cx, cy, s["zmax"]), body, connect=True)
    if s["legs"]:
        for name, foot in zip(("leg.L", "leg.R"), s["legs"]):
            hip = Vector((foot.x, foot.y, zmin + 0.30 * h))
            bone(name, hip, foot + Vector((0, 0, 0.02 * h)), root)
    if s["arms"]:
        for name, (shoulder, hand) in zip(("arm.L", "arm.R"), s["arms"]):
            bone(name, shoulder, hand, body)
    _add_end_bones(eb)

    # Z axis of every bone points forward (-Y): X = pitch, Z = side tilt, Y = twist
    for b in eb:
        b.align_roll(Vector((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")

    # Skin with automatic (bone heat) weights
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    _repair_weights(obj, arm)
    return arm


def _repair_weights(obj, arm):
    """Bone heat can leave vertices without weights: give them to the nearest bone."""
    bones = [b for b in arm.data.bones if b.use_deform]
    groups = {g.name: g for g in obj.vertex_groups}
    for b in bones:
        if b.name not in groups:
            groups[b.name] = obj.vertex_groups.new(name=b.name)
    fixed = 0
    for v in obj.data.vertices:
        if sum(g.weight for g in v.groups) > 1e-4:
            continue
        best, best_d = None, 1e9
        for b in bones:
            a, t = b.head_local, b.tail_local
            ab = t - a
            f = max(0.0, min(1.0, (v.co - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (v.co - (a + ab * f)).length
            if d < best_d:
                best, best_d = b, d
        groups[best.name].add([v.index], 1.0, "REPLACE")
        fixed += 1
    info(f"skinned to {len(bones)} bones, repaired {fixed} unweighted vertices")


# ----------------------------------------------------------------------------- animation
# Hand-authored KEY POSE tables: {clip: (frames, loop, [(frame, pose), ...])}. Between keys Blender
# interpolates with smooth bezier curves; a pose repeated on two frames is a hold (used only at
# impacts: hit snap, land squash, attack strike, death topple). Poses are dicts of channels, 0 = rest:
#   root_y (fraction of height), body_rx (+ leans forward), body_ry (+ turns to the character's
#   LEFT, so the right shoulder comes forward), body_rz (+ tilts to the character's left),
#   body_s (Y scale, volume kept), head_rx / head_rz,
#   arm_r / arm_l (+ swings forward and up, ~3 = straight up), arm_r_out / arm_l_out (+ outward),
#   leg_r / leg_l (+ foot forward).
# "r" is the CHARACTER's right = -X in Blender (the character faces -Y). The bones keep their old
# names (the one at -X is called "arm.L" / "leg.L"), so sides are resolved by rest position and every
# axis sign is calibrated on the rig itself (_calibrate) - no assumptions about bone roll.

TAU = math.tau


def P(**kw):
    return kw


def mirror(p):
    q = {}
    for k, v in p.items():
        if k.startswith(("arm_r", "leg_r")):
            q[k.replace("_r", "_l", 1)] = v
        elif k.startswith(("arm_l", "leg_l")):
            q[k.replace("_l", "_r", 1)] = v
        elif k in ("body_rz", "head_rz", "body_ry", "head_ry"):
            q[k] = -v
        else:
            q[k] = v
    return q


def _mirrored_cycle(first_half, half):
    """Keys of one half step + the same mirrored half a half-cycle later + the loop point."""
    keys = list(first_half)
    keys += [(f + half, mirror(p)) for f, p in first_half]
    keys.append((half * 2, first_half[0][1]))
    return keys


# Death pose per body type: bounce (round: bounces and rolls onto its side), topple (tall: slow
# fall like a tree), thud (heavy: knees buckle, hard drop, shudder), spin (small: spun around, then flat)
DEATH_KIND = {
    "Apple": "bounce", "Tomato": "bounce", "Beet": "bounce",
    "Banana": "topple", "Carrot": "topple", "Corn": "topple",
    "Pumpkin": "thud", "Watermelon": "thud", "Pineapple": "thud", "Broccoli": "thud",
    "Grape": "spin", "Lemon": "spin", "Pepper": "spin",
}


def _back(t, **kw):
    """Lying on the back, t = 0 standing .. 1 flat: the whole rig (legs too) pitches about the feet,
    shifted forward / up so the body ends up where it stood."""
    d = dict(root_rx=-1.45 * t, root_fz=0.42 * t, root_y=0.2 * t)
    d.update(kw)
    return P(**d)


def _side(t, sg=1.0, **kw):
    d = dict(root_rz=1.45 * sg * t, root_x=-0.42 * sg * t, root_y=0.2 * t)
    d.update(kw)
    return P(**d)


_RELAXED = dict(body_s=0.93, head_rx=-0.15, arm_r=0.2, arm_l=0.1, arm_r_out=0.5, arm_l_out=0.6, leg_r=0.45, leg_l=0.15)


def _death_variant(kind, d_hit, flat, rest):
    rl = _RELAXED
    if kind == "bounce":
        # round: hops back, rolls and ends on its side
        return [
            (0, P()), (2, d_hit), (3, d_hit),
            (7, _back(0.2, root_y=0.12, body_s=1.03, head_rx=-0.3, arm_r=0.9, arm_l=0.9, arm_r_out=0.4, arm_l_out=0.4)),
            (11, _side(0.45, 1.0, root_y=0.14, body_s=0.97, body_rx=-0.3, arm_r=0.7, arm_l=0.7, arm_r_out=0.5, arm_l_out=0.5)),
            (14, _side(0.9, 1.0, root_y=0.2, body_s=0.95, arm_r=0.4, arm_l=0.4, arm_r_out=0.5, arm_l_out=0.5, leg_r=0.3)),
            (17, _side(1.0, 1.0, **rl)), (19, _side(1.0, 1.0, **rl)),
            (21, _side(1.0, 1.0, **dict(rl, root_y=0.23))),
            (23, _side(1.0, 1.0, **rl)), (24, _side(1.0, 1.0, **rl)),
        ]
    if kind == "topple":
        # tall: slow wobble, then falls like a felled tree, one small bounce
        return [
            (0, P()),
            (3, P(body_s=0.98, body_rx=0.1, body_rz=0.06, head_rx=-0.1, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.4, arm_l_out=0.4)),
            (7, _back(0.05, body_rx=-0.1, body_rz=-0.05, head_rx=-0.2, arm_r=0.5, arm_l=0.5, arm_r_out=0.6, arm_l_out=0.6)),
            (12, _back(0.3, head_rx=-0.3, arm_r=1.0, arm_l=0.8, arm_r_out=0.7, arm_l_out=0.7)),
            (16, _back(0.8, head_rx=-0.3, arm_r=0.7, arm_l=0.7, arm_r_out=0.6, arm_l_out=0.6)),
            (19, flat), (20, flat),
            (22, _back(0.95, **dict(rl, root_y=0.225))),
            (24, rest),
        ]
    if kind == "thud":
        # heavy: knees buckle, hard drop, falls back and shudders
        drop = P(root_y=-0.03, body_s=0.85, body_rx=0.15, head_rx=0.1, arm_r=0.2, arm_l=0.2, arm_r_out=0.5, arm_l_out=0.5, leg_r=0.5, leg_l=0.5)
        shake_a = _back(1.0, **dict(rl, body_rz=0.06))
        shake_b = _back(1.0, **dict(rl, body_rz=-0.06))
        return [
            (0, P()), (2, d_hit), (4, d_hit),
            (8, drop), (10, drop),
            (13, _back(0.45, body_s=0.9, head_rx=-0.3, arm_r=0.8, arm_l=0.8, arm_r_out=0.6, arm_l_out=0.6, leg_r=0.4, leg_l=0.3)),
            (15, flat), (16, flat),
            (17, shake_a), (18, shake_b), (19, shake_a), (20, shake_b),
            (22, rest), (24, rest),
        ]
    if kind == "spin":
        # small: knocked up and spun around, lands on its side
        tw = 6.2832
        return [
            (0, P()), (2, d_hit),
            (5, P(root_y=0.12, body_s=1.05, body_rx=-0.3, body_ry=1.6, head_rx=-0.3, arm_r=1.5, arm_l=1.5, arm_r_out=0.7, arm_l_out=0.7, leg_r=0.4, leg_l=-0.3)),
            (9, P(root_y=0.16, body_s=1.0, body_rx=-0.4, body_ry=4.2, head_rx=-0.3, arm_r=1.5, arm_l=1.5, arm_r_out=0.7, arm_l_out=0.7, leg_r=-0.3, leg_l=0.4)),
            (13, _side(0.5, -1.0, root_y=0.2, body_s=0.95, body_ry=5.8, head_rx=-0.3, arm_r=1.0, arm_l=1.0, arm_r_out=0.6, arm_l_out=0.6)),
            (16, _side(1.0, -1.0, **dict(rl, body_ry=tw))), (18, _side(1.0, -1.0, **dict(rl, body_ry=tw))),
            (20, _side(1.0, -1.0, **dict(rl, body_ry=tw, root_y=0.225))),
            (22, _side(1.0, -1.0, **dict(rl, body_ry=tw))), (24, _side(1.0, -1.0, **dict(rl, body_ry=tw))),
        ]
    return None


def _clip_tables(death_kind=""):
    # idle: breathing + slow weight shift, 48 loop
    idle = [
        (0, P()),
        (12, P(body_s=1.015, body_rz=0.02, head_rx=0.03, arm_r_out=0.06, arm_l_out=0.06)),
        (24, P(body_s=1.035, head_rx=0.0, arm_r_out=0.12, arm_l_out=0.12, arm_r=0.03, arm_l=0.03)),
        (36, P(body_s=1.015, body_rz=-0.02, head_rx=-0.03, arm_r_out=0.06, arm_l_out=0.06)),
        (48, P()),
    ]
    # walk: contact 0, down 3, passing 6, up 9, mirrored 12-21, 24 loop
    walk_half = [
        (0, P(root_y=-0.01, body_rx=0.07, body_rz=0.04, body_ry=-0.12, head_rz=-0.03, leg_r=0.7, leg_l=-0.7, arm_r=-0.65, arm_l=0.65, arm_r_out=0.06, arm_l_out=0.06)),
        (3, P(root_y=-0.035, body_s=0.98, body_rx=0.08, body_rz=0.06, body_ry=-0.06, head_rz=-0.04, leg_r=0.48, leg_l=-0.5, arm_r=-0.4, arm_l=0.4, arm_r_out=0.07, arm_l_out=0.07)),
        (6, P(root_y=0.0, body_rx=0.07, body_rz=0.0, body_ry=0.0, leg_r=0.0, leg_l=-0.05, arm_r=0.0, arm_l=0.0, arm_r_out=0.09, arm_l_out=0.09)),
        (9, P(root_y=0.035, body_s=1.015, body_rx=0.06, body_rz=-0.05, body_ry=0.06, head_rz=0.04, leg_r=-0.42, leg_l=0.42, arm_r=0.4, arm_l=-0.4, arm_r_out=0.07, arm_l_out=0.07)),
    ]
    walk = _mirrored_cycle(walk_half, 12)
    # run: contact 0 (lean), down 2 (squash), passing 4, flight 6 (stretch, arms pump), mirrored 8-14
    run_half = [
        (0, P(root_y=-0.01, body_rx=0.25, body_rz=0.07, body_ry=-0.3, head_rx=-0.12, leg_r=1.15, leg_l=-1.1, arm_r=-1.3, arm_l=1.3, arm_r_out=0.1, arm_l_out=0.1)),
        (2, P(root_y=-0.06, body_s=0.94, body_rx=0.27, body_rz=0.1, body_ry=-0.15, head_rx=-0.14, leg_r=0.7, leg_l=-0.75, arm_r=-0.8, arm_l=0.8, arm_r_out=0.1, arm_l_out=0.1)),
        (4, P(root_y=0.0, body_rx=0.25, body_ry=0.0, head_rx=-0.12, leg_r=0.0, leg_l=-0.1, arm_r=0.0, arm_l=0.0, arm_r_out=0.12, arm_l_out=0.12)),
        (6, P(root_y=0.13, body_s=1.06, body_rx=0.22, body_rz=-0.08, body_ry=0.3, head_rx=-0.1, leg_r=-1.2, leg_l=1.15, arm_r=1.4, arm_l=-1.4, arm_r_out=0.1, arm_l_out=0.1)),
    ]
    run = _mirrored_cycle(run_half, 8)
    # jump 20: crouch, takeoff stretch, apex tuck, open into the fall
    jump = [
        (0, P()),
        (4, P(root_y=-0.02, body_s=0.8, body_rx=0.2, head_rx=-0.1, arm_r=-0.7, arm_l=-0.7, arm_r_out=0.2, arm_l_out=0.2, leg_r=0.1, leg_l=0.1)),
        (7, P(root_y=0.05, body_s=1.15, body_rx=-0.05, head_rx=-0.1, arm_r=2.3, arm_l=2.3, arm_r_out=0.25, arm_l_out=0.25, leg_r=-0.2, leg_l=-0.2)),
        (11, P(root_y=0.07, body_s=0.97, body_rx=0.12, arm_r=1.3, arm_l=1.3, arm_r_out=0.8, arm_l_out=0.8, leg_r=0.7, leg_l=0.65)),
        (20, P(root_y=0.05, body_s=1.03, head_rx=-0.1, arm_r=1.7, arm_l=1.1, arm_r_out=0.2, arm_l_out=0.15, leg_r=0.6, leg_l=0.3)),
    ]
    # fall 12 loop: arms up / forward and uneven, knees tucked, three irregular flail poses
    fall_a = P(root_y=0.05, body_s=1.03, body_rx=0.08, head_rx=-0.1, arm_r=1.7, arm_l=1.1, arm_r_out=0.2, arm_l_out=0.15, leg_r=0.6, leg_l=0.3)
    fall_b = P(root_y=0.05, body_s=1.04, body_rx=0.05, body_rz=0.07, head_rx=-0.15, head_rz=0.08, arm_r=1.0, arm_l=1.9, arm_r_out=0.3, arm_l_out=0.2, leg_r=0.3, leg_l=0.65)
    fall_c = P(root_y=0.055, body_s=1.02, body_rx=0.12, body_rz=-0.05, head_rx=-0.05, head_rz=-0.06, arm_r=1.45, arm_l=0.7, arm_r_out=0.15, arm_l_out=0.3, leg_r=0.5, leg_l=0.45)
    fall = [(0, fall_a), (4, fall_b), (8, fall_c), (12, fall_a)]
    # land 10: squash (held at the impact), overshoot, settle
    squash = P(root_y=-0.01, body_s=0.75, body_rx=0.2, head_rx=-0.12, arm_r=0.3, arm_l=0.3, arm_r_out=0.5, arm_l_out=0.5, leg_r=0.15, leg_l=0.15)
    land = [
        (0, P(root_y=0.03, body_s=1.04, arm_r=1.4, arm_l=1.0, arm_r_out=0.3, arm_l_out=0.3, leg_r=0.4, leg_l=0.1)),
        (2, squash), (4, squash),
        (6, P(body_s=1.1, body_rx=-0.05, arm_r=0.6, arm_l=0.6, arm_r_out=0.3, arm_l_out=0.3)),
        (8, P(body_s=0.97, arm_r_out=0.1, arm_l_out=0.1)),
        (10, P()),
    ]
    # attack 12: wind-back, strike (held), follow-through. Right arm = -X.
    strike = P(root_y=0.01, body_s=1.03, body_rx=0.2, body_ry=0.45, head_rx=-0.1, arm_r=1.6, arm_l=-0.5, arm_r_out=0.0, arm_l_out=0.2)
    attack = [
        (0, P()),
        (3, P(body_s=0.96, body_rx=-0.05, body_ry=-0.35, arm_r=-1.2, arm_l=0.5, arm_r_out=0.15, arm_l_out=0.1)),
        (5, strike), (6, strike),
        (8, P(body_s=1.01, body_rx=0.15, body_ry=0.5, arm_r=1.85, arm_l=-0.4, arm_l_out=0.2)),
        (12, P()),
    ]
    # hit 10: short snap back with a backward lean (held), head whip, recover
    snap = P(body_s=0.95, body_rx=-0.3, root_rx=-0.12, head_rx=0.2, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.3, arm_l_out=0.3)
    hit = [
        (0, P()), (1, snap), (2, snap),
        (3, P(body_s=0.95, body_rx=-0.3, root_rx=-0.12, head_rx=-0.4, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.3, arm_l_out=0.3)),
        (6, P(body_s=1.0, body_rx=0.06, head_rx=0.08, arm_r_out=0.15, arm_l_out=0.15)),
        (10, P()),
    ]
    # death 24: hit (held), stagger, topple onto the back, flat (held), bounce, settle (held)
    d_hit = P(body_s=0.94, body_rx=-0.3, head_rx=-0.4, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.35, arm_l_out=0.35)
    flat = _back(1.0, **_RELAXED)
    rest = _back(1.0, **dict(_RELAXED, head_rx=-0.1, arm_r_out=0.55))
    death = [
        (0, P()), (2, d_hit), (4, d_hit),
        (9, P(body_rx=0.1, body_rz=0.2, head_rx=0.1, leg_r=0.3, leg_l=-0.2, arm_r=0.8, arm_l=-0.4, arm_r_out=0.5, arm_l_out=0.4)),
        (13, _back(0.45, body_s=0.97, head_rx=-0.3, arm_r=0.7, arm_l=0.7, arm_r_out=0.6, arm_l_out=0.6, leg_r=0.1)),
        (17, flat), (19, flat),
        (21, _back(0.95, **dict(_RELAXED, root_y=0.225))),
        (23, rest), (24, rest),
    ]
    death = _death_variant(death_kind, d_hit, flat, rest) or death
    # casts, 15 frames: anticipation 0-4, action 4-8, recovery 8-15 (weapon hidden: arms go anywhere).
    # throw: overhand with a body turn and a step
    throw = P(body_s=1.03, body_rx=0.3, body_ry=0.7, root_rx=0.1, head_ry=-0.3, arm_r=1.5, arm_l=-0.7, arm_r_out=0.0, arm_l_out=0.4, leg_r=0.4, leg_l=-0.3)
    cast_throw = [
        (0, P()),
        (4, P(body_s=0.97, body_rx=-0.1, body_ry=-0.6, root_rx=-0.05, head_ry=0.3, arm_r=-2.5, arm_l=0.9, arm_r_out=0.35, arm_l_out=0.3, leg_r=-0.2, leg_l=0.3)),
        (6, throw), (7, throw),
        (10, P(body_rx=0.3, body_ry=0.45, arm_r=0.5, arm_l=-0.3, arm_l_out=0.3)),
        (15, P()),
    ]
    # slam: rises on the toes with the arms overhead, then crashes down into a crouch
    slam = P(root_y=-0.025, body_s=0.88, body_rx=0.6, head_rx=0.2, arm_r=0.7, arm_l=0.7, arm_r_out=0.1, arm_l_out=0.1, leg_r=0.35, leg_l=-0.3)
    cast_slam = [
        (0, P()),
        (2, P(root_y=-0.01, body_s=0.88, body_rx=0.15, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.4, arm_l_out=0.4)),
        (4, P(root_y=0.06, body_s=1.1, body_rx=-0.2, head_rx=-0.25, arm_r=2.9, arm_l=2.9, arm_r_out=0.25, arm_l_out=0.25)),
        (6, slam), (8, slam),
        (11, P(body_s=0.95, body_rx=0.2, arm_r=0.3, arm_l=0.3)),
        (15, P()),
    ]

    # spray: braced, forward thrust, the whole torso shakes
    def sp(ry, rz=0.0):
        return P(body_s=0.98, body_rx=0.25, body_ry=ry, body_rz=rz, head_rx=-0.1, head_ry=-ry * 0.5, arm_r=1.35, arm_l=1.35, arm_r_out=0.1, arm_l_out=0.1, leg_r=0.3, leg_l=-0.3)

    cast_spray = [
        (0, P()),
        (4, P(body_s=0.97, body_rx=-0.12, head_rx=-0.1, arm_r=-0.5, arm_l=-0.5, arm_r_out=0.3, arm_l_out=0.3)),
        (6, sp(0.0)),
        (7, sp(0.3, 0.05)), (8, sp(-0.3, -0.05)), (9, sp(0.3, 0.05)), (10, sp(-0.3, -0.05)), (11, sp(0.25, 0.05)), (12, sp(-0.15)),
        (15, P()),
    ]
    # raise: rises on the toes, arms spread up in a V, looks up
    up = P(root_y=0.06, body_s=1.1, body_rx=-0.2, head_rx=-0.35, arm_r=2.9, arm_l=2.9, arm_r_out=0.55, arm_l_out=0.55, leg_r=-0.1, leg_l=-0.1)
    cast_raise = [
        (0, P()),
        (4, P(root_y=-0.01, body_s=0.9, body_rx=0.1, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.3, arm_l_out=0.3)),
        (8, up), (10, up),
        (12, P(root_y=0.02, body_s=1.05, arm_r=2.3, arm_l=2.3, arm_r_out=0.5, arm_l_out=0.5)),
        (15, P()),
    ]
    # dash: the whole body pitches forward, arms swept back
    dash_pose = P(root_y=0.02, root_rx=0.3, body_s=1.02, body_rx=0.4, head_rx=-0.5, arm_r=-1.9, arm_l=-1.9, arm_r_out=0.2, arm_l_out=0.2, leg_r=-0.8, leg_l=0.6)
    cast_dash = [
        (0, P()),
        (4, P(body_s=0.9, body_rx=0.15, root_rx=0.1, arm_r=-0.6, arm_l=-0.6, arm_r_out=0.2, arm_l_out=0.2, leg_r=0.3, leg_l=-0.3)),
        (6, dash_pose), (8, dash_pose),
        (11, P(root_rx=0.2, body_rx=0.3, head_rx=-0.3, arm_r=-1.1, arm_l=-1.1, arm_r_out=0.15, arm_l_out=0.15, leg_r=-0.2, leg_l=0.2)),
        (15, P()),
    ]
    # idle variants (one-shot, played now and then by CharacterAnimator): glance around, stretch, shift weight
    idle_look = [
        (0, P()),
        (10, P(body_ry=0.15, head_ry=0.8, head_rx=0.05, head_rz=0.12, arm_r_out=0.06, arm_l_out=0.06)),
        (22, P(body_ry=0.12, head_ry=0.8, head_rx=0.05, head_rz=0.12, arm_r_out=0.06, arm_l_out=0.06)),
        (34, P(body_ry=-0.15, head_ry=-0.8, head_rz=-0.12, arm_r_out=0.06, arm_l_out=0.06)),
        (46, P(body_ry=-0.12, head_ry=-0.8, head_rz=-0.12, arm_r_out=0.06, arm_l_out=0.06)),
        (60, P()),
    ]
    idle_stretch = [
        (0, P()),
        (6, P(body_s=0.93, body_rx=0.1, arm_r=-0.3, arm_l=-0.3, arm_r_out=0.2, arm_l_out=0.2)),
        (18, P(root_y=0.03, body_s=1.12, body_rx=-0.2, head_rx=-0.3, arm_r=2.8, arm_l=2.8, arm_r_out=0.45, arm_l_out=0.45)),
        (32, P(root_y=0.03, body_s=1.12, body_rx=-0.2, head_rx=-0.3, arm_r=2.8, arm_l=2.8, arm_r_out=0.45, arm_l_out=0.45)),
        (40, P(body_s=0.95, body_rx=0.12, head_rx=0.1, arm_r=0.3, arm_l=0.3, arm_r_out=0.3, arm_l_out=0.3)),
        (48, P(body_s=1.02, arm_r_out=0.1, arm_l_out=0.1)),
        (60, P()),
    ]
    idle_shift = [
        (0, P()),
        (10, P(root_y=-0.012, body_rz=0.13, body_ry=-0.12, head_rz=-0.12, leg_r=0.15, arm_r=0.15, arm_l=-0.15, arm_r_out=0.08, arm_l_out=0.16)),
        (26, P(root_y=-0.012, body_rz=0.13, body_ry=-0.12, head_rz=-0.12, leg_r=0.15, arm_r=0.15, arm_l=-0.15, arm_r_out=0.08, arm_l_out=0.16)),
        (38, P(root_y=-0.012, body_rz=-0.13, body_ry=0.12, head_rz=0.12, leg_l=0.15, arm_r=-0.15, arm_l=0.15, arm_r_out=0.16, arm_l_out=0.08)),
        (50, P(body_s=1.02, head_rx=0.08)),
        (60, P()),
    ]
    return {
        "idle_look": (60, False, idle_look), "idle_stretch": (60, False, idle_stretch),
        "idle_shift": (60, False, idle_shift),
        "idle": (48, True, idle), "walk": (24, True, walk), "run": (16, True, run),
        "jump": (20, False, jump), "fall": (12, True, fall), "land": (10, False, land),
        "attack": (12, False, attack), "hit": (10, False, hit), "death": (24, False, death),
        "cast_throw": (15, False, cast_throw), "cast_slam": (15, False, cast_slam),
        "cast_spray": (15, False, cast_spray), "cast_raise": (15, False, cast_raise),
        "cast_dash": (15, False, cast_dash),
    }


# Personality per hero: multipliers on the shared pose tables. leg / arm = stride and arm swing,
# sway = body roll / turn / head tilt, squash = body_s deviation, bounce = vertical travel,
# lean = forward lean when running, amp = size of reactions (hit / attack / casts / arms in jumps),
# stomp = extra squash on every footfall (heavy heroes), twist = spine twist (body_ry) everywhere.
_DEFAULT_STYLE = dict(leg=1.0, arm=1.0, sway=1.0, squash=1.0, bounce=1.0, lean=1.0, amp=1.0, stomp=0.0, twist=1.0)
HERO_STYLE = {
    # round: roll and waddle, big squash
    "Apple": dict(leg=0.8, arm=0.8, sway=1.7, squash=1.3, bounce=1.2),
    "Tomato": dict(leg=0.85, sway=1.6, squash=1.3, bounce=1.1, amp=1.0),
    "Beet": dict(leg=0.85, arm=0.9, sway=1.4, squash=1.2, stomp=0.02, lean=0.7),
    # heavy: stomp, land squash on each step, small reactions
    "Pumpkin": dict(leg=0.8, arm=0.8, sway=1.2, squash=1.3, bounce=0.8, stomp=0.05, amp=0.9),
    "Watermelon": dict(leg=0.75, arm=0.75, sway=1.3, squash=1.4, bounce=0.8, stomp=0.06, amp=0.9),
    "Pineapple": dict(leg=1.0, arm=0.9, sway=1.0, squash=0.9, stomp=0.03),
    "Broccoli": dict(leg=0.85, arm=1.1, sway=1.0, squash=0.4, stomp=0.03, lean=1.0),
    # tall: long stride, sway, little squash
    "Banana": dict(leg=1.1, arm=1.1, sway=1.2, squash=0.7, bounce=0.8, twist=0.4),
    "Carrot": dict(leg=1.2, sway=0.7, squash=0.6, bounce=0.8, lean=0.8),
    "Corn": dict(leg=1.15, sway=1.3, squash=0.6, bounce=0.9),
    # small: quick choppy steps, big arm pump, springy
    "Grape": dict(leg=1.1, arm=1.4, sway=1.0, squash=1.0, bounce=1.5, amp=1.1),
    "Lemon": dict(leg=1.0, arm=1.3, sway=1.2, squash=1.1, bounce=1.4, amp=1.1),
    "Pepper": dict(leg=1.15, arm=1.4, sway=0.8, bounce=1.6, lean=1.3, amp=1.2),
}
_LOCO_CLIPS = ("idle", "walk", "run", "idle_look", "idle_stretch", "idle_shift")


def style_for(name):
    s = dict(_DEFAULT_STYLE)
    s.update(HERO_STYLE.get(name, {}))
    return s


def stylize(clip, keys, st):
    out = []
    loco = clip in _LOCO_CLIPS
    gait = clip in ("walk", "run")
    for f, pose in keys:
        q = dict(pose)
        for k, v in pose.items():
            if k.startswith("leg_"):
                q[k] = v * st["leg"]
            elif k.endswith("_out") and k.startswith("arm_"):
                q[k] = v * (st["arm"] if loco else st["amp"])
            elif k.startswith("arm_"):
                q[k] = v * (st["arm"] if loco else st["amp"])
            elif k in ("body_rz", "body_ry", "head_rz"):
                q[k] = v * st["sway"] if (loco or clip == "death") else v * st["amp"]
                if k == "body_ry" and abs(v) < 3.0:
                    q[k] *= st["twist"]
            elif k == "body_s":
                q[k] = 1.0 + (v - 1.0) * st["squash"] if clip != "death" else v
                q[k] = max(q[k], 0.8)
            elif k == "root_y":
                q[k] = v * st["bounce"] if clip != "death" else v
            elif k in ("body_rx", "head_rx"):
                if gait:
                    q[k] = v * st["lean"]
                elif clip not in ("death", "land", "jump", "fall") and not loco:
                    q[k] = v * st["amp"]
        if gait and pose.get("root_y", 0.0) < -0.005 and st["stomp"]:
            q["body_s"] = q.get("body_s", 1.0) - st["stomp"]
        out.append((f, q))
    return out


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def _resolve_roles(arm):
    """Map roles to pose bones; the character's right side is -X (smaller rest x)."""
    pbs = {pb.name: pb for pb in arm.pose.bones}
    roles = {k: pbs.get(k) for k in ("root", "body", "head")}
    for kind in ("arm", "leg"):
        pair = [pbs[n] for n in (kind + ".L", kind + ".R") if n in pbs]
        pair.sort(key=lambda p: (arm.matrix_world @ p.bone.head_local).x)
        if len(pair) == 2:
            roles[kind + "_r"], roles[kind + "_l"] = pair
    return {k: v for k, v in roles.items() if v}


def _tail_world(arm, pb):
    bpy.context.view_layer.update()
    return arm.matrix_world @ pb.tail


def _bone_forward(arm, pb):
    bpy.context.view_layer.update()
    return (arm.matrix_world.to_3x3() @ pb.matrix.to_3x3()) @ Vector((0, 0, 1))


def _calibrate(arm, roles):
    """Per role: sign making +X rotation move the tip forward (-Y), and sign making +Z rotation
    move it toward the character's left (+X). The root also gets the signs of its location Z (forward)
    and X (left) - used by the death poses that tip the whole rig over."""
    cal = {}
    for role, pb in roles.items():
        reset_pose(arm)
        t0 = _tail_world(arm, pb).copy()
        pb.rotation_euler.x = 0.3
        t1 = _tail_world(arm, pb).copy()
        pb.rotation_euler.x = 0.0
        pb.rotation_euler.z = 0.3
        t2 = _tail_world(arm, pb).copy()
        fwd = 1.0 if (t1.y - t0.y) < 0 else -1.0
        left = 1.0 if (t2.x - t0.x) > 0 else -1.0
        # twist about the bone's own Y: sign making + turn the bone's forward (Z) toward the left (+X)
        pb.rotation_euler.z = 0.0
        z0 = _bone_forward(arm, pb).x
        pb.rotation_euler.y = 0.3
        z1 = _bone_forward(arm, pb).x
        pb.rotation_euler.y = 0.0
        tw = 1.0 if (z1 - z0) > 0 else -1.0
        if role == "root":
            pb.location.z = 0.1
            tz = _tail_world(arm, pb).copy()
            pb.location.z = 0.0
            pb.location.x = 0.1
            tx = _tail_world(arm, pb).copy()
            pb.location.x = 0.0
            cal[role] = (fwd, left, tw, 1.0 if (tz.y - t0.y) < 0 else -1.0, 1.0 if (tx.x - t0.x) > 0 else -1.0)
        else:
            cal[role] = (fwd, left, tw)
    reset_pose(arm)
    return cal


def apply_pose(roles, cal, pose, h):
    g = pose.get
    if "root" in roles:
        r = roles["root"]
        c = cal.get("root", (1.0, 1.0, 1.0, 1.0, 1.0))
        r.location = (c[4] * g("root_x", 0.0) * h, g("root_y", 0.0) * h, c[3] * g("root_fz", 0.0) * h)
        r.rotation_euler.x = c[0] * g("root_rx", 0.0)
        r.rotation_euler.z = c[1] * g("root_rz", 0.0)
    body = roles["body"]
    body.rotation_euler.x = cal["body"][0] * g("body_rx", 0.0)
    body.rotation_euler.y = cal["body"][2] * g("body_ry", 0.0)
    body.rotation_euler.z = cal["body"][1] * g("body_rz", 0.0)
    s = g("body_s", 1.0)
    xz = 1.0 + (1.0 - s) * 0.35
    body.scale = (xz, s, xz)
    if "head" in roles:
        roles["head"].rotation_euler.x = cal["head"][0] * g("head_rx", 0.0)
        roles["head"].rotation_euler.z = cal["head"][1] * g("head_rz", 0.0)
        roles["head"].rotation_euler.y = cal["head"][2] * g("head_ry", 0.0)
    for side in ("r", "l"):
        if "arm_" + side in roles:
            pb = roles["arm_" + side]
            a = g("arm_" + side, 0.0)
            pb.rotation_euler.x = cal["arm_" + side][0] * a
            # outward: the right arm (-X) goes toward -X = against "left"
            out = g("arm_%s_out" % side, 0.0)
            pb.rotation_euler.z = cal["arm_" + side][1] * out * (1.0 if side == "l" else -1.0)
            # the arms inherit the body scale: cancel most of it so a squashed body does not
            # stretch / thin the limbs (effective length along the arm direction)
            eff = math.sqrt((s * math.cos(a)) ** 2 + (xz * math.sin(a)) ** 2)
            pb.scale = (xz ** -0.7, eff ** -0.7, xz ** -0.7)
        if "leg_" + side in roles:
            roles["leg_" + side].rotation_euler.x = cal["leg_" + side][0] * g("leg_" + side, 0.0)


def bake_clips(arm, height, hero=""):
    st = style_for(hero)
    info("hero %r style %s" % (hero, st))
    bpy.context.scene.render.fps = FPS
    arm.animation_data_create()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    reset_pose(arm)
    roles = _resolve_roles(arm)
    cal = _calibrate(arm, roles)
    info("sides: right arm=%s right leg=%s; cal=%s" % (
        roles["arm_r"].name if "arm_r" in roles else None,
        roles["leg_r"].name if "leg_r" in roles else None, cal))
    names = []
    def _bake(name, keys):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        for f, pose in stylize(name, keys, st):
            reset_pose(arm)
            apply_pose(roles, cal, pose, height)
            for pb in arm.pose.bones:
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("rotation_euler", frame=f)
                pb.keyframe_insert("scale", frame=f)
        return act

    def _lowest(act, frame):
        arm.animation_data.action = act
        bpy.context.scene.frame_set(int(frame))
        dg = bpy.context.evaluated_depsgraph_get()
        low = 1e9
        for o in bpy.context.scene.objects:
            if o.type != "MESH" or not o.vertex_groups:  # skinned body only (not helper meshes)
                continue
            eo = o.evaluated_get(dg)
            me = eo.to_mesh()
            mw = eo.matrix_world
            low = min(low, min((mw @ v.co).z for v in me.vertices))
            eo.to_mesh_clear()
        return low

    for name, (frames, loop, keys) in _clip_tables(DEATH_KIND.get(hero, "")).items():
        act = _bake(name, keys)
        if name == "death":
            # lie flat ON the ground: measure the lowest skinned vertex at the last frame and lift / sink
            # the lying poses (weighted by how far they are tipped over) so it rests at y = 0
            last = max(f for f, _ in keys)
            dy = -_lowest(act, last)
            if abs(dy) > 0.002:
                shift = dy / height
                fixed = []
                for f, pose in keys:
                    tip = min(1.0, (abs(pose.get("root_rx", 0.0)) + abs(pose.get("root_rz", 0.0))) / 1.45)
                    q = dict(pose)
                    q["root_y"] = q.get("root_y", 0.0) + shift * tip
                    fixed.append((f, q))
                bpy.data.actions.remove(act)
                act = _bake(name, fixed)
                info("death lift %s: %.3f m -> lowest now %.3f" % (hero, dy, _lowest(act, last)))
        names.append(name)
    reset_pose(arm)
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.ops.object.mode_set(mode="OBJECT")
    info("animations: " + ", ".join(names))


def _smooth_weights(arm, iters=4, radius=0.25, keep=0.5):
    """Blend the skin weights over a few loops around the shoulders and hips (Laplacian smoothing on the
    welded mesh, only within `radius` of an arm / leg root), so joints bend smoothly instead of creasing.
    Run once on a finished GLB (--anim-only IN --smooth); every run blurs a little more."""
    heads = [arm.matrix_world @ arm.data.bones[n].head_local for n in ("arm.L", "arm.R", "leg.L", "leg.R")
             if n in arm.data.bones]
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or not o.vertex_groups:
            continue
        gname = {g.index: g.name for g in o.vertex_groups}
        V = o.data.vertices
        key = lambda v: (round(v.co.x, 3), round(v.co.y, 3), round(v.co.z, 3))
        keys = [key(v) for v in V]
        W, adj, members = {}, {}, {}
        for v, k in zip(V, keys):
            members.setdefault(k, []).append(v.index)
            if k not in W:
                W[k] = {gname[g.group]: g.weight for g in v.groups if g.weight > 0.0}
        for p in o.data.polygons:
            ks = [keys[i] for i in p.vertices]
            for i, a in enumerate(ks):
                b = ks[(i + 1) % len(ks)]
                if a != b:
                    adj.setdefault(a, set()).add(b)
                    adj.setdefault(b, set()).add(a)
        zone = [k for k in W if any((o.matrix_world @ Vector(k) - h).length < radius for h in heads)]
        for _ in range(iters):
            new = {}
            for k in zone:
                nb = adj.get(k)
                if not nb:
                    continue
                mix = {}
                for n, w in W[k].items():
                    mix[n] = w * keep
                for q in nb:
                    for n, w in W[q].items():
                        mix[n] = mix.get(n, 0.0) + w * (1.0 - keep) / len(nb)
                top = sorted(mix.items(), key=lambda t: -t[1])[:4]
                tot = sum(w for _, w in top) or 1.0
                new[k] = {n: w / tot for n, w in top if w / tot > 0.01}
            W.update(new)
        groups = {g.name: g for g in o.vertex_groups}
        for k in zone:
            for i in members[k]:
                for g in list(V[i].groups):
                    o.vertex_groups[g.group].remove([i])
                for n, w in W[k].items():
                    groups[n].add([i], w, "REPLACE")
        info("smoothed skin weights of %s: %d joint vertices, %d passes" % (o.name, len(zone), iters))


def anim_only(src, dst, smooth=False):
    """Re-bake the clips of a finished rigged GLB; meshes, paint and skin stay untouched."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if not arms:
        raise SystemExit("ERROR: no armature in " + src)
    arm = arms[0]
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    zs = [(o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    _add_end_bones(arm.data.edit_bones)
    for b in arm.data.edit_bones:  # same bone frame as build_armature: Z forward (-Y)
        b.align_roll(Vector((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    if smooth:
        _smooth_weights(arm)
    root_z = (arm.matrix_world @ arm.data.bones["root"].head_local).z
    bake_clips(arm, max(zs) - root_z, os.path.splitext(os.path.basename(src))[0])
    has_colors = any(o.data.color_attributes for o in meshes)
    export(dst, has_colors)
    print("RESULT: " + dst, flush=True)


# ----------------------------------------------------------------------------- export / main


def export(dst, has_colors):
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(
        filepath=dst,
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
    if has_colors:
        kwargs["export_vertex_color"] = "ACTIVE"
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError as e:  # option renamed in this Blender version: retry with the basics
        info(f"exporter option not supported ({e}), retrying with defaults")
        for k in ("export_vertex_color", "export_animation_mode", "export_force_sampling"):
            kwargs.pop(k, None)
        bpy.ops.export_scene.gltf(**kwargs)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv and argv[0] == "--extract":  # -- --extract CONCEPT.png OUT.palette.txt
        write_palette(argv[2], extract_palette(argv[1]))
        return
    if argv and argv[0] == "--anim-only":  # -- --anim-only IN.glb [OUT.glb]  (default: overwrite IN)
        pos = [a for a in argv[1:] if not a.startswith("--")]
        anim_only(pos[0], pos[1] if len(pos) > 1 else pos[0], "--smooth" in argv)
        return
    opts = parse_args()
    log(5, "importing mesh")
    obj = import_mesh(opts["src"])
    has_colors = bool(obj.data.color_attributes)
    palette_path = opts["palette"]
    if opts["concept"] and (not palette_path or not os.path.isfile(palette_path)):
        palette_path = palette_path or opts["dst"] + ".palette.txt"
        write_palette(palette_path, extract_palette(opts["concept"]))
    if palette_path:
        log(20, "low-poly repaint with the concept palette")
        faces = opts["faces"] if opts["faces_given"] else 3000
        lowpoly_paint(obj, faces, read_palette(palette_path), opts["protect"], opts["concept"],
                      opts["voxel"], opts["smooth"])
    elif not opts["remesh"] and (opts["flat"] or opts["faces_given"]):
        log(20, "simplifying")
        simplify(obj, opts["faces"], opts["flat"], opts["vivid"])
    if opts["remesh"] and not palette_path:
        log(20, "remeshing")
        remesh(obj, opts["faces"], opts["flat"], opts["posterize"], opts["vivid"], opts["merge_l"])
    log(45, "building skeleton")
    limbs = opts["limbs"]
    shape = detect_limbs(obj, force_arms=limbs in ("all", "arms"), force_legs=limbs in ("all", "legs"))
    arm = build_armature(obj, shape)
    log(70, "animating")
    bake_clips(arm, shape["h"], os.path.splitext(os.path.basename(opts["dst"]))[0])
    log(90, "exporting GLB")
    export(opts["dst"], has_colors)
    log(100, "done")
    print("RESULT: " + opts["dst"], flush=True)


try:
    main()
except SystemExit:
    raise
except Exception as exc:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    print(f"ERROR: {exc}", flush=True)
    sys.exit(1)
