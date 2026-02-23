# ANUGA | Flood Simulation System

## Overview

This setup of ANUGA is a **plug-and-play flood simulation pipeline** designed to run on HPC clusters or Linux workstations.

It packages the full workflow into one reproducible environment:

- ANUGA flood simulation engine (MPI parallel capable)
- Automated post-processing pipeline
- GeoServer map publishing (desktop/workstation only)
- React dashboard visualization (desktop/workstation only)
- Optional 3D ANUGA viewer (desktop/workstation only)

The goal is simple:
Run one install → run simulation → visualize results.

## Supported Environments

| Environment | Example Systems | What Works |
|---|---|---|
| HPC cluster | Param Rudra, Param Shavak, any SLURM/PBS cluster | ANUGA simulation + MPI only |
| Desktop Linux | Ubuntu 20.04+, Debian 11+, AlmaLinux 8+, RHEL 8+ | Full stack including GeoServer + dashboard |

On HPC systems, GeoServer, Node, and the React dashboard are not installed or started. Simulation outputs (.sww files) should be copied to a desktop system for visualization.

---

## Who This Repository Is For

### HPC / System Administrators
Responsible for installing dependencies and setting up environment.

➡ Read: `INSTALL.md`

---

### Flood Modelers / Researchers
Responsible for configuring simulations and generating outputs.

➡ Read: `RUNNING.md`

---

### Stakeholders / Dashboard Users
Responsible only for viewing flood outputs on dashboard.
Note: Dashboard is only available on desktop Linux systems, not on HPC clusters.

➡ Read: `USER_GUIDE.md`

---

## First Time Setup (Golden Path)

### Step 0 — Clone Repository

```bash
git clone https://github.com/anup619/Param-Shavak-Anuga

cd Param-Shavak-Anuga
git lfs pull
```

Run `git lfs pull` **only first time** or if large files are missing.

All commands in docs assume you are inside repo root directory.

---

### Step 1 — Install

The setup script auto-detects your environment and installs accordingly.

**On HPC (Param Rudra, Param Shavak, any SLURM/PBS cluster) — load MPI module first:**
```bash
module load openmpi-4.1.6
export GEOTIFF_CSV=""
CONDA_ENV_NAME=anuga-env make setup
```

**On desktop Linux (Ubuntu, Debian, AlmaLinux, etc.):**
```bash
make setup
```

See INSTALL.md for full details on what gets installed per environment.

---

### Step 2 — Run Simulation

```bash
source build/setup_mpi_env.sh
mpirun -np 16 python3 mahanadi_test_case/simulate.py
```

On HPC, submit via job scheduler instead — see RUNNING.md.

---

### Step 3 — Start Visualization (Desktop Linux Only)

Not applicable on HPC clusters. Copy `.sww` output files to a desktop system to visualize.

```bash
make geoserver-start
source build/setup_tools_env.sh
cd anuga-viewer-app
npm run dev
```
Dashboard runs at:
`http://localhost:5173`

---

## How The Pipeline Works
```
Install → Configure → Simulate → Postprocess → Deploy → Visualize
```

Detailed behavior:
- `setup.sh` installs system + python dependencies
- CMake installs ANUGA locally
- Simulation produces `.sww`
- bridge.py converts outputs + deploys to GeoServer
- React dashboard reads WMS layers

---

## Repository Structure
```plaintext
Param-Shavak-Anuga/
│
├ INSTALL.md
├ RUNNING.md
├ USER_GUIDE.md
│
├ build/
│ ├ setup_mpi_env.sh
│ ├ setup_tools_env.sh
│ ├ geoserver_start.sh
│ └ geoserver_stop.sh
│
├ opensource_tools/
│ ├ geoserver-.zip
│ └ node-.tar.xz
│
├ anuga_core/
│
└ mahanadi_test_case/
```

---

## When To Read Which File

| Situation | Read |
|---|---|
| First time installation | INSTALL.md |
| Running flood simulation | RUNNING.md |
| Viewing dashboard results | USER_GUIDE.md |

---

## Plug-and-Play Philosophy

This system is designed so that:

Admin installs once  
Modelers run simulations  
Stakeholders view results  

No manual dependency chasing.

---

## Support / Contact

Anup Bagde  
Project Engineer - HPC ESEG Group  
CDAC Pune  
Email: anupb@cdac.in

---