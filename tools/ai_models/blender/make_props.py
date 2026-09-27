"""Blender (5.x) batch script: builds ROYALTIM's low-poly props - loot containers and pickups.

    blender -b --factory-startup -P make_props.py -- OUT_DIR [prop ...]

Same paper-craft look as the concept characters: flat facets, one flat vertex color per part
(rendered in Godot by shaders/lowpoly_paper.gdshader via ModelUtils.apply_lowpoly_look).
Moving parts are separate child nodes with their pivot where they move:
  "Lid"       chest: hinge at the back edge; crate / barrel / supply drop: center of the lid
  "Parachute" supply drop: attach point on top of the crate
Props: chest crate barrel supply_drop medkit ammo_pistol ammo_shotgun ammo_rifle ammo_sniper
       fuel_can shield crystal wall_stone wall_wood wall_sandbag bush   (all when none are given)
Blender axes: Z up, the front faces -Y (glTF / Godot: +Z towards the gameplay camera).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector


def srgb(hex_color):
    """'#rrggbb' -> linear RGBA (vertex colors are linear in glTF)."""
    c = [int(hex_color[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c) + (1.0,)


WOOD = srgb("#a8652f")
WOOD_DARK = srgb("#6f3f1d")
WOOD_IN = srgb("#3d2312")
GOLD = srgb("#e9b83c")
GOLD_LIGHT = srgb("#ffd966")
IRON = srgb("#5d646f")
IRON_DARK = srgb("#3a3f47")
STRAW = srgb("#d9b25c")
OLIVE = srgb("#5f6d3a")
OLIVE_DARK = srgb("#353d20")
WARNING = srgb("#e8b23a")
RED = srgb("#d8392d")
WHITE = srgb("#f4f1e9")
CLOTH = srgb("#f3eee0")
BRASS = srgb("#d9a93c")
COPPER = srgb("#c26f38")


# ----------------------------------------------------------------------------- building blocks


class Part:
    """A bmesh being built; every helper paints the faces it creates."""

    def __init__(self):
        self.bm = bmesh.new()
        self.color = self.bm.loops.layers.float_color.new("Color")

    def _new_faces(self, before):
        return [f for f in self.bm.faces if f not in before]

    def paint(self, faces, color):
        for f in faces:
            for loop in f.loops:
                loop[self.color] = color

    def box(self, size, center, color, bevel=0.0, rot_z=0.0, rot_y=0.0):
        before = set(self.bm.faces)
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(size), verts=verts)
        if rot_y:
            bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot_y, 3, "Y"), verts=verts)
        if rot_z:
            bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot_z, 3, "Z"), verts=verts)
        bmesh.ops.translate(self.bm, vec=Vector(center), verts=verts)
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=1, affect="EDGES", profile=0.5)
        faces = self._new_faces(before)
        self.paint(faces, color)
        return faces

    def cylinder(self, radius, depth, center, color, segments=8, radius_top=None, axis="Z"):
        before = set(self.bm.faces)
        rot = {"Z": Matrix.Identity(3), "X": Matrix.Rotation(math.pi / 2, 3, "Y"),
               "Y": Matrix.Rotation(math.pi / 2, 3, "X")}[axis]
        m = Matrix.Translation(Vector(center)) @ rot.to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                              radius2=radius if radius_top is None else radius_top, depth=depth, matrix=m)
        faces = self._new_faces(before)
        self.paint(faces, color)
        return faces

    def blob(self, radius, center, color, scale=(1, 1, 1), subdivisions=1):
        """Faceted lump (icosphere): stones, sandbags, bush foliage."""
        before = set(self.bm.faces)
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector(scale)).to_4x4()
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdivisions, radius=radius, matrix=m)
        faces = self._new_faces(before)
        self.paint(faces, color)
        return faces

    def prism(self, outline, depth, color, axis="Y", offset=(0, 0, 0)):
        """Closed 2D outline extruded along an axis. outline: [(u, v)] counter-clockwise;
        axis Y: u = x, v = z (front / back faces); axis X: u = y, v = z (side profile)."""
        before = set(self.bm.faces)
        ox, oy, oz = offset

        def point(u, v, w):
            if axis == "Y":
                return Vector((u + ox, w + oy, v + oz))
            return Vector((w + ox, u + oy, v + oz))

        a = [self.bm.verts.new(point(u, v, -depth / 2)) for u, v in outline]
        b = [self.bm.verts.new(point(u, v, depth / 2)) for u, v in outline]
        self.bm.faces.new(a)
        self.bm.faces.new(list(reversed(b)))
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((a[i], a[j], b[j], b[i]))
        faces = self._new_faces(before)
        self.paint(faces, color)
        return faces

    def hollow_top(self, faces, rim, depth, inside_color):
        """Turn the top face of a box into an open container: rim ring + inner walls + floor."""
        self.bm.normal_update()
        top = max((f for f in faces if f.is_valid and f.normal.z > 0.9), key=lambda f: f.calc_center_median().z)
        bmesh.ops.inset_region(self.bm, faces=[top], thickness=rim, use_even_offset=True)
        # The extruded copy of the top sinks to become the floor; its side quads are the inner walls
        ret = bmesh.ops.extrude_face_region(self.bm, geom=[top])
        moved = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(self.bm, vec=(0, 0, -depth), verts=moved)
        self.paint([e for e in ret["geom"] if isinstance(e, bmesh.types.BMFace)], inside_color)

    keep_normals = False  # open double-sided surfaces: recalculating would flip one side back

    def finish(self, name, location=(0, 0, 0), parent=None):
        if not self.keep_normals:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for p in mesh.polygons:
            p.use_smooth = False
        mesh.color_attributes.active_color = mesh.color_attributes["Color"]
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = location
        if parent:
            obj.parent = parent
            obj.location = Vector(location) - parent.location
        return obj


def arc(width, height, segments=5):
    """Half-ellipse profile for a chest lid: from the front edge over the top to the back edge."""
    pts = []
    for i in range(segments + 1):
        a = math.pi * (1.0 - i / segments)
        pts.append((width / 2 * math.cos(a), height * math.sin(a)))
    return pts


# ----------------------------------------------------------------------------- containers


def build_chest():
    w, d, h, lid_h = 0.9, 0.56, 0.42, 0.24
    base = Part()
    body = base.box((w, d, h), (0, 0, h / 2), WOOD, bevel=0.018)
    base.hollow_top(body, 0.05, 0.28, WOOD_IN)
    # plank seams and iron/brass bands
    base.box((w + 0.006, d + 0.006, 0.025), (0, 0, h * 0.42), WOOD_DARK)
    for x in (-0.3, 0.3):
        base.box((0.075, 0.022, h), (x, -d / 2 - 0.008, h / 2), GOLD, bevel=0.006)
        base.box((0.075, 0.022, h), (x, d / 2 + 0.008, h / 2), GOLD, bevel=0.006)
        base.box((0.075, d + 0.04, 0.022), (x, 0, 0.006), GOLD)
    base.box((0.15, 0.03, 0.15), (0, -d / 2 - 0.014, h - 0.08), GOLD_LIGHT, bevel=0.01)
    base.box((0.03, 0.012, 0.055), (0, -d / 2 - 0.03, h - 0.09), IRON_DARK)
    # treasure glinting inside
    for x, y, s, rz in ((-0.2, 0.05, 0.13, 0.3), (0.05, -0.06, 0.15, 0.9), (0.22, 0.07, 0.12, 0.2),
                        (-0.05, 0.1, 0.11, 1.3), (0.12, -0.1, 0.1, 0.6)):
        base.box((s, s, s * 0.8), (x, y, h - 0.24), GOLD_LIGHT, bevel=0.02, rot_z=rz)
    for x, y in ((-0.1, -0.12), (0.28, -0.08), (-0.28, -0.05)):
        base.cylinder(0.045, 0.014, (x, y, h - 0.17), GOLD, segments=8)
    chest = base.finish("Chest")

    # lid: pivot on the hinge (back top edge); geometry extends to the front (-Y)
    lid = Part()
    profile = [(y - d / 2, z) for y, z in arc(d, lid_h)]
    lid.prism(profile, w + 0.02, WOOD, axis="X")
    lid.paint([f for f in lid.bm.faces if f.normal.z < -0.9], WOOD_IN)  # underside seen when open
    band = [(y * 1.05 - d / 2 * 1.05 + 0.0, z * 1.08) for y, z in arc(d, lid_h)]
    for x in (-0.3, 0.3):
        lid.prism([(u, v) for u, v in band], 0.075, GOLD, axis="X", offset=(x, 0.013, 0.0))
    lid.box((0.13, 0.03, 0.09), (0, -d - 0.015, 0.02), GOLD_LIGHT, bevel=0.008)  # latch
    lid.finish("Lid", location=(0, d / 2, h), parent=chest)
    return chest


def build_crate():
    s, h = 0.78, 0.66
    base = Part()
    body = base.box((s - 0.04, s - 0.04, h), (0, 0, h / 2), WOOD, bevel=0.01)
    base.hollow_top(body, 0.05, 0.4, WOOD_IN)
    bar = 0.075
    for x in (-1, 1):
        for y in (-1, 1):
            base.box((bar, bar, h), (x * (s / 2 - bar / 2), y * (s / 2 - bar / 2), h / 2), WOOD_DARK, bevel=0.008)
    for side in range(4):
        rz = side * math.pi / 2
        n = Matrix.Rotation(rz, 3, "Z") @ Vector((0, -s / 2 + 0.005, 0))
        base.box((bar, bar * 0.6, s * 1.08), (n.x, n.y, h / 2), WOOD_DARK,
                 rot_y=math.atan2(h - 0.1, s - 0.1), rot_z=rz)
        base.box((s, bar * 0.6, bar), (n.x, n.y, bar / 2), WOOD_DARK, rot_z=rz)
    for x, y in ((-0.15, 0.1), (0.1, -0.12), (0.18, 0.15), (-0.12, -0.15)):  # straw
        base.box((0.18, 0.04, 0.04), (x, y, h - 0.36), STRAW, rot_z=x * 7.0)
    crate = base.finish("Crate")
    lid = Part()
    lid.box((s, s, 0.08), (0, 0, 0.04), WOOD, bevel=0.01)
    for i in (-1, 0, 1):
        lid.box((s + 0.004, 0.012, 0.084), (0, i * s / 3.2, 0.04), WOOD_DARK)
    for x in (-1, 1):
        lid.box((bar, s + 0.01, 0.1), (x * (s / 2 - bar / 2), 0, 0.05), WOOD_DARK, bevel=0.008)
    lid.finish("Lid", location=(0, 0, h), parent=crate)
    return crate


def _ring(bm, z, r, segs, twist=0.0):
    return [bm.verts.new((r * math.cos(twist + i * math.tau / segs), r * math.sin(twist + i * math.tau / segs), z))
            for i in range(segs)]


def build_barrel():
    segs = 10
    base = Part()
    rings_z_r = [(0.0, 0.3), (0.14, 0.35), (0.42, 0.38), (0.7, 0.35), (0.82, 0.31)]
    before = set(base.bm.faces)
    rings = [_ring(base.bm, z, r, segs) for z, r in rings_z_r]
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            base.bm.faces.new((a[i], a[j], b[j], b[i]))
    base.bm.faces.new(list(reversed(rings[0])))
    top = base.bm.faces.new(rings[-1])
    base.paint([f for f in base.bm.faces if f not in before], WOOD)
    base.hollow_top([top], 0.04, 0.1, WOOD_IN)
    for z0, r in ((0.2, 0.365), (0.6, 0.365)):
        base.cylinder(r + 0.012, 0.06, (0, 0, z0), IRON, segments=segs)
    barrel = base.finish("Barrel")
    lid = Part()
    lid.cylinder(0.3, 0.045, (0, 0, 0.022), WOOD_DARK, segments=segs)
    lid.box((0.34, 0.05, 0.05), (0, 0, 0.06), IRON, bevel=0.01)
    lid.finish("Lid", location=(0, 0, 0.8), parent=barrel)
    return barrel


def build_supply_drop():
    w, d, h = 1.1, 0.76, 0.6
    base = Part()
    body = base.box((w, d, h), (0, 0, h / 2), OLIVE, bevel=0.025)
    base.hollow_top(body, 0.06, 0.34, OLIVE_DARK)
    base.box((w + 0.012, d + 0.012, 0.07), (0, 0, h * 0.62), WARNING)
    for x in (-0.34, 0.34):
        base.box((0.09, d + 0.03, h - 0.02), (x, 0, h / 2), OLIVE_DARK)
    for x in (-0.12, 0.12):  # white stencil marks on the front
        base.box((0.12, 0.01, 0.12), (x, -d / 2 - 0.012, h * 0.3), WHITE)
    for x, y in ((-0.2, 0.05), (0.15, -0.1), (0.25, 0.12)):  # supplies inside
        base.box((0.22, 0.16, 0.16), (x, y, h - 0.26), WHITE if x < 0 else WARNING, bevel=0.02, rot_z=x * 3)
    drop = base.finish("SupplyDrop")
    lid = Part()
    lid.box((w + 0.02, d + 0.02, 0.09), (0, 0, 0.045), OLIVE, bevel=0.02)
    lid.box((w + 0.026, 0.1, 0.1), (0, 0, 0.05), OLIVE_DARK)
    lid.cylinder(0.06, 0.1, (0.4, 0.22, 0.14), RED, segments=8, radius_top=0.04)  # beacon
    lid.finish("Lid", location=(0, 0, h), parent=drop)

    chute = Part()
    segs, radius, top = 10, 1.25, 1.95
    before = set(chute.bm.faces)
    rings = [_ring(chute.bm, top - 0.75 * (1 - math.cos(a)) - 0.05, radius * math.sin(a) + 0.08, segs)
             for a in (1.2, 0.75, 0.3)]
    apex = chute.bm.verts.new((0, 0, top))
    panels = []
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            panels.append((i, chute.bm.faces.new((a[i], a[j], b[j], b[i]))))  # outward winding
    for i in range(segs):
        panels.append((i, chute.bm.faces.new((rings[-1][i], rings[-1][(i + 1) % segs], apex))))
    for i, f in panels:
        chute.paint([f], CLOTH if i % 2 == 0 else RED)
    # Inside of the canopy (seen from below while it floats down): a flipped, slightly smaller copy
    inside = bmesh.ops.duplicate(chute.bm, geom=[f for _i, f in panels])["geom"]
    inside_faces = [e for e in inside if isinstance(e, bmesh.types.BMFace)]
    bmesh.ops.reverse_faces(chute.bm, faces=inside_faces)
    bmesh.ops.scale(chute.bm, vec=(0.985, 0.985, 0.985),
                    verts=[e for e in inside if isinstance(e, bmesh.types.BMVert)])
    for (i, _f), f in zip(panels, inside_faces):
        chute.paint([f], srgb("#cfc8b8") if i % 2 == 0 else srgb("#b53a2e"))
    chute.keep_normals = True
    for i in range(0, segs, 2):  # cords down to the crate
        p = rings[0][i].co
        mid = p * 0.5
        length = p.length
        cord_dir = p.normalized()
        before_c = set(chute.bm.faces)
        verts = bmesh.ops.create_cube(chute.bm, size=1.0)["verts"]
        bmesh.ops.scale(chute.bm, vec=(0.012, 0.012, length), verts=verts)
        rot = Vector((0, 0, 1)).rotation_difference(cord_dir).to_matrix()
        bmesh.ops.rotate(chute.bm, cent=(0, 0, 0), matrix=rot, verts=verts)
        bmesh.ops.translate(chute.bm, vec=mid, verts=verts)
        chute.paint(chute._new_faces(before_c), IRON_DARK)
    chute.finish("Parachute", location=(0, 0, h + 0.1), parent=drop)
    return drop


# ----------------------------------------------------------------------------- cover
# Wall segments span one hex edge (1 m) along X, 0.3 m thick, ~1.3 m tall: a veggie (1.25 m)
# ducks fully behind one. Pivot at the bottom center. CoverSpawner puts them on tile edges.

WALL_LEN, WALL_H, WALL_T = 1.04, 1.3, 0.3


def build_wall_stone():
    import random
    rnd = random.Random(11)
    p = Part()
    greys = [srgb("#8f908a"), srgb("#7a7c76"), srgb("#a4a49c"), srgb("#6c6e69")]
    rows = 4
    row_h = WALL_H / rows
    for row in range(rows):
        x = -WALL_LEN / 2
        offset = (row % 2) * 0.12
        x -= offset
        while x < WALL_LEN / 2 - 0.02:
            w = rnd.uniform(0.24, 0.36)
            x0, x1 = max(x, -WALL_LEN / 2), min(x + w, WALL_LEN / 2)
            if x1 - x0 > 0.06:
                cx = (x0 + x1) / 2
                p.box((x1 - x0 - 0.02, WALL_T * rnd.uniform(0.92, 1.05), row_h * rnd.uniform(0.9, 1.02)),
                      (cx, rnd.uniform(-0.015, 0.015), row_h * (row + 0.5)), rnd.choice(greys), bevel=0.025)
            x += w
    moss = srgb("#6f8f3f")
    for x in (-0.3, 0.05, 0.32):  # moss on the top
        p.blob(0.09, (x, 0.0, WALL_H + 0.01), moss, scale=(1.6, 1.2, 0.45))
    return p.finish("WallStone")


def build_wall_wood():
    import random
    rnd = random.Random(5)
    p = Part()
    browns = [srgb("#9c6433"), srgb("#8a5629"), srgb("#a8703a")]
    n = 6
    plank = WALL_LEN / n
    for i in range(n):
        x = -WALL_LEN / 2 + plank * (i + 0.5)
        h = WALL_H * rnd.uniform(0.9, 1.0)
        col = rnd.choice(browns)
        p.box((plank - 0.015, 0.1, h), (x, 0, h / 2), col, bevel=0.01)
        # sharpened tip
        p.prism([(-plank / 2 + 0.01, 0), (plank / 2 - 0.01, 0), (0, 0.13)], 0.1, col, axis="Y", offset=(x, 0, h))
    for z in (0.3, 0.95):  # braces behind
        p.box((WALL_LEN, 0.06, 0.1), (0, 0.08, z), srgb("#6c4020"), bevel=0.008)
    return p.finish("WallWood")


def build_wall_sandbag():
    import random
    rnd = random.Random(3)
    p = Part()
    tans = [srgb("#c9b184"), srgb("#b89f71"), srgb("#d6c196")]
    rows = 5
    for row in range(rows):
        count = 4 if row % 2 == 0 else 3
        span = WALL_LEN / 4
        for i in range(count):
            x = -WALL_LEN / 2 + span * (i + 0.5) + (span / 2 if count == 3 else 0)
            z = 0.13 + row * 0.235
            p.box((span * 0.98, 0.3, 0.24), (x, rnd.uniform(-0.02, 0.02), z), rnd.choice(tans), bevel=0.07,
                  rot_z=rnd.uniform(-0.06, 0.06))
    return p.finish("WallSandbag")


def build_bush():
    import random
    rnd = random.Random(7)
    p = Part()
    greens = [srgb("#4e8a34"), srgb("#5f9c3c"), srgb("#437a2c"), srgb("#6aa845")]
    lumps = [(0, 0, 0.45, 0.45), (0.32, 0.1, 0.34, 0.33), (-0.3, 0.12, 0.33, 0.32), (0.1, -0.3, 0.32, 0.3),
             (-0.12, 0.32, 0.3, 0.3), (0.05, 0.05, 0.72, 0.3), (0.35, -0.22, 0.25, 0.24), (-0.34, -0.2, 0.26, 0.25)]
    for x, y, z, r in lumps:
        p.blob(r, (x, y, z), rnd.choice(greens), scale=(1.0, 1.0, 0.85))
    for x, y, z in ((0.2, -0.28, 0.62), (-0.25, 0.1, 0.66), (0.33, 0.2, 0.5)):  # a few berries
        p.blob(0.05, (x, y, z), srgb("#d8463a"), subdivisions=1)
    return p.finish("Bush")


# ----------------------------------------------------------------------------- pickups


def build_medkit():
    p = Part()
    p.box((0.44, 0.22, 0.3), (0, 0, 0), WHITE, bevel=0.02)
    p.box((0.446, 0.226, 0.03), (0, 0, 0.03), srgb("#d7d2c4"))
    for y in (-0.114, 0.114):
        p.box((0.2, 0.012, 0.065), (0, y, -0.01), RED)
        p.box((0.065, 0.012, 0.2), (0, y, -0.01), RED)
    p.box((0.2, 0.05, 0.04), (0, 0, 0.23), IRON, bevel=0.008)
    for x in (-0.085, 0.085):
        p.box((0.035, 0.04, 0.07), (x, 0, 0.18), IRON)
    return p.finish("Medkit")


AMMO_COLORS = {
    "ammo_pistol": srgb("#e2b845"),
    "ammo_shotgun": srgb("#d0463a"),
    "ammo_rifle": srgb("#6fae4c"),
    "ammo_sniper": srgb("#4c82d6"),
}


def build_ammo(name):
    p = Part()
    p.box((0.34, 0.22, 0.17), (0, 0, 0), OLIVE, bevel=0.012)
    p.box((0.346, 0.226, 0.05), (0, 0, 0.0), AMMO_COLORS[name])
    p.box((0.1, 0.012, 0.04), (0, -0.117, 0.055), OLIVE_DARK)
    if name == "ammo_shotgun":
        for i in range(4):
            x = -0.105 + i * 0.07
            p.cylinder(0.03, 0.03, (x, 0, 0.1), BRASS, segments=8)
            p.cylinder(0.03, 0.1, (x, 0, 0.165), RED, segments=8)
    else:
        length = {"ammo_pistol": 0.07, "ammo_rifle": 0.1, "ammo_sniper": 0.14}[name]
        for i in range(5):
            x = -0.12 + i * 0.06
            p.cylinder(0.022, length, (x, 0, 0.085 + length / 2), BRASS, segments=6)
            p.cylinder(0.022, 0.05, (x, 0, 0.085 + length + 0.025), COPPER, segments=6, radius_top=0.004)
    return p.finish(name.title().replace("_", ""))


def build_fuel_can():
    p = Part()
    p.box((0.3, 0.14, 0.38), (0, 0, 0), RED, bevel=0.02)
    dark = srgb("#9e2a21")
    for y in (-0.072, 0.072):
        p.box((0.03, 0.01, 0.34), (0, y, -0.01), dark, rot_y=0.62)
        p.box((0.03, 0.01, 0.34), (0, y, -0.01), dark, rot_y=-0.62)
    p.box((0.16, 0.05, 0.035), (-0.03, 0, 0.25), IRON_DARK, bevel=0.006)
    for x in (-0.1, 0.04):
        p.box((0.03, 0.04, 0.07), (x, 0, 0.215), IRON_DARK)
    p.cylinder(0.03, 0.06, (0.1, 0, 0.215), IRON, segments=8)
    p.cylinder(0.036, 0.03, (0.1, 0, 0.26), WARNING, segments=8)
    return p.finish("FuelCan")


def build_shield():
    p = Part()
    outline = [(-0.24, 0.3), (0.24, 0.3), (0.25, 0.06), (0.15, -0.18), (0.0, -0.32),
               (-0.15, -0.18), (-0.25, 0.06)]
    rim = [(u * 1.13, v * 1.1 + 0.005) for u, v in outline]
    p.prism(list(reversed(rim)), 0.05, srgb("#dfe4ea"), axis="Y", offset=(0, 0.012, 0))
    p.prism(list(reversed(outline)), 0.06, srgb("#3a78d4"), axis="Y")
    p.prism(list(reversed([(0, 0.17), (0.09, 0.02), (0, -0.14), (-0.09, 0.02)])), 0.07, WHITE, axis="Y",
            offset=(0, -0.006, 0))
    p.box((0.3, 0.07, 0.035), (0, -0.004, 0.22), srgb("#f2c84b"))
    return p.finish("Shield")


def build_crystal():
    p = Part()
    bm = p.bm
    segs = 6
    top = bm.verts.new((0, 0, 0.34))
    bottom = bm.verts.new((0, 0, -0.3))
    upper = _ring(bm, 0.08, 0.15, segs)
    lower = _ring(bm, -0.02, 0.16, segs, twist=math.pi / segs)
    faces = []
    for i in range(segs):
        j = (i + 1) % segs
        faces.append(bm.faces.new((upper[i], upper[j], top)))
        faces.append(bm.faces.new((lower[i], upper[j], upper[i])))
        faces.append(bm.faces.new((lower[i], lower[j], upper[j])))
        faces.append(bm.faces.new((lower[j], lower[i], bottom)))
    light, dark = srgb("#c08af2"), srgb("#8a3fd6")
    for k, f in enumerate(faces):
        p.paint([f], light if k % 3 == 0 else dark)
    return p.finish("Crystal")


BUILDERS = {
    "chest": build_chest, "crate": build_crate, "barrel": build_barrel, "supply_drop": build_supply_drop,
    "medkit": build_medkit, "fuel_can": build_fuel_can, "shield": build_shield, "crystal": build_crystal,
    "wall_stone": build_wall_stone, "wall_wood": build_wall_wood, "wall_sandbag": build_wall_sandbag,
    "bush": build_bush,
}
for _ammo in AMMO_COLORS:
    BUILDERS[_ammo] = (lambda n: (lambda: build_ammo(n)))(_ammo)


def export(path):
    kwargs = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                  export_animations=False, export_vertex_color="ACTIVE")
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_vertex_color")
        bpy.ops.export_scene.gltf(**kwargs)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("usage: ... -- OUT_DIR [prop ...]")
    out_dir = argv[0]
    names = argv[1:] or list(BUILDERS)
    os.makedirs(out_dir, exist_ok=True)
    for name in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        BUILDERS[name]()
        path = os.path.join(out_dir, name + ".glb")
        export(path)
        tris = sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == "MESH" for p in o.data.polygons)
        print("PROP %s: %d triangles -> %s" % (name, tris, path), flush=True)


try:
    main()
except SystemExit:
    raise
except Exception as exc:  # noqa: BLE001
    import traceback
    traceback.print_exc()
    print("ERROR: %s" % exc, flush=True)
    sys.exit(1)
