"""Blender (5.x) batch script: clean up a character mesh, auto-rig it, add a toy animation set.

    blender -b --factory-startup -P rig_and_animate.py -- IN.glb OUT.glb [--remesh] [--faces 5000]
    ... -- IN.glb OUT.glb --palette P.palette.txt --concept INPUT.png [--faces 2500]   (concept look)
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
  5. keyframes idle, walk, run, jump, land, attack, hit, death
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
# Pose bones: rotation X = pitch (positive leans forward), Z = side tilt, location Y = along
# the bone (up for root/body). Every clip keys every bone, so clips never leak into each other.

TAU = math.tau


def _pb(bones, name):
    return bones.get(name)


def clip_idle(b, t):
    s = math.sin(TAU * t)
    b["body"].scale = (1 - 0.015 * s, 1 + 0.035 * s, 1 - 0.015 * s)
    b["head"].rotation_euler.x = 0.04 * math.sin(TAU * t + 0.6)
    for side, sign in (("arm.L", 1), ("arm.R", -1)):
        if _pb(b, side):
            b[side].rotation_euler.z = sign * 0.10 * s


def _gait(b, t, swing, hop, lean, waddle, h):
    s = math.sin(TAU * t)
    b["root"].location.y = abs(s) * hop * h
    b["body"].rotation_euler.x = lean
    b["body"].rotation_euler.z = waddle * s
    b["head"].rotation_euler.z = -waddle * 0.5 * s
    for side, sign in (("leg.L", 1), ("leg.R", -1)):
        if _pb(b, side):
            b[side].rotation_euler.x = sign * swing * s
    for side, sign in (("arm.L", -1), ("arm.R", 1)):
        if _pb(b, side):
            b[side].rotation_euler.x = sign * swing * 0.9 * s


def make_clips(h):
    return {
        "idle": (48, clip_idle),
        "walk": (24, lambda b, t: _gait(b, t, 0.55, 0.05, 0.06, 0.12, h)),
        "run": (16, lambda b, t: _gait(b, t, 0.95, 0.08, 0.25, 0.08, h)),
        "jump": (20, lambda b, t: _jump(b, t)),
        "land": (10, lambda b, t: _squash(b, 1.0 - t, 0.28)),
        "attack": (12, lambda b, t: _attack(b, t)),
        "hit": (10, lambda b, t: _hit(b, t)),
        "death": (24, lambda b, t: _death(b, t)),
    }


def _squash(b, amount, depth):
    k = depth * amount
    b["body"].scale = (1 + k * 0.5, 1 - k, 1 + k * 0.5)


def _jump(b, t):
    # crouch -> stretch -> tuck -> neutral
    if t < 0.25:
        _squash(b, t / 0.25, 0.22)
    elif t < 0.5:
        k = (t - 0.25) / 0.25
        b["body"].scale = (1 - 0.06 * k, 1 + 0.14 * k, 1 - 0.06 * k)
    else:
        k = 1.0 - (t - 0.5) / 0.5
        b["body"].scale = (1 - 0.06 * k, 1 + 0.14 * k, 1 - 0.06 * k)
        for side in ("leg.L", "leg.R"):
            if _pb(b, side):
                b[side].rotation_euler.x = -0.5 * k
    for side, sign in (("arm.L", 1), ("arm.R", -1)):
        if _pb(b, side):
            b[side].rotation_euler.z = sign * 0.6 * math.sin(math.pi * t)


def _attack(b, t):
    punch = math.sin(math.pi * min(t / 0.6, 1.0))
    b["body"].rotation_euler.y = 0.35 * punch
    b["body"].rotation_euler.x = 0.12 * punch
    if _pb(b, "arm.R"):
        b["arm.R"].rotation_euler.x = 1.3 * punch


def _hit(b, t):
    k = math.sin(math.pi * t) * (1.0 - t)
    b["body"].rotation_euler.x = -0.45 * k
    _squash(b, k, 0.25)


def _death(b, t):
    k = min(t * 1.4, 1.0)
    b["body"].rotation_euler.x = -1.35 * k
    b["body"].scale = (1 + 0.15 * k, 1 - 0.35 * k, 1 + 0.15 * k)


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def bake_clips(arm, height):
    bpy.context.scene.render.fps = FPS
    arm.animation_data_create()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bones = {pb.name: pb for pb in arm.pose.bones}
    names = []
    for name, (frames, fn) in make_clips(height).items():
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        for f in range(0, frames + 1, 2):
            reset_pose(arm)
            fn(bones, f / frames)
            for pb in arm.pose.bones:
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("rotation_euler", frame=f)
                pb.keyframe_insert("scale", frame=f)
        names.append(name)
    reset_pose(arm)
    arm.animation_data.action = bpy.data.actions["idle"]
    bpy.ops.object.mode_set(mode="OBJECT")
    info("animations: " + ", ".join(names))


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
    bake_clips(arm, shape["h"])
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
