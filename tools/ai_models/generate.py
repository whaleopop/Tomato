#!/usr/bin/env python
"""ROYALTIM-3 local 3D model generator: text -> concept image -> background removal -> TripoSR -> GLB.

CLI contract (the Godot editor plugin calls this, keep it stable):
    python generate.py (--prompt "text" | --image path.png) [--name tomato_hero] [--out path.glb]
                       [--seed 42] [--steps 6] [--mc-res 256] [--faces 8000] [--cpu] [--keep-bg]
stdout: "PROGRESS: <0-100> <message>" lines while working, then exactly one final line
        "RESULT: <absolute path to .glb>" on success, or "ERROR: <message>" + non-zero exit code.
Other stdout lines (INFO:/WARNING:) are informational; library logs go to stderr.

Service modes used by setup.ps1: --download-models [--no-text2img], --self-check.
"""
import argparse
import gc
import os
import random
import re
import sys
import time
import traceback
from pathlib import Path

AI_ROOT = Path(os.environ.get("ROYALTIM_AI_ROOT", r"D:\royaltim-ai"))
for _k, _v in {
    "HF_HOME": AI_ROOT / "hf_cache",
    "TORCH_HOME": AI_ROOT / "torch_cache",
    "U2NET_HOME": AI_ROOT / "u2net",
    "PIP_CACHE_DIR": AI_ROOT / "pip_cache",
}.items():
    os.environ.setdefault(_k, str(_v))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("DIFFUSERS_VERBOSITY", "error")
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

TRIPOSR_DIR = AI_ROOT / "TripoSR"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = PROJECT_ROOT / "models" / "generated"

T2I_REPO = "SimianLuo/LCM_Dreamshaper_v7"
T2I_FILES = [
    "model_index.json", "scheduler/*", "tokenizer/*", "feature_extractor/*",
    "text_encoder/config.json", "text_encoder/model.safetensors",
    "unet/config.json", "unet/diffusion_pytorch_model.safetensors",
    "vae/config.json", "vae/diffusion_pytorch_model.safetensors",
]
TSR_REPO = "stabilityai/TripoSR"
DINO_REPO = "facebook/dino-vitb16"  # TripoSR only needs its config.json (weights are in model.ckpt)

STYLES = {
    # ROYALTIM characters are vegetables/fruits themselves, not people dressed as them
    "veggie": "anthropomorphic vegetable mascot, the whole body is the round vegetable itself with a cute face, "
              "big eyes, small stubby arms and legs, full body, front view, centered, single character, "
              "plain white background, clay toy, 3d render, game asset",
    "character": "cute cartoon character, full body, front view, centered, single object, "
                 "plain white background, 3d render, game asset",
    "prop": "cartoon game prop, single object, centered, front view, whole object visible, "
            "plain white background, 3d render, game asset",
    "none": "",
}
NEGATIVE_PROMPT = (
    "multiple characters, crowd, cropped, cut off, out of frame, partial view, text, watermark, "
    "signature, logo, frame, border, busy background, scenery, landscape, floor, shadow, "
    "blurry, lowres, jpeg artifacts, deformed, extra limbs"
)
LCM_W = 8.0          # guidance baked into LCM_Dreamshaper_v7 (w-embedding); recommended value 8
NEG_CFG = 1.0        # extra CFG against the negative prompt (1.0 = off); see --neg-cfg
MC_THRESHOLD = 25.0  # TripoSR default density threshold
CHUNK_SIZES = [8192, 2048, 1024]


# ----------------------------------------------------------------------------- output helpers
def progress(pct, msg):
    print(f"PROGRESS: {int(pct)} {msg}", flush=True)


def info(msg):
    print(f"INFO: {msg}", flush=True)


def warn(msg):
    print(f"WARNING: {msg}", flush=True)


class GenError(Exception):
    pass


def is_oom(exc):
    import torch
    if isinstance(exc, torch.cuda.OutOfMemoryError):
        return True
    s = str(exc)
    return any(k in s for k in ("out of memory", "CUBLAS_STATUS_ALLOC_FAILED",
                                "CUDNN_STATUS_NOT_ENOUGH_WORKSPACE", "CUDNN_STATUS_ALLOC_FAILED"))


def free_cuda():
    import torch
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


# ----------------------------------------------------------------------------- args
def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Local text/image -> 3D GLB generator (LCM Dreamshaper + rembg + TripoSR)")
    src = p.add_mutually_exclusive_group()
    src.add_argument("--prompt", help="text description (English works best)")
    src.add_argument("--image", help="input image (PNG/JPG); RGBA alpha is used as the mask if present")
    p.add_argument("--name", help="asset name; default derived from prompt/image")
    p.add_argument("--out", help="output .glb path (default: <project>/models/generated/<name>.glb)")
    p.add_argument("--seed", type=int, default=-1, help="seed for the concept image (-1 = random)")
    p.add_argument("--steps", type=int, default=6, help="LCM denoising steps, 4-8 (default 6)")
    p.add_argument("--mc-res", type=int, default=256, help="marching cubes resolution (default 256)")
    p.add_argument("--faces", type=int, default=8000, help="target face count after decimation, 0 = keep all (default 8000)")
    p.add_argument("--cpu", action="store_true", help="run everything on CPU (slow)")
    p.add_argument("--keep-bg", action="store_true", help="do not run background removal on --image")
    p.add_argument("--matte", choices=["rembg", "chroma"], default="rembg",
                   help="background removal: rembg (any photo) or chroma (plain backdrop, keeps thin limbs)")
    p.add_argument("--rig", action="store_true", help="also remesh + auto-rig + animate in Blender -> <name>_rigged.glb")
    p.add_argument("--rig-file", help="only rig + animate an existing GLB (no AI), writes <name>_rigged.glb")
    p.add_argument("--no-remesh", action="store_true", help="with --rig-file: keep the original mesh (hand-made models)")
    # optional extras (not part of the plugin contract)
    p.add_argument("--style", choices=sorted(STYLES), default="character", help="prompt style suffix (default character; veggie = vegetable mascots)")
    p.add_argument("--negative", default=NEGATIVE_PROMPT, help="negative prompt (used when --neg-cfg > 1)")
    p.add_argument("--neg-cfg", type=float, default=NEG_CFG, help="extra CFG vs negative prompt, 1.0 = off (doubles UNet cost)")
    p.add_argument("--height", type=float, default=1.2, help="model height in Godot units (default 1.2)")
    p.add_argument("--download-models", action="store_true", help="only download all weights, then exit")
    p.add_argument("--no-text2img", action="store_true", help="with --download-models: skip the text->image model")
    p.add_argument("--self-check", action="store_true", help="verify the installation, then exit")
    a = p.parse_args(argv)
    # Mascots drift towards humans without pushing against them, so veggie enables negative CFG
    if a.style == "veggie" and a.neg_cfg == NEG_CFG:
        a.neg_cfg = 1.6
        if a.negative == NEGATIVE_PROMPT:
            a.negative = NEGATIVE_PROMPT + ", human, person, girl, boy, woman, man, hair, skin, anime"
    if not (a.download_models or a.self_check or a.rig_file) and not (a.prompt or a.image):
        p.error("one of --prompt or --image is required")
    if not 1 <= a.steps <= 50:
        p.error("--steps must be in 1..50")
    if not 32 <= a.mc_res <= 1024:
        p.error("--mc-res must be in 32..1024")
    return a


def slugify(text, max_words=4):
    words = re.findall(r"[a-z0-9]+", text.lower())
    return "_".join(words[:max_words]) or time.strftime("model_%Y%m%d_%H%M%S")


def resolve_output(args):
    if args.out:
        out = Path(args.out).expanduser()
        if out.suffix.lower() != ".glb":
            out = out.with_suffix(".glb")
        name = re.sub(r"[^A-Za-z0-9_\-]+", "_", args.name) if args.name else out.stem
    else:
        if args.name:
            name = re.sub(r"[^A-Za-z0-9_\-]+", "_", args.name).strip("_") or "model"
        elif args.prompt:
            name = slugify(args.prompt)
        else:
            name = slugify(Path(args.image).stem)
        out = DEFAULT_OUT_DIR / f"{name}.glb"
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    return name, out


# ----------------------------------------------------------------------------- stage 1: text -> image
def load_t2i(mode, device):
    import torch
    from diffusers import LatentConsistencyModelPipeline
    from huggingface_hub import snapshot_download
    local = snapshot_download(T2I_REPO, allow_patterns=T2I_FILES)
    dtype = torch.float16 if mode != "cpu" else torch.float32
    pipe = LatentConsistencyModelPipeline.from_pretrained(
        local, torch_dtype=dtype, safety_checker=None, feature_extractor=None, requires_safety_checker=False)
    pipe.set_progress_bar_config(disable=True)
    if mode == "gpu":
        pipe.to(device)
    elif mode == "model_offload":
        pipe.enable_model_cpu_offload(device=device)
    elif mode == "sequential_offload":
        pipe.enable_sequential_cpu_offload(device=device)
    return pipe


def lcm_sample(pipe, prompt, negative, steps, seed, neg_cfg, device):
    """LCM sampling loop (same math as LatentConsistencyModelPipeline) + optional CFG vs a negative prompt."""
    import torch
    use_neg = neg_cfg > 1.0 and bool(negative)
    unet, sched = pipe.unet, pipe.scheduler
    dtype = unet.dtype
    gen = torch.Generator("cpu").manual_seed(seed)
    with torch.no_grad():
        pos, neg = pipe.encode_prompt(prompt, device, 1, use_neg, negative_prompt=negative if use_neg else None)
        sched.set_timesteps(steps, device=device, original_inference_steps=50)
        latents = torch.randn((1, 4, 64, 64), generator=gen, dtype=torch.float32).to(device, dtype)
        latents = latents * sched.init_noise_sigma
        w = torch.tensor([LCM_W - 1.0])
        w_emb = pipe.get_guidance_scale_embedding(w, embedding_dim=unet.config.time_cond_proj_dim).to(device, dtype)
        denoised = latents
        for i, t in enumerate(sched.timesteps):
            if use_neg:
                pred = unet(torch.cat([latents] * 2), t, timestep_cond=w_emb.repeat(2, 1),
                            encoder_hidden_states=torch.cat([neg, pos]), return_dict=False)[0]
                p_neg, p_pos = pred.chunk(2)
                pred = p_neg + neg_cfg * (p_pos - p_neg)
            else:
                pred = unet(latents, t, timestep_cond=w_emb, encoder_hidden_states=pos, return_dict=False)[0]
            latents, denoised = sched.step(pred, t, latents, generator=gen, return_dict=False)
            progress(10 + 18 * (i + 1) / len(sched.timesteps), f"denoising step {i + 1}/{len(sched.timesteps)}")
        vae = pipe.vae
        img = vae.decode(denoised.to(vae.dtype) / vae.config.scaling_factor, return_dict=False)[0]
        pil = pipe.image_processor.postprocess(img.float(), output_type="pil")[0]
    return pil


def text_to_image(args, device, seed):
    import torch
    prompt = args.prompt.strip()
    if re.search(r"[\u0400-\u04FF]", prompt):
        warn("the text model understands English only - Cyrillic prompts give random results")
    suffix = STYLES[args.style]
    full = f"{prompt}, {suffix}" if suffix else prompt
    info(f"prompt: {full}")
    info(f"seed: {seed}")
    if device == "cpu":
        modes = ["cpu"]
    else:
        total = torch.cuda.get_device_properties(0).total_memory / 2**30
        modes = (["gpu"] if total >= 6 else []) + ["model_offload", "sequential_offload", "cpu"]
    last = None
    for mode in modes:
        pipe = None
        try:
            progress(3, f"loading text-to-image model ({mode})")
            pipe = load_t2i(mode, device if mode != "cpu" else "cpu")
            progress(10, "generating concept image")
            image = lcm_sample(pipe, full, args.negative, args.steps, seed, args.neg_cfg,
                               "cpu" if mode == "cpu" else device)
            return image
        except Exception as e:  # noqa: BLE001
            if not is_oom(e):
                raise
            last = e
            warn(f"CUDA out of memory in text-to-image ({mode}), retrying with less VRAM")
        finally:
            if pipe is not None:
                try:
                    pipe.maybe_free_model_hooks()
                    pipe.remove_all_hooks()
                except Exception:  # noqa: BLE001
                    pass
                del pipe
            free_cuda()
    raise GenError(f"text-to-image failed: {last}")


# ----------------------------------------------------------------------------- stage 2: background removal
def chroma_matte(img, threshold=0.035):
    """Mask for renders on a plain backdrop (concept art): background = everything connected to the
    image border whose chromaticity (color independent of brightness) matches the border color.
    Floor shadows keep the backdrop's chromaticity, so they are dropped; thin limbs of another
    color survive, which a generic salient-object model like u2net sometimes cuts off."""
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    rgb = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    total = rgb.sum(axis=2, keepdims=True) + 1e-4
    chroma = rgb[..., :2] / total
    border = np.concatenate([chroma[0], chroma[-1], chroma[:, 0], chroma[:, -1]])
    bg_chroma = np.median(border, axis=0)
    dist = np.linalg.norm(chroma - bg_chroma, axis=2)
    candidate = dist < threshold
    labels, _n = ndimage.label(candidate)
    edge_labels = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    background = np.isin(labels, edge_labels[edge_labels > 0])
    fg = ndimage.binary_opening(~background, iterations=2)
    fg_labels, n = ndimage.label(fg)
    if n > 1:  # keep the character, drop specks
        sizes = ndimage.sum(fg, fg_labels, range(1, n + 1))
        fg = np.isin(fg_labels, np.nonzero(sizes >= sizes.max() * 0.02)[0] + 1)
    fg = ndimage.binary_fill_holes(fg)
    alpha = ndimage.gaussian_filter(fg.astype(np.float32), 1.0)
    rgba = np.dstack([rgb, alpha])
    return Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA")


def prepare_image(img, keep_bg, fg_ratio=0.85, matte="rembg"):
    """Returns a 512x512 RGB image with the object centered on a 50% gray background (TripoSR input)."""
    import numpy as np
    from PIL import Image
    has_alpha = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
    if has_alpha:
        img = img.convert("RGBA")
        if img.getextrema()[3][0] == 255:
            has_alpha = False  # fully opaque alpha channel carries no mask
    if keep_bg and not has_alpha:
        return img.convert("RGB").resize((512, 512), Image.LANCZOS)
    if not has_alpha and matte == "chroma":
        img = chroma_matte(img)
        has_alpha = True
    if not has_alpha:
        import rembg
        session = rembg.new_session("u2net", providers=["CPUExecutionProvider"])
        img = rembg.remove(img.convert("RGB"), session=session)
    rgba = np.array(img.convert("RGBA"))
    rgba[rgba[..., 3] < 16, 3] = 0  # drop faint matting noise so the bbox is tight
    if not (rgba[..., 3] > 0).any():
        raise GenError("background removal left nothing - try another image or --keep-bg")
    from tsr.utils import resize_foreground
    rgba = np.array(resize_foreground(Image.fromarray(rgba), fg_ratio)).astype(np.float32) / 255.0
    rgb = rgba[..., :3] * rgba[..., 3:4] + (1.0 - rgba[..., 3:4]) * 0.5
    return Image.fromarray((rgb * 255.0 + 0.5).astype(np.uint8)).resize((512, 512), Image.LANCZOS)


# ----------------------------------------------------------------------------- stage 3: TripoSR
def load_tsr():
    from tsr.system import TSR
    from tsr.models import isosurface
    if getattr(isosurface, "ROYALTIM_PATCH", None) is None:
        raise GenError(f"TripoSR in {TRIPOSR_DIR} is not patched - run tools/ai_models/setup.ps1")
    model = TSR.from_pretrained(TSR_REPO, config_name="config.yaml", weight_name="model.ckpt")
    model.eval()
    return model


def density_grid(model, scene_code, res, device, chunk):
    """Evaluates TripoSR density on a res^3 grid; grid points are generated per block (low RAM/VRAM)."""
    import numpy as np
    import torch
    r = model.renderer.cfg.radius
    lin = torch.linspace(-r, r, res)  # == scale_tensor(linspace(0, 1), (0, 1), (-r, r)) in extract_mesh
    n = res ** 3
    out = np.empty(n, dtype=np.float32)
    block = max(chunk * 32, 65536)
    next_report = 0.0
    for s in range(0, n, block):
        idx = torch.arange(s, min(s + block, n))
        pts = torch.stack([lin[idx // (res * res)], lin[(idx // res) % res], lin[idx % res]], dim=-1)
        with torch.no_grad():
            d = model.renderer.query_triplane(model.decoder, pts.to(device), scene_code)["density_act"]
        out[s:s + len(idx)] = d.float().view(-1).cpu().numpy()
        frac = (s + len(idx)) / n
        if frac >= next_report:
            progress(55 + 20 * frac, f"evaluating density grid {int(frac * 100)}%")
            next_report += 0.2
    return out


def query_colors(model, scene_code, verts, device, block=65536):
    import numpy as np
    import torch
    cols = []
    for s in range(0, len(verts), block):
        pts = torch.from_numpy(verts[s:s + block].astype(np.float32)).to(device)
        with torch.no_grad():
            cols.append(model.renderer.query_triplane(model.decoder, pts, scene_code)["color"].float().cpu().numpy())
    return np.concatenate(cols, axis=0) if cols else np.zeros((0, 3), np.float32)


def image_to_scene(model, image, device):
    """Runs TripoSR forward pass (image -> triplane scene code) on device. Returns (scene_code, device_used)."""
    import torch
    for dev in ([device, "cpu"] if device != "cpu" else ["cpu"]):
        try:
            model.to(dev)
            with torch.no_grad():
                scene_codes = model([image], device=dev)
            return scene_codes[0], dev
        except Exception as e:  # noqa: BLE001
            if dev == "cpu" or not is_oom(e):
                raise
            warn("CUDA out of memory in TripoSR forward pass - falling back to CPU (slower)")
            model.to("cpu")
            free_cuda()


def extract(model, scene_code, res, device):
    """Density grid + marching cubes with OOM fallback: chunk 8192 -> 2048 -> 1024 -> CPU."""
    import torch
    attempts = [(device, c) for c in CHUNK_SIZES] if device != "cpu" else []
    attempts.append(("cpu", CHUNK_SIZES[0]))
    for dev, chunk in attempts:
        try:
            model.renderer.set_chunk_size(chunk)
            model.decoder.to(dev)  # the renderer has no weights; the decoder is a small MLP
            code = scene_code.to(dev)
            dens = density_grid(model, code, res, dev, chunk)
            return dens, code, dev
        except Exception as e:  # noqa: BLE001
            if dev == "cpu" or not is_oom(e):
                raise
            warn(f"CUDA out of memory with chunk size {chunk}, retrying smaller")
            free_cuda()
    raise GenError("mesh extraction failed")


def marching_cubes(model, density, res):
    import numpy as np
    import torch
    model.set_marching_cubes_resolution(res)
    helper = model.isosurface_helper  # patched PyMCubes helper (tsr/models/isosurface.py)
    level = torch.from_numpy(-(density - MC_THRESHOLD))
    v, f = helper(level)
    r = model.renderer.cfg.radius
    v = v.numpy().astype(np.float64) * (2 * r) - r  # scale_tensor((0, 1) -> (-r, r))
    return v, f.numpy().astype(np.int64)


# ----------------------------------------------------------------------------- stage 4: mesh post-processing
def remove_floaters(v, f, min_frac=0.005):
    import numpy as np
    import trimesh
    if len(f) == 0:
        return v, f
    labels = trimesh.graph.connected_component_labels(trimesh.graph.face_adjacency(f), node_count=len(f))
    counts = np.bincount(labels)
    keep_labels = np.where(counts >= max(min_frac * len(f), 1))[0]
    if len(keep_labels) == 0:
        keep_labels = [np.argmax(counts)]
    keep = np.isin(labels, keep_labels)
    removed = len(counts) - len(keep_labels)
    if removed:
        info(f"removed {removed} tiny floating fragment(s)")
    f = f[keep]
    used = np.unique(f)
    remap = -np.ones(len(v), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return v[used], remap[f]


def decimate(v, f, target):
    if target <= 0 or len(f) <= target:
        return v, f
    try:
        import fast_simplification
    except ImportError:
        warn("fast_simplification not installed - skipping decimation")
        return v, f
    import numpy as np
    pts, faces = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int32),
                                              target_reduction=1.0 - target / len(f), agg=5)
    return pts.astype(np.float64), faces.astype(np.int64)


def to_godot_frame(v, height):
    """TripoSR frame: +Z up, input camera on +X, image-right = +Y.
    Godot/glTF: +Y up, model front faces +Z, +X right. (x, y, z) -> (y, z, x) is a proper rotation."""
    import numpy as np
    g = v[:, [1, 2, 0]].copy()
    lo, hi = g.min(axis=0), g.max(axis=0)
    g[:, 0] -= (lo[0] + hi[0]) / 2
    g[:, 2] -= (lo[2] + hi[2]) / 2
    g[:, 1] -= lo[1]
    h = hi[1] - lo[1]
    if h > 1e-8:
        g *= height / h
    return g


def srgb_to_linear(c):
    import numpy as np
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def export_glb(path, name, verts, faces, colors_srgb):
    """Minimal glTF 2.0 binary writer: POSITION, NORMAL, COLOR_0 (float, linear per spec) + one matte material.
    Godot 4.7 importer quirk: FLAG_ALBEDO_FROM_VERTEX_COLOR is only applied from the 2nd primitive of a
    mesh on (the material is read before COLOR_0 is parsed). The material object is shared, so the mesh
    is written as 2 primitives (all faces but one + the last face) sharing vertex data and material."""
    import json
    import struct
    import numpy as np
    import trimesh
    mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    v = np.ascontiguousarray(mesh.vertices, np.float32)
    n = np.ascontiguousarray(mesh.vertex_normals, np.float32)
    c = np.ascontiguousarray(srgb_to_linear(np.clip(colors_srgb, 0.0, 1.0)), np.float32)
    f = np.ascontiguousarray(mesh.faces, np.uint32)
    parts = [v, n, c, f[:-1].reshape(-1), f[-1:].reshape(-1)]
    buf, views = bytearray(), []
    for i, arr in enumerate(parts):
        buf += b"\0" * (-len(buf) % 4)
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": arr.nbytes,
                      "target": 34962 if i < 3 else 34963})
        buf += arr.tobytes()
    buf += b"\0" * (-len(buf) % 4)
    acc = [
        {"bufferView": 0, "componentType": 5126, "count": len(v), "type": "VEC3",
         "min": v.min(axis=0).tolist(), "max": v.max(axis=0).tolist()},
        {"bufferView": 1, "componentType": 5126, "count": len(n), "type": "VEC3"},
        {"bufferView": 2, "componentType": 5126, "count": len(c), "type": "VEC3"},
        {"bufferView": 3, "componentType": 5125, "count": int(parts[3].size), "type": "SCALAR"},
        {"bufferView": 4, "componentType": 5125, "count": int(parts[4].size), "type": "SCALAR"},
    ]
    attrs = {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}
    gltf = {
        "asset": {"version": "2.0", "generator": "ROYALTIM-3 tools/ai_models (TripoSR)"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [
            {"attributes": attrs, "indices": 3, "material": 0, "mode": 4},
            {"attributes": attrs, "indices": 4, "material": 0, "mode": 4}]}],
        "materials": [{"name": f"{name}_vertex_color", "pbrMetallicRoughness": {
            "baseColorFactor": [1.0, 1.0, 1.0, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "accessors": acc, "bufferViews": views, "buffers": [{"byteLength": len(buf)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    data = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(buf))
            + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(buf), 0x004E4942) + bytes(buf))
    tmp = path.with_suffix(".glb.tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)
    return mesh


# ----------------------------------------------------------------------------- main flow
def setup_imports():
    if not (TRIPOSR_DIR / "tsr").is_dir():
        raise GenError(f"TripoSR not found in {TRIPOSR_DIR} - run tools/ai_models/setup.ps1")
    sys.path.insert(0, str(TRIPOSR_DIR))
    import warnings
    warnings.filterwarnings("ignore")


def pick_device(args):
    import torch
    if args.cpu:
        return "cpu"
    if not torch.cuda.is_available():
        warn("CUDA GPU not available - running on CPU (slow)")
        return "cpu"
    return "cuda"


def generate(args):
    import numpy as np
    import torch
    from PIL import Image
    t0 = time.time()
    progress(0, "starting")
    setup_imports()
    name, out = resolve_output(args)
    device = pick_device(args)
    if device == "cuda":
        torch.cuda.reset_peak_memory_stats()
        free, total = torch.cuda.mem_get_info()
        info(f"GPU: {torch.cuda.get_device_name(0)}, VRAM free {free / 2**20:.0f} / {total / 2**20:.0f} MB")

    # 1) concept image
    if args.prompt:
        seed = args.seed if args.seed >= 0 else random.randint(0, 2**31 - 1)
        concept = text_to_image(args, device, seed)
        concept_path = out.with_name(out.stem + "_concept.png")
        concept.save(concept_path)
        info(f"concept image: {concept_path}")
        progress(30, "concept image saved")
    else:
        src = Path(args.image).expanduser()
        if not src.is_file():
            raise GenError(f"image not found: {src}")
        concept = Image.open(src)
        concept.load()

    # 2) background removal + recentering
    progress(32, "removing background" if not args.keep_bg else "preparing image")
    image = prepare_image(concept, args.keep_bg, matte=args.matte)
    image.save(out.with_name(out.stem + "_input.png"))  # exactly what TripoSR saw

    # 3) TripoSR (text-to-image pipeline is already freed from VRAM here)
    progress(38, "loading TripoSR")
    model = load_tsr()
    progress(45, "reconstructing 3D (image -> triplane)")
    scene_code, dev_used = image_to_scene(model, image, device)
    # only the tiny NeRF decoder is needed from here on; keep the big modules off the GPU
    for m in (model.image_tokenizer, model.backbone, model.post_processor):
        m.to("cpu")
    free_cuda()
    progress(55, f"extracting surface (marching cubes {args.mc_res}^3)")
    # even if the forward pass fell back to CPU, the grid query is retried on the GPU first
    density, code, dev_used = extract(model, scene_code, args.mc_res, device)
    progress(76, "marching cubes")
    v, f = marching_cubes(model, density, args.mc_res)
    del density
    if len(f) == 0:
        raise GenError("TripoSR produced an empty mesh - try another image/seed")
    info(f"raw mesh: {len(v)} vertices, {len(f)} faces")

    # 4) cleanup, decimation, colors, Godot orientation
    progress(80, "cleaning mesh")
    v, f = remove_floaters(v, f)
    if args.faces > 0 and len(f) > args.faces:
        progress(84, f"decimating to {args.faces} faces")
        v, f = decimate(v, f, args.faces)
    progress(90, "sampling vertex colors")
    colors = query_colors(model, code, v, dev_used)
    verts = to_godot_frame(v, args.height)
    progress(95, "exporting GLB")
    mesh = export_glb(out, name, verts, f, colors)

    peak = torch.cuda.max_memory_allocated() / 2**20 if device == "cuda" else 0.0
    lo, hi = mesh.bounds
    info(f"mesh: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces, "
         f"bbox min {np.round(lo, 3).tolist()} max {np.round(hi, 3).tolist()}")
    info(f"time {time.time() - t0:.1f}s, peak torch VRAM {peak:.0f} MB, file {out.stat().st_size / 1024:.0f} KB")
    if args.rig:
        out = rig_with_blender(out, args.faces if args.faces > 0 else 5000)
    progress(100, "done")
    return out


# ----------------------------------------------------------------------------- stage 5: Blender rig
def find_blender():
    """BLENDER_EXE, then Steam libraries, then the usual install folders."""
    env = os.environ.get("BLENDER_EXE")
    if env and Path(env).is_file():
        return Path(env)
    candidates = []
    steam_vdf = Path(r"C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf")
    if steam_vdf.is_file():
        for m in re.finditer(r'"path"\s+"([^"]+)"', steam_vdf.read_text(encoding="utf-8", errors="ignore")):
            candidates.append(Path(m.group(1).replace("\\\\", "\\")) / "steamapps/common/Blender/blender.exe")
    for base in (Path(r"C:\Program Files\Blender Foundation"), Path(r"D:\Program Files\Blender Foundation")):
        if base.is_dir():
            candidates.extend(sorted(base.glob("*/blender.exe"), reverse=True))
    for c in candidates:
        if c.is_file():
            return c
    return None


def rig_with_blender(src, faces, remesh=True):
    import subprocess
    blender = find_blender()
    if not blender:
        warn("Blender not found (set BLENDER_EXE) - skipping rigging, static model kept")
        return src
    dst = src.with_name(src.stem + "_rigged.glb")
    script = Path(__file__).with_name("blender") / "rig_and_animate.py"
    progress(96, "rigging and animating in Blender")
    cmd = [str(blender), "-b", "--factory-startup", "-P", str(script), "--", str(src), str(dst),
           "--faces", str(faces)] + (["--remesh"] if remesh else [])
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in proc.stdout.splitlines():
        if line.startswith("INFO: ") and ("limbs" in line or "skinned" in line or "animations" in line or "remeshed" in line):
            print(line, flush=True)
    if proc.returncode != 0 or not dst.is_file():
        tail = [l for l in proc.stdout.splitlines() if l.startswith("ERROR")] or proc.stderr.splitlines()[-3:]
        warn("rigging failed, static model kept: " + " | ".join(tail))
        return src
    info(f"rigged model: {dst}")
    return dst


def download_models(args):
    from huggingface_hub import hf_hub_download, snapshot_download
    progress(0, "downloading TripoSR weights")
    hf_hub_download(TSR_REPO, "config.yaml")
    hf_hub_download(TSR_REPO, "model.ckpt")
    hf_hub_download(DINO_REPO, "config.json")
    progress(40, "downloading rembg u2net")
    import rembg
    rembg.new_session("u2net", providers=["CPUExecutionProvider"])
    if not args.no_text2img:
        progress(50, "downloading LCM Dreamshaper v7")
        snapshot_download(T2I_REPO, allow_patterns=T2I_FILES)
    progress(100, "models downloaded")


def self_check():
    import numpy as np
    import torch
    setup_imports()
    info(f"python {sys.version.split()[0]}, torch {torch.__version__}, CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        free, total = torch.cuda.mem_get_info()
        info(f"GPU {torch.cuda.get_device_name(0)}: {total / 2**20:.0f} MB total, {free / 2**20:.0f} MB free now")
    else:
        warn("no CUDA GPU visible to torch - generation will run on CPU")
    import diffusers, transformers, rembg, trimesh, mcubes, fast_simplification  # noqa: F401,E401
    from tsr.models import isosurface
    if getattr(isosurface, "ROYALTIM_PATCH", None) is None:
        raise GenError("TripoSR isosurface.py is not patched")
    # marching-cubes orientation test: a ball must come out with outward normals (positive volume)
    helper = isosurface.MarchingCubeHelper(48)
    g = helper.grid_vertices.numpy() * 2 - 1
    dens = 50.0 * (0.6 - np.linalg.norm(g - [0.1, 0, 0], axis=1))  # "density" > 0 inside
    v, f = helper(torch.from_numpy(-dens.astype(np.float32)))
    m = trimesh.Trimesh(v.numpy(), f.numpy(), process=False)
    if not (m.is_watertight and m.volume > 0):
        raise GenError(f"marching cubes self-test failed (watertight={m.is_watertight}, volume={m.volume})")
    info(f"marching cubes OK ({len(f)} faces, outward normals); diffusers {diffusers.__version__}, "
         f"transformers {transformers.__version__}, trimesh {trimesh.__version__}")
    info("self-check passed")


def main(argv=None):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
    except Exception:  # noqa: BLE001
        pass
    args = parse_args(argv)
    try:
        if args.download_models:
            download_models(args)
            return 0
        if args.self_check:
            self_check()
            return 0
        if args.rig_file:
            src = Path(args.rig_file).resolve()
            if not src.is_file():
                raise GenError(f"model not found: {src}")
            out = rig_with_blender(src, args.faces if args.faces > 0 else 5000, remesh=not args.no_remesh)
            if out == src:
                raise GenError("rigging failed (see warnings above)")
            print(f"RESULT: {out}", flush=True)
            return 0
        out = generate(args)
        print(f"RESULT: {out}", flush=True)
        return 0
    except KeyboardInterrupt:
        print("ERROR: cancelled", flush=True)
        return 130
    except GenError as e:
        print(f"ERROR: {e}", flush=True)
        return 1
    except Exception as e:  # noqa: BLE001
        traceback.print_exc(file=sys.stderr)
        msg = str(e).strip().splitlines()[0] if str(e).strip() else type(e).__name__
        print(f"ERROR: {type(e).__name__}: {msg}", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
