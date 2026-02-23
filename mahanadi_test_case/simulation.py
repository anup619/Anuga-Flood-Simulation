from __future__ import annotations

import os
import time
from typing import Callable, Tuple, Dict, List

import anuga
import shapefile
import netCDF4 as nc
import numpy as np

from config import Config


# =============================================================================
# DEM + Shapefile helpers
# =============================================================================

def read_asc_header(path: str) -> Dict[str, float | int]:
    header = {}
    with open(path, "r", encoding="utf-8") as f:
        for _ in range(6):
            k, v = f.readline().strip().split()
            header[k.lower()] = float(v) if ("." in v or "e" in v.lower()) else int(v)
    return header


def asc_extent(header):
    xll = float(header["xllcorner"])
    yll = float(header["yllcorner"])
    ncols = int(header["ncols"])
    nrows = int(header["nrows"])
    cs = float(header["cellsize"])

    xmin, ymin = xll, yll
    xmax = xll + ncols * cs
    ymax = yll + nrows * cs

    return xmin, ymin, xmax, ymax


def read_first_point(shp_path: str) -> Tuple[float, float]:
    sf = shapefile.Reader(shp_path)
    shapes = sf.shapes()

    if not shapes:
        raise ValueError("Shapefile has no features")

    shp = shapes[0]

    if shp.shapeType not in (shapefile.POINT, shapefile.POINTZ, shapefile.POINTM):
        raise ValueError("Expected point shapefile")

    x, y = shp.points[0]
    return float(x), float(y)

def read_polygon_from_shapefile(shp_path: str) -> List[Tuple[float, float]]:
    sf = shapefile.Reader(shp_path)
    shapes = sf.shapes()

    if not shapes:
        raise ValueError("Shapefile has no features")

    shp = shapes[0]

    if shp.shapeType not in (shapefile.POLYGON, shapefile.POLYGONZ, shapefile.POLYGONM):
        raise ValueError(f"Expected polygon shapefile, got shapeType {shp.shapeType}")

    points = shp.points
    
    polygon = [(float(x), float(y)) for x, y in points]
    
    if polygon[0] != polygon[-1]:
        polygon.append(polygon[0])
    
    return polygon

def get_stage_at_time(sww_path, target_time=None):
    with nc.Dataset(sww_path, 'r') as fid:
        times = fid.variables['time'][:]

        if target_time is None:
            t_idx = -1
        else:
            t_idx = np.argmin(np.abs(times - target_time))
            print(f"Requested t={target_time}s, using closest: t={times[t_idx]:.1f}s (index {t_idx})")

        if 'stage_c' in fid.variables:
            stage = fid.variables['stage_c'][t_idx, :]  # shape: (n_triangles,)
        else:
            stage_v = fid.variables['stage'][t_idx, :]
            vols = fid.variables['volumes'][:]
            stage = np.mean(stage_v[vols], axis=1)

    return stage

# =============================================================================
# Forcing builders
# =============================================================================

def build_dam_release(cfg: Config) -> Callable[[float], float]:

    peak = cfg.dam_release.peak_discharge_cumecs
    base = cfg.dam_release.base_discharge_cumecs

    def dam_release_Q(t: float) -> float:

        if t <= 10 * 60:
            return peak * (t / (10 * 60))

        if t <= 60 * 60:
            return peak

        if t <= 120 * 60:
            frac = (t - 60 * 60) / (60 * 60)
            return peak + frac * (base - peak)

        return base

    return dam_release_Q

def build_rainfall(cfg: Config) -> Callable[[float], float]:

    if not cfg.rainfall.enable:
        return lambda t: 0.0

    peak_mps = cfg.rainfall.intensity_mm_hr / 1000.0 / 3600.0

    dry = cfg.rainfall.dry_minutes * 60
    ramp = cfg.rainfall.ramp_up_minutes * 60
    hold = cfg.rainfall.hold_minutes * 60
    taper = cfg.rainfall.taper_minutes * 60

    t0 = dry
    t1 = t0 + ramp
    t2 = t1 + hold
    t3 = t2 + taper

    def rainfall_mps(t: float) -> float:

        if t <= t0:
            return 0.0

        if ramp > 0 and t <= t1:
            frac = (t - t0) / ramp
            return peak_mps * frac

        if t <= t2:
            return peak_mps

        if taper > 0 and t <= t3:
            frac = (t - t2) / taper
            return peak_mps * (1 - frac)

        return 0.0

    return rainfall_mps

def get_mesh_filepath(cfg: Config) -> str:
    boundary_suffix = ""
    if cfg.boundary.use_polygon_boundary:
        boundary_suffix = f"_poly_{cfg.boundary.boundary_type}"
    else:
        boundary_suffix = f"_rect_{cfg.boundary.boundary_type}"
        
    mesh_filename = f"{cfg.paths.name_stem}{boundary_suffix}.msh"
    return os.path.join(cfg.mesh.mesh_cache_dir, mesh_filename)


# =============================================================================
# Main simulation runner
# =============================================================================

def run_simulation(cfg: Config) -> None:
    from anuga import myid, numprocs, distribute, barrier, finalize

    is_parallel = bool(cfg.parallel.enable) and numprocs > 1

    if myid == 0:
        print("=" * 70)
        print(f"ANUGA {'PARALLEL' if is_parallel else 'SERIAL'} RUN | ranks={numprocs}")
        print("=" * 70)

        print("\nSIMULATION SETTINGS:")
        print(f"  Duration: {cfg.simulation.final_time_hours} hours")
        print(f"  Dam peak discharge: {cfg.dam_release.peak_discharge_cumecs} m^3/s")
        
        if cfg.boundary.use_polygon_boundary:
            print(f"  Boundary: POLYGON from {os.path.basename(cfg.paths.aoi_shp_path)} ({cfg.boundary.boundary_type.upper()})")
        else:
            print(f"  Boundary: RECTANGULAR DEM extent ({cfg.boundary.boundary_type.upper()})")
            
        if cfg.rainfall.enable:
            print(f"  Rainfall: ENABLED ({cfg.rainfall.intensity_mm_hr} mm/hr peak)")
            print(
                f"  Rain schedule (min): dry={cfg.rainfall.dry_minutes}, "
                f"ramp={cfg.rainfall.ramp_up_minutes}, hold={cfg.rainfall.hold_minutes}, "
                f"taper={cfg.rainfall.taper_minutes}"
            )
        else:
            print("  Rainfall: DISABLED")
        
        if cfg.initial_conditions.hot_start:
            print(f"  Hot Start: ENABLED, using file: {cfg.paths.hot_start_path}")
        else:
            print("  Hot Start: DISABLED")
        print(f"  Manning n: {cfg.initial_conditions.friction_mannings_n}")
        print(f"  Max triangle area: {cfg.mesh.max_triangle_area_m2} m^2")
        print("=" * 70)

    os.makedirs(cfg.paths.output_dir, exist_ok=True)

    domain = None
    pts_path = None
    dam_x = dam_y = None

    if myid == 0:
        # Load DEM header + extent
        header = read_asc_header(cfg.paths.asc_path)
        xmin, ymin, xmax, ymax = asc_extent(header)

        # Load dam location + check inside DEM
        dam_x, dam_y = read_first_point(cfg.paths.dam_shp_path)
        
        # Determine bounding polygon and boundary tags based on configuration
        if cfg.boundary.use_polygon_boundary:
            # Use polygon from shapefile
            bounding_polygon = read_polygon_from_shapefile(cfg.paths.aoi_shp_path)
            
            # Tag all polygon edges with a single tag
            num_edges = len(bounding_polygon) - 1  # -1 because polygon is closed
            boundary_tags = {"exterior": list(range(num_edges))}
            
            print(f"[rank 0] Using polygon boundary with {num_edges} edges")
            
            # Verify dam is inside polygon (simple bounding box check)
            poly_xs = [p[0] for p in bounding_polygon]
            poly_ys = [p[1] for p in bounding_polygon]
            poly_xmin, poly_xmax = min(poly_xs), max(poly_xs)
            poly_ymin, poly_ymax = min(poly_ys), max(poly_ys)
            
            if not (poly_xmin <= dam_x <= poly_xmax and poly_ymin <= dam_y <= poly_ymax):
                print(f"WARNING: Dam point ({dam_x:.1f}, {dam_y:.1f}) may be outside polygon bounds!")
        else:
            # Use rectangular DEM extent
            bounding_polygon = [(xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax)]
            boundary_tags = {"south": [0], "east": [1], "north": [2], "west": [3]}
            
            print(f"[rank 0] Using rectangular DEM boundary")
            
            # Check dam inside DEM
            if not (xmin <= dam_x <= xmax and ymin <= dam_y <= ymax):
                raise ValueError("Dam point is outside DEM extent!")

        # Convert DEM -> .dem -> .pts (cached for speed)
        anuga.asc2dem(cfg.paths.asc_path, use_cache=False, verbose=False)
        dem_path = os.path.join(os.path.dirname(cfg.paths.asc_path), f"{cfg.paths.name_stem}.dem")
        pts_path = os.path.join(os.path.dirname(cfg.paths.asc_path), f"{cfg.paths.name_stem}.pts")
        anuga.dem2pts(dem_path, use_cache=False, verbose=False)

        # Build mesh + domain        
        mesh_filepath = get_mesh_filepath(cfg)

        if cfg.mesh.use_cached_mesh:
            os.makedirs(cfg.mesh.mesh_cache_dir, exist_ok=True)
            if os.path.exists(mesh_filepath):
                print(f"[rank 0] USING CACHED MESH: {mesh_filepath}")
            else:
                print(f"[rank 0] Cached mesh not found, generating new mesh...")

        domain = anuga.create_domain_from_regions(
            bounding_polygon,
            boundary_tags=boundary_tags,
            maximum_triangle_area=cfg.mesh.max_triangle_area_m2,
            minimum_triangle_angle=cfg.mesh.min_angle_deg,
            mesh_filename=mesh_filepath if cfg.mesh.use_cached_mesh else None,
            use_cache=cfg.mesh.use_cached_mesh,
            verbose=True,
        )

        domain.set_name(cfg.paths.output_file)
        domain.set_datadir(cfg.paths.output_dir)

        if cfg.mesh.use_cached_mesh and not os.path.exists(mesh_filepath):
            print(f"[rank 0] SAVED MESH TO: {mesh_filepath}")

        # Domain settings
        domain.set_minimum_storable_height(0.01)
        domain.set_flow_algorithm("DE0")
        domain.set_CFL(cfg.simulation.cfl)

        # Elevation (rank 0 only before distribute)
        domain.set_quantity(
            "elevation",
            filename=pts_path,
            use_cache=True,
            verbose=False,
            alpha=0.1,
        )
        
        if cfg.initial_conditions.hot_start:
            stage_ic = get_stage_at_time(cfg.paths.hot_start_path, target_time=172800)
            domain.set_quantity('stage', stage_ic, location='centroids')

        if myid == 0:
            print(f"[rank 0] Mesh triangles: {domain.number_of_elements:,}")
            print(f"[rank 0] PTS used: {pts_path}")
            print(f"[rank 0] Dam at: ({dam_x:.1f}, {dam_y:.1f})")

    if is_parallel:
        domain = distribute(domain)

    if domain is None:
        raise RuntimeError("Domain was not created. Check MPI/parallel setup.")

    domain.set_quantity("friction", cfg.initial_conditions.friction_mannings_n)

    if cfg.boundary.boundary_type == "reflective":
        bc = anuga.Reflective_boundary(domain)
    else:
        bc = anuga.Transmissive_boundary(domain)
    
    if cfg.boundary.use_polygon_boundary:
        domain.set_boundary({"exterior": bc})
    else:
        domain.set_boundary({"west": bc, "east": bc, "south": bc, "north": bc})

    dam_Q = build_dam_release(cfg)
    rain_rate = build_rainfall(cfg)

    dam_x, dam_y = read_first_point(cfg.paths.dam_shp_path)

    inlet_region = anuga.Region(domain, center=(dam_x, dam_y), radius=cfg.dam_release.inlet_radius_m)
    anuga.Inlet_operator(domain, inlet_region, Q=dam_Q)

    if cfg.rainfall.enable:
        try:
            from anuga.operators.rate_operators import Rate_operator
            Rate_operator(domain, rate=rain_rate, factor=1.0)
        except Exception as e:
            if myid == 0:
                print("Rainfall operator not available:", e)

    final_time = cfg.simulation.final_time_hours * 3600.0

    if is_parallel:
        barrier()

    start = time.time()

    if cfg.simulation.print_simulation_logs and myid == 0:
        print(f"{'Time':>10s} {'Progress':>10s}")

    for t in domain.evolve(yieldstep=cfg.simulation.yieldstep_s, finaltime=final_time):
        if cfg.simulation.print_simulation_logs and myid == 0:
            progress = 100.0 * t / final_time
            print(f"{t/3600:8.2f} hr {progress:9.1f}%")

    if is_parallel:
        domain.sww_merge(delete_old=True)

    if myid == 0:
        elapsed = time.time() - start
        print("=" * 70)
        print(f"DONE | parallel={is_parallel} | ranks={numprocs} | time={elapsed/60:.1f} min")
        print(f"Outputs: {os.path.abspath(cfg.paths.output_dir)}")
        print("=" * 70)

    if is_parallel:
        finalize()