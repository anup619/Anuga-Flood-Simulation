from __future__ import annotations

import os
from typing import Any, Dict
import datetime

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

from config import (
    Config,
    PathsConfig,
    MeshConfig,
    DamReleaseConfig,
    SimulationConfig,
    InitialConditionsConfig,
    RainfallConfig,
    ParallelConfig,
    PostprocessingConfig,
    BoundaryConfig,
    validate_config,
)

def _require(section: Dict[str, Any], key: str, section_name: str) -> Any:
    if key not in section:
        raise ValueError(f"Missing '{section_name}.{key}' in settings.toml")
    return section[key]


def _abs_path(script_dir: str, maybe_rel: str) -> str:
    if os.path.isabs(maybe_rel):
        return maybe_rel
    return os.path.join(script_dir, maybe_rel)


def load_config(settings_path: str, script_dir: str) -> Config:
    with open(settings_path, "rb") as f:
        raw = tomllib.load(f)

    paths = raw.get("paths", {})
    mesh = raw.get("mesh", {})
    dam = raw.get("dam_release", {})
    sim = raw.get("simulation", {})
    init = raw.get("initial_conditions", {})
    rain = raw.get("rainfall", {})
    parallel = raw.get("parallel", {})
    postproc = raw.get("postprocessing", {})
    boundary = raw.get("boundary", {}) 
    
    output_file_name = str(_require(paths, "output_file", "paths"))
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    dynamic_run_id = f"{output_file_name}_{timestamp}"

    cfg = Config(
        paths=PathsConfig(
            name_stem=str(_require(paths, "name_stem", "paths")),
            output_file=dynamic_run_id,
            asc_path=_abs_path(script_dir, str(_require(paths, "asc_path", "paths"))),
            dam_shp_path=_abs_path(script_dir, str(_require(paths, "dam_shp_path", "paths"))),
            output_dir=_abs_path(script_dir, str(_require(paths, "output_dir", "paths"))),
            aoi_shp_path=_abs_path(script_dir, str(paths.get("aoi_shp_path", "input_files/shapfile/AOI_Anuga.shp"))),
            hot_start_path=_abs_path(script_dir, str(paths.get("hot_start_path", "input_files/hot_start.sww"))),  
        ),
        mesh=MeshConfig(
            max_triangle_area_m2=float(_require(mesh, "max_triangle_area_m2", "mesh")),
            min_angle_deg=float(_require(mesh, "min_angle_deg", "mesh")),
            use_cached_mesh=bool(mesh.get("use_cached_mesh", False)),
            mesh_cache_dir=_abs_path(script_dir, str(mesh.get("mesh_cache_dir", "mesh_cache"))),
        ),
        dam_release=DamReleaseConfig(
            inlet_radius_m=float(_require(dam, "inlet_radius_m", "dam_release")),
            peak_discharge_cumecs=float(_require(dam, "peak_discharge_cumecs", "dam_release")),
            base_discharge_cumecs=float(_require(dam, "base_discharge_cumecs", "dam_release")),
        ),
        simulation=SimulationConfig(
            final_time_hours=float(_require(sim, "final_time_hours", "simulation")),
            yieldstep_s=float(_require(sim, "yieldstep_s", "simulation")),
            cfl=float(_require(sim, "cfl", "simulation")),
            print_simulation_logs=bool(_require(sim, "print_simulation_logs", "simulation")),
        ),
        initial_conditions=InitialConditionsConfig(
            hot_start=bool(_require(init, "hot_start", False)),
            friction_mannings_n=float(_require(init, "friction_mannings_n", "initial_conditions")),
        ),
        rainfall=RainfallConfig(
            enable=bool(_require(rain, "enable", "rainfall")),
            intensity_mm_hr=float(_require(rain, "intensity_mm_hr", "rainfall")),
            dry_minutes=float(_require(rain, "dry_minutes", "rainfall")),
            ramp_up_minutes=float(_require(rain, "ramp_up_minutes", "rainfall")),
            hold_minutes=float(_require(rain, "hold_minutes", "rainfall")),
            taper_minutes=float(_require(rain, "taper_minutes", "rainfall")),
        ),
        parallel=ParallelConfig(
            enable=bool(_require(parallel, "enable", "parallel")),
        ),
        postprocessing=PostprocessingConfig(
            postprocess=bool(postproc.get("postprocess", False)),
            generate_timeseries=bool(postproc.get("generate_timeseries", False)),
            timeseries_steps=int(postproc.get("timeseries_steps", 25)),
            timeseries_cellsize=float(postproc.get("timeseries_cellsize", 10)),
        ),
        boundary=BoundaryConfig(
            use_polygon_boundary=bool(boundary.get("use_polygon_boundary", False)),
            boundary_type=str(boundary.get("boundary_type", "transmissive")),
        ),
    )

    validate_config(cfg)
    return cfg
