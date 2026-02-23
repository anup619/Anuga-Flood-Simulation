import os
import sys
import datetime
import requests
from requests.auth import HTTPBasicAuth
import anuga
from settings_loader import load_config

class AnugaGeoserverBridge:
    def __init__(self, settings_path: str, script_dir: str):
        self.cfg = load_config(settings_path, script_dir)
        self.gs_url = "http://localhost:8080/geoserver/rest"
        self.auth = HTTPBasicAuth("admin", "geoserver")
        self.workspace = "anuga"
        
        self.target_layer = "mahanadi_dam_release_max_depth"
        self.store_name = "mahanadi_max_depth_store"
        
    def upload_style(self, style_name="flood_depth_style"):
        style_file = os.path.join(os.path.dirname(__file__), "flood_depth_style.sld")
        
        if not os.path.exists(style_file):
            print(f"Warning: Style file not found: {style_file}")
            return False
        
        # Check if style already exists
        check_url = f"{self.gs_url}/workspaces/{self.workspace}/styles/{style_name}.json"
        check_resp = requests.get(check_url, auth=self.auth)
        
        if check_resp.status_code == 200:
            print(f"Style '{style_name}' already exists, skipping upload.")
            return True
        
        # Create the style
        create_url = f"{self.gs_url}/workspaces/{self.workspace}/styles"
        style_data = {"style": {"name": style_name, "filename": f"{style_name}.sld"}}
        
        create_resp = requests.post(
            create_url,
            json=style_data,
            headers={"Content-Type": "application/json"},
            auth=self.auth
        )
        
        if create_resp.status_code not in [200, 201]:
            print(f"Failed to create style: {create_resp.status_code} - {create_resp.text}")
            return False
        
        # Upload the SLD file
        upload_url = f"{self.gs_url}/workspaces/{self.workspace}/styles/{style_name}"
        with open(style_file, "rb") as f:
            upload_resp = requests.put(
                upload_url,
                data=f,
                headers={"Content-Type": "application/vnd.ogc.sld+xml"},
                auth=self.auth
            )
        
        if upload_resp.status_code in [200, 201]:
            print(f"Style '{style_name}' uploaded successfully")
            return True
        else:
            print(f"Failed to upload style: {upload_resp.status_code} - {upload_resp.text}")
            return False

    def generate_timeseries_asc(self, sww_path: str, run_id: str):
        import netCDF4
        import numpy as np
        
        output_dir = os.path.join(self.cfg.paths.output_dir, f"{run_id}_timeseries")
        os.makedirs(output_dir, exist_ok=True)
        
        print(f"Generating time series in: {output_dir}")
        
        # Read timesteps from SWW
        nc = netCDF4.Dataset(sww_path, "r")
        times = nc.variables["time"][:]
        nc.close()
        
        num_timesteps = len(times)
        max_exports = self.cfg.postprocessing.timeseries_steps
        cellsize = self.cfg.postprocessing.timeseries_cellsize
        
        print(f"Total timesteps: {num_timesteps}, Exporting: {max_exports}")
        
        # Select which timesteps to export
        if num_timesteps <= max_exports:
            export_indices = list(range(num_timesteps))
        else:
            export_indices = np.linspace(0, num_timesteps - 1, max_exports, dtype=int).tolist()
        
        # Generate ASC files
        for i, timestep_idx in enumerate(export_indices, start=1):
            step = f"{i:04d}"
            asc_out = os.path.join(output_dir, f"depth_{step}.asc")
            
            print(f"  {i}/{len(export_indices)}: timestep {timestep_idx} -> depth_{step}.asc")
            
            anuga.sww2dem(
                name_in=sww_path,
                name_out=asc_out,
                quantity='depth',
                reduction=timestep_idx,
                cellsize=cellsize,
                verbose=False,
            )
        
        # Create indexer.properties
        indexer_content = (
                "Name=timeseries\n"
                "TypeName=timeseries\n"
                "TimeAttribute=ingestion\n"
                "Schema=*the_geom:Polygon,location:String,ingestion:java.util.Date\n"
                "PropertyCollectors=TimestampFileNameExtractorSPI[timeregex](ingestion)\n"
            )
        
        with open(os.path.join(output_dir, "indexer.properties"), "w") as f:
            f.write(indexer_content)
        
        # Create timeregex.properties
        timeregex_content = (
            "regex=([0-9]{4})\n"
            "format=yyyy\n"
        )
        
        with open(os.path.join(output_dir, "timeregex.properties"), "w") as f:
            f.write(timeregex_content)
        
        print(f" Time series generation complete: {len(export_indices)} files")
        return output_dir

    def deploy_timeseries_to_geoserver(self, timeseries_dir: str, run_id: str):
        import zipfile
        import tempfile
        
        store_name = f"{run_id}_timeseries_store"
        layer_name = f"{run_id}_timeseries"
        
        print(f"Creating ImageMosaic for time series: {layer_name}")
        
        # Create a zip file containing all ASC files and properties
        with tempfile.NamedTemporaryFile(suffix='.zip', delete=False) as tmp_zip:
            zip_path = tmp_zip.name
            
            with zipfile.ZipFile(zip_path, 'w') as zipf:
                for filename in os.listdir(timeseries_dir):
                    file_path = os.path.join(timeseries_dir, filename)
                    if os.path.isfile(file_path):
                        zipf.write(file_path, arcname=filename)
        
        # Upload as ImageMosaic
        upload_url = (
            f"{self.gs_url}/workspaces/{self.workspace}/"
            f"coveragestores/{store_name}/file.imagemosaic"
            f"?configure=all&coverageName={layer_name}"
        )
        
        try:
            with open(zip_path, 'rb') as f:
                resp = requests.put(
                    upload_url,
                    data=f,
                    headers={"Content-type": "application/zip"},
                    auth=self.auth
                )
            
            if resp.status_code in [200, 201]:
                print(f" Time series ImageMosaic uploaded")
                
                # Configure SRS for the mosaic
                coverage_url = f"{self.gs_url}/workspaces/{self.workspace}/coveragestores/{store_name}/coverages/{layer_name}.json"
                
                coverage_data = {
                    "coverage": {
                        "srs": "EPSG:32645",
                        "projectionPolicy": "REPROJECT_TO_DECLARED",
                        "requestSRS": {
                            "string": ["EPSG:32645", "EPSG:3857", "EPSG:4326"]
                        },
                        "responseSRS": {
                            "string": ["EPSG:32645", "EPSG:3857", "EPSG:4326"]
                        }
                    }
                }
                
                update_resp = requests.put(
                    coverage_url,
                    json=coverage_data,
                    headers={"Content-type": "application/json"},
                    auth=self.auth
                )
                
                if update_resp.status_code == 200:
                    print(f" Time series SRS configured")
                
                # Configure Time Dimension
                print(f" Configuring Time dimension...")
                dimension_url = f"{self.gs_url}/workspaces/{self.workspace}/coveragestores/{store_name}/coverages/{layer_name}.json"

                dimension_data = {
                    "coverage": {
                        "metadata": {
                            "entry": [
                                {
                                    "@key": "time",
                                    "dimensionInfo": {
                                        "enabled": True,
                                        "presentation": "LIST",
                                        "units": "ISO8601",
                                        "defaultValue": {
                                            "strategy": "MINIMUM"
                                        },
                                        "nearestMatchEnabled": True
                                    }
                                }
                            ]
                        }
                    }
                }

                dimension_resp = requests.put(
                    dimension_url,
                    json=dimension_data,
                    headers={"Content-type": "application/json"},
                    auth=self.auth
                )

                if dimension_resp.status_code == 200:
                    print(f" Time dimension configured successfully")
                else:
                    print(f" Warning: Time dimension configuration responded with {dimension_resp.status_code}: {dimension_resp.text}")
                
                # Apply style
                if self.upload_style():
                    style_url = f"{self.gs_url}/layers/{self.workspace}:{layer_name}.json"
                    style_data = {
                        "layer": {
                            "defaultStyle": {
                                "name": f"{self.workspace}:flood_depth_style"
                            }
                        }
                    }
                    
                    style_resp = requests.put(
                        style_url,
                        json=style_data,
                        headers={"Content-type": "application/json"},
                        auth=self.auth
                    )
                    
                    if style_resp.status_code == 200:
                        print(f" Style applied to time series layer")
                
                print(f"SUCCESS: Time series layer '{self.workspace}:{layer_name}' deployed")
            else:
                print(f"ERROR: GeoServer responded with {resp.status_code}: {resp.text}")
        
        finally:
            # Cleanup temp zip
            if os.path.exists(zip_path):
                os.remove(zip_path)
            
    def run_post_processing(self, run_id: str = None, generate_timeseries: bool = False):
        
        sww_path = os.path.join(self.cfg.paths.output_dir, f"{run_id}.sww")
        
        asc_path = os.path.join(self.cfg.paths.output_dir, f"{run_id}_max_depth.asc")
        
        print(f"--- Starting Post-Processing for: {run_id} ---")
        
        if not os.path.exists(sww_path):
            print(f"Error: Source file not found: {sww_path}")
            return
        
        print(f"Converting {run_id}.sww to ASCII Grid...")
        try:
            anuga.sww2dem(
                sww_path, 
                asc_path, 
                quantity='depth', 
                reduction=max, 
                cellsize=10
            )
        except Exception as e:
            print(f" ANUGA sww2dem failed: {e}")
            return

        print(f"Deploying ASCII Grid to GeoServer...")
        try:
            # Use run_id to create unique store and layer names
            self.deploy_to_geoserver(asc_path, run_id)
        except Exception as e:
            print(f" X GeoServer Deployment failed: {e}")
            
        if generate_timeseries:
            print(f"\n--- Generating Time Series for: {run_id} ---")
            try:
                timeseries_dir = self.generate_timeseries_asc(sww_path, run_id)
                print(f"Deploying Time Series to GeoServer...")
                self.deploy_timeseries_to_geoserver(timeseries_dir, run_id)
            except Exception as e:
                print(f"X Time series generation/deployment failed: {e}")

        print(f"--- Finished. Result saved as: {os.path.basename(asc_path)} ---")
        print(f"Check your React dashboard for layer: {run_id}")

    def deploy_to_geoserver(self, file_path, run_id):
        filename = os.path.basename(file_path)
        is_asc = file_path.lower().endswith('.asc')
        
        # Create unique names for this run
        store_name = f"{run_id}_store"
        layer_name = f"{run_id}_max_depth"
        
        if is_asc:
            content_type = "application/arcgrid"
            format_type = "arcgrid"
        else:
            content_type = "image/geotiff"
            format_type = "geotiff"

        print(f"Deploying {filename} to GeoServer workspace: {self.workspace} (Format: {format_type})...")

        requests.post(f"{self.gs_url}/workspaces", json={"workspace": {"name": self.workspace}}, auth=self.auth)
        
        upload_url = (
            f"{self.gs_url}/workspaces/{self.workspace}/"
            f"coveragestores/{store_name}/file.{format_type}"
            f"?configure=first&coverageName={layer_name}"
        )
        
        with open(file_path, "rb") as f:
            resp = requests.put(
                upload_url,
                data=f,
                headers={"Content-type": content_type},
                auth=self.auth
            )

        if resp.status_code in [200, 201]:
            print(f"SUCCESS: Coverage uploaded. Now updating SRS to EPSG:32645...")
            
            # Update the coverage to fix SRS
            coverage_url = f"{self.gs_url}/workspaces/{self.workspace}/coveragestores/{store_name}/coverages/{layer_name}.json"
            
            coverage_data = {
                "coverage": {
                    "srs": "EPSG:32645",
                    "nativeCRS": "EPSG:32645",
                    "projectionPolicy": "REPROJECT_TO_DECLARED",
                    "requestSRS": {
                        "string": ["EPSG:32645", "EPSG:3857", "EPSG:4326"]
                    },
                    "responseSRS": {
                        "string": ["EPSG:32645", "EPSG:3857", "EPSG:4326"]
                    }
                }
            }
            
            update_resp = requests.put(
                coverage_url,
                json=coverage_data,
                headers={"Content-type": "application/json"},
                auth=self.auth
            )
            
            if update_resp.status_code == 200:
                print(f"SUCCESS: Layer '{self.workspace}:{layer_name}' configured with EPSG:32645")
                if self.upload_style():
                    style_url = f"{self.gs_url}/layers/{self.workspace}:{layer_name}.json"
                    style_data = {
                        "layer": {
                            "defaultStyle": {
                                "name": f"{self.workspace}:flood_depth_style"
                            }
                        }
                    }
                    
                    style_resp = requests.put(
                        style_url,
                        json=style_data,
                        headers={"Content-type": "application/json"},
                        auth=self.auth
                    )
                    
                    if style_resp.status_code == 200:
                        print(f"Style applied to layer '{layer_name}'")
                    else:
                        print(f"Warning: Failed to apply style: {style_resp.status_code}")
            else:
                print(f"WARNING: SRS update responded with {update_resp.status_code}: {update_resp.text}")
        else:
            print(f"ERROR: GeoServer responded with {resp.status_code}: {resp.text}")

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Post-process ANUGA output and deploy to GeoServer")
    parser.add_argument("run_id", nargs="?", help="Name of the .sww file to process (without extension)")
    parser.add_argument("--timeseries", action="store_true", help="Generate and deploy time series layer")
    
    args = parser.parse_args()
    
    current_dir = os.path.dirname(os.path.abspath(__file__))
    settings = os.path.join(current_dir, "settings.toml")
    
    bridge = AnugaGeoserverBridge(settings, current_dir)
    
    # Determine if we should generate timeseries
    generate_ts = args.timeseries or bridge.cfg.postprocessing.generate_timeseries
    
    if args.run_id:
        bridge.run_post_processing(target_sww_name=args.run_id, generate_timeseries=generate_ts)
    else:
        bridge.run_post_processing(generate_timeseries=generate_ts)