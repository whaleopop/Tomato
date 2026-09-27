# ROYALTIM-3 patch for TripoSR (copied over tsr/models/isosurface.py by tools/ai_models/setup.ps1).
# The original uses torchmcubes, which must be compiled (C++/CUDA). This version uses PyMCubes
# (module `mcubes`, prebuilt wheels) on a CPU numpy volume and reproduces the original output
# convention exactly: vertices in (dim0, dim1, dim2) grid-index order scaled by 1/(res-1) to
# [0, 1], and the same triangle winding as torchmcubes + TripoSR's [2, 1, 0] axis swap.
from typing import Optional, Tuple

import mcubes
import numpy as np
import torch
import torch.nn as nn

ROYALTIM_PATCH = "pymcubes-v1"

# Verified against a line-by-line Python port of torchmcubes on asymmetric test volumes:
# PyMCubes output (no axis swap) == torchmcubes + TripoSR's [2, 1, 0] swap, with identical
# vertices and identical winding (outward normals, positive signed volume), so no flip is needed.


class IsosurfaceHelper(nn.Module):
    points_range: Tuple[float, float] = (0, 1)

    @property
    def grid_vertices(self) -> torch.FloatTensor:
        raise NotImplementedError


class MarchingCubeHelper(IsosurfaceHelper):
    def __init__(self, resolution: int) -> None:
        super().__init__()
        self.resolution = resolution
        self._grid_vertices: Optional[torch.FloatTensor] = None

    @property
    def grid_vertices(self) -> torch.FloatTensor:
        if self._grid_vertices is None:
            # keep the vertices on CPU so that we can support very large resolution
            x, y, z = (
                torch.linspace(*self.points_range, self.resolution),
                torch.linspace(*self.points_range, self.resolution),
                torch.linspace(*self.points_range, self.resolution),
            )
            x, y, z = torch.meshgrid(x, y, z, indexing="ij")
            verts = torch.cat(
                [x.reshape(-1, 1), y.reshape(-1, 1), z.reshape(-1, 1)], dim=-1
            ).reshape(-1, 3)
            self._grid_vertices = verts
        return self._grid_vertices

    def forward(
        self,
        level: torch.FloatTensor,
    ) -> Tuple[torch.FloatTensor, torch.LongTensor]:
        device = level.device
        level = -level.view(self.resolution, self.resolution, self.resolution)
        volume = level.detach().float().cpu().numpy().astype(np.float64)
        # mcubes returns vertices already in (dim0, dim1, dim2) order, i.e. what the original
        # code gets after `v_pos[..., [2, 1, 0]]` on torchmcubes' (x=dim2, y=dim1, z=dim0) output.
        verts, faces = mcubes.marching_cubes(volume, 0.0)
        v_pos = torch.from_numpy(np.ascontiguousarray(verts, dtype=np.float32))
        t_pos_idx = torch.from_numpy(np.ascontiguousarray(faces, dtype=np.int64))
        v_pos = v_pos / (self.resolution - 1.0)
        return v_pos.to(device), t_pos_idx.to(device)
