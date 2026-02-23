import os
import json
import datetime
from dataclasses import asdict
from config import Config

def log_run_metadata(cfg: Config, run_id: str, elapsed: float):

    log_dir = cfg.paths.output_dir
    history_file = os.path.join(log_dir, "simulation_history.jsonl")
    
    parts = run_id.split('_')
    timestamp_str = "_".join(parts[-2:]) if len(parts) >= 2 else "unknown"
    
    entry = {
        "timestamp": timestamp_str,
        "run_id": run_id,
        "parameters": asdict(cfg),
        "environment": {
            "hpc": "Param Shavak",
            "os": "BOSS-OS",
            "status": "Completed"
        },
        "total_time": f"{elapsed/60:.1f} min"
    }

    try:
        with open(history_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
        
        summary_path = os.path.join(log_dir, f"{run_id}_meta.json")
        with open(summary_path, "w") as f:
            json.dump(entry, f, indent=4)
            
        print(f"Metadata logged to: {history_file}")
    except Exception as e:
        print(f"Warning: Could not write metadata: {e}")