"""Look at / convert a downloaded 3D asset for ROYALTIM-3.

Run with Blender (5.x):
  blender -b -P tools/ai_models/blender/asset_tool.py -- IN_FILE [options]

IN_FILE: .glb / .gltf / .fbx / .obj / .stl / .ply / .dae
Options:
  --preview OUT.png     render the model next to a 1.2 m hero stand-in (grey capsule) on a 1 m grid
  --export OUT.glb      write a cleaned GLB (scale / rotation / origin applied)
  --fit-height M        scale so the model is M metres tall
  --fit-length M        scale so the longest horizontal side is M metres (guns: RangedWeapon.hold_length)
  --rotate-z DEG        turn around the up axis first (Blender +Y = Godot -Z, where gun barrels point)
  --feet                origin at the bottom centre (props / characters stand on it)
  --decimate N          reduce to about N triangles
Always prints one "ASSET {json}" line: triangles, size in metres, materials, textures, vertex colors.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERO_HEIGHT = 1.2


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit(__doc__)
    opts = {"src": argv[0]}
    flags = {"--preview": str, "--export": str, "--fit-height": float, "--fit-length": float,
             "--rotate-z": float, "--decimate": int}
    for flag, cast in flags.items():
        if flag in argv:
            opts[flag[2:].replace("-", "_")] = cast(argv[argv.index(flag) + 1])
    opts["feet"] = "--feet" in argv
    return opts


def import_any(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=path)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=path)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
    else:
        raise SystemExit("unsupported format: " + ext)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def root_objects():
    return [o for o in bpy.context.scene.objects if o.parent is None]


def transform_all(matrix):
    for o in root_objects():
        o.matrix_world = matrix @ o.matrix_world


def apply_transforms():
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes():
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
    if meshes():
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def triangles():
    return sum(len(p.vertices) - 2 for o in meshes() for p in o.data.polygons)


def describe():
    lo, hi = bounds(meshes())
    size = hi - lo
    mats, textures = set(), set()
    for o in meshes():
        for slot in o.material_slots:
            if slot.material:
                mats.add(slot.material.name)
                if slot.material.node_tree:
                    for n in slot.material.node_tree.nodes:
                        if n.type == "TEX_IMAGE" and n.image:
                            textures.add(n.image.name)
    vcol = any(len(o.data.color_attributes) > 0 for o in meshes())
    return {"triangles": triangles(), "meshes": len(meshes()),
            "size_m": [round(size.x, 3), round(size.y, 3), round(size.z, 3)],
            "materials": sorted(mats), "textures": sorted(textures), "vertex_colors": vcol,
            "armatures": sum(1 for o in bpy.context.scene.objects if o.type == "ARMATURE"),
            "animations": [a.name for a in bpy.data.actions]}


def fit(opts):
    if "rotate_z" in opts:
        from mathutils import Matrix
        transform_all(Matrix.Rotation(math.radians(opts["rotate_z"]), 4, "Z"))
    lo, hi = bounds(meshes())
    size = hi - lo
    factor = 1.0
    if "fit_height" in opts and size.z > 0:
        factor = opts["fit_height"] / size.z
    elif "fit_length" in opts and max(size.x, size.y) > 0:
        factor = opts["fit_length"] / max(size.x, size.y)
    if factor != 1.0:
        from mathutils import Matrix
        transform_all(Matrix.Scale(factor, 4))
    if opts["feet"]:
        lo, hi = bounds(meshes())
        from mathutils import Matrix
        transform_all(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))


def decimate(target):
    total = triangles()
    if total <= target:
        return
    for o in meshes():
        m = o.modifiers.new("Decimate", "DECIMATE")
        m.ratio = target / total
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)


def export(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    kwargs = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                  export_vertex_color="ACTIVE")
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_vertex_color")
        bpy.ops.export_scene.gltf(**kwargs)


def add_stand_in(x):
    """A grey capsule as tall as a hero, and a 1 m grid under everything."""
    radius = 0.3
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=HERO_HEIGHT - 2 * radius,
                                        location=(x, 0, HERO_HEIGHT / 2))
    body = bpy.context.object
    for z in (radius, HERO_HEIGHT - radius):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(x, 0, z))
    grey = bpy.data.materials.new("StandIn")
    grey.diffuse_color = (0.55, 0.55, 0.6, 1.0)
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.name.startswith(("Cylinder", "Sphere")):
            o.data.materials.append(grey)
    return body


def render_preview(path, model_info):
    lo, hi = bounds(meshes())
    width = hi.x - lo.x
    stand_x = hi.x + 0.6
    add_stand_in(stand_x)
    lo2, hi2 = bounds(meshes())
    span = max(hi2.x - lo2.x, hi2.y - lo2.y, hi2.z - lo2.z, 1.0)

    bpy.ops.mesh.primitive_grid_add(x_subdivisions=int(span * 2) + 4, y_subdivisions=int(span * 2) + 4,
                                    size=math.ceil(span * 2) + 2, location=((lo2.x + hi2.x) / 2, (lo2.y + hi2.y) / 2, min(lo2.z, 0) - 0.001))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX" if model_info["vertex_colors"] and not model_info["textures"] else "TEXTURE"
    shading.show_cavity = True
    shading.show_object_outline = True
    shading.show_shadows = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.film_transparent = False

    centre = (lo2 + hi2) / 2
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.6
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    # 3/4 view from the front-left and above (Blender -Y is the model's front = Godot +Z, where heroes face).
    direction = Vector((-0.6, -1.0, 0.7)).normalized()
    cam.location = centre + direction * span * 4
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)


def main():
    opts = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_any(opts["src"])
    if not meshes():
        raise SystemExit("no meshes in " + opts["src"])
    fit(opts)
    if "decimate" in opts:
        decimate(opts["decimate"])
    info = describe()
    info["source"] = opts["src"]
    if "export" in opts:
        apply_transforms()
        export(opts["export"])
        info["exported"] = opts["export"]
    print("ASSET " + json.dumps(info, ensure_ascii=False), flush=True)
    if "preview" in opts:
        render_preview(opts["preview"], info)
        print("PREVIEW " + os.path.abspath(opts["preview"]), flush=True)


try:
    main()
except SystemExit as e:
    if e.code not in (None, 0):
        print(e.code, file=sys.stderr)
        sys.exit(1)
