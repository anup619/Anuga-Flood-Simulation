import os

from settings_loader import load_config
from simulation import run_simulation
from bridge import AnugaGeoserverBridge
from logger import log_run_metadata
import time

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    settings_path = os.path.join(script_dir, "settings.toml")

    cfg = load_config(settings_path, script_dir)
    start = time.time()
    run_simulation(cfg)
    
    try:
        from anuga import myid
    except ImportError:
        myid = 0

    if myid == 0:
        print("\n" + "="*70)
        print("SIMULATION FINISHED...")
        print("="*70)
        run_id = cfg.paths.output_file
        try:
            if cfg.postprocessing.postprocess:
                bridge = AnugaGeoserverBridge(settings_path, script_dir)
                print("\n" + "="*70)
                print("STARTING AUTOMATED DEPLOYMENT...")
                print("="*70)
                bridge.run_post_processing(
                    run_id=cfg.paths.output_file,
                    generate_timeseries=cfg.postprocessing.generate_timeseries
                )
                print("\nDEPLOYMENT COMPLETE. Check your React App.")
        except Exception as e:
            print(f"\nDeployment failed: {e}")
            
        elapsed = time.time() - start  
        log_run_metadata(cfg, run_id, elapsed) 
        print("Process finished.") 
    

if __name__ == "__main__":
    main()