from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PathsConfig:
    name_stem: str
    output_file: str
    asc_path: str
    dam_shp_path: str
    output_dir: str
    aoi_shp_path: str
    hot_start_path: str


@dataclass(frozen=True)
class MeshConfig:
    max_triangle_area_m2: float
    min_angle_deg: float
    use_cached_mesh: bool
    mesh_cache_dir: str


@dataclass(frozen=True)
class DamReleaseConfig:
    inlet_radius_m: float
    peak_discharge_cumecs: float
    base_discharge_cumecs: float


@dataclass(frozen=True)
class SimulationConfig:
    final_time_hours: float
    yieldstep_s: float
    cfl: float
    print_simulation_logs: bool


@dataclass(frozen=True)
class InitialConditionsConfig:
    hot_start: bool
    friction_mannings_n: float


@dataclass(frozen=True)
class RainfallConfig:
    enable: bool
    intensity_mm_hr: float
    dry_minutes: float
    ramp_up_minutes: float
    hold_minutes: float
    taper_minutes: float
   
@dataclass(frozen=True)
class ParallelConfig:
    enable: bool
    
@dataclass(frozen=True)
class PostprocessingConfig:
    postprocess : bool
    generate_timeseries: bool
    timeseries_steps: int
    timeseries_cellsize: float
    
@dataclass(frozen=True)
class BoundaryConfig:
    use_polygon_boundary: bool
    boundary_type: str
    
@dataclass(frozen=True)
class Config:
    paths: PathsConfig
    mesh: MeshConfig
    dam_release: DamReleaseConfig
    simulation: SimulationConfig
    initial_conditions: InitialConditionsConfig
    rainfall: RainfallConfig
    parallel: ParallelConfig
    postprocessing: PostprocessingConfig
    boundary: BoundaryConfig

def validate_config(cfg: Config) -> None:
    """Fail early with friendly errors if settings are invalid."""
    if cfg.mesh.max_triangle_area_m2 <= 0:
        raise ValueError("mesh.max_triangle_area_m2 must be > 0")

    if cfg.dam_release.inlet_radius_m <= 0:
        raise ValueError("dam_release.inlet_radius_m must be > 0")

    if cfg.dam_release.peak_discharge_cumecs < 0 or cfg.dam_release.base_discharge_cumecs < 0:
        raise ValueError("dam_release discharge values must be >= 0")

    if cfg.simulation.final_time_hours <= 0:
        raise ValueError("simulation.final_time_hours must be > 0")

    if cfg.simulation.yieldstep_s <= 0:
        raise ValueError("simulation.yieldstep_s must be > 0")

    if cfg.simulation.cfl <= 0:
        raise ValueError("simulation.cfl must be > 0")

    if cfg.initial_conditions.friction_mannings_n < 0:
        raise ValueError("initial_conditions.friction_mannings_n must be >= 0")

    if cfg.rainfall.enable:
        # Basic non-negative checks for rainfall knobs
        if cfg.rainfall.intensity_mm_hr < 0:
            raise ValueError("rainfall.intensity_mm_hr must be >= 0")

        for field_name, minutes in [
            ("rainfall.dry_minutes", cfg.rainfall.dry_minutes),
            ("rainfall.ramp_up_minutes", cfg.rainfall.ramp_up_minutes),
            ("rainfall.hold_minutes", cfg.rainfall.hold_minutes),
            ("rainfall.taper_minutes", cfg.rainfall.taper_minutes),
        ]:
            if minutes < 0:
                raise ValueError(f"{field_name} must be >= 0")
            
    if cfg.boundary.boundary_type not in ["transmissive", "reflective"]:
        raise ValueError("boundary.boundary_type must be 'transmissive' or 'reflective'")