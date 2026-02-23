# Installation Guide

## Purpose

This document explains how to install and verify the full ANUGA simulation stack.

This guide is intended for:
- HPC Administrators
- DevOps Engineers
- Infra Setup Engineers

If you only want to run simulations → See RUNNING.md  
If you only want to view dashboard → See USER_GUIDE.md  

---

## 1. Supported Systems

| Environment | Examples | Notes |
|---|---|---|
| HPC cluster | Param Rudra, Param Shavak, any PBS/SLURM cluster | ANUGA + MPI only, no GeoServer/Node/dashboard |
| Desktop Linux | Ubuntu 20.04+, Debian 11+, AlmaLinux 8+, RHEL 8+, BOSS OS | Full stack including GeoServer and dashboard |

Hardware:
- Multi-core CPU recommended
- MPI cluster support optional but preferred

---

## 2. Pre-Installation Requirements

### Desktop Linux
Conda conflicts with system MPI and NetCDF libraries. Run:
```bash
conda deactivate
```
Repeat until fully out of conda.

### HPC Clusters
Conda is required on HPC (used instead of system package manager). Ensure conda/miniconda is available and your target conda environment exists before running setup.

---

## 3. Step 0 — Get The Base Repository (FIRST TIME ONLY)
```bash
git clone https://github.com/anup619/Param-Shavak-Anuga

cd Param-Shavak-Anuga
git lfs pull
```
Notes:
- `git lfs pull` required only first clone OR if large files missing
- All installation commands assume you are in repo root

---

## 4. Air-Gapped / Offline HPC Preparation

If system has no internet access:

Place these inside:
```bash
opensource_tools/
```

Required archives:
- geoserver-2.28.x-bin.zip
- node-vXX-linux-x64.tar.xz

Installer will auto-detect and extract if present.

---

## 5. MPI Environment Note

### HPC Clusters
Load the appropriate MPI module before running setup. Example for Param Rudra:
```bash
module load openmpi-4.1.6
```
Find available MPI modules with:
```bash
module avail 2>&1 | grep -i mpi
```

### Desktop Linux
MPI is installed automatically via the package manager (apt/dnf). No manual step needed.

---

## 6. Full Installation (Automated)

The setup script auto-detects your environment and takes the appropriate path.

### Desktop Linux (Ubuntu / Debian / AlmaLinux / RHEL)
```bash
make setup
```

### HPC Clusters (Param Rudra, Param Shavak, etc.)
```bash
module load openmpi-4.1.6
export GEOTIFF_CSV=""
CONDA_ENV_NAME=anuga-env make setup
```

To force HPC mode explicitly:
```bash
FORCE_HPC=1 make setup
```


---

## What `make setup` Does Internally

### System Layer
Installs:
- GCC / Build tools
- Python dev stack
- NetCDF headers
- OpenMPI
- Java (for GeoServer)

---

### Python Layer
Installs:
- numpy, scipy, matplotlib
- netcdf4
- meson build tools
- ANUGA dependencies
- mpi4py compiled using system MPI

---

### ANUGA Layer
CMake:
- Clones anuga_core
- Installs locally into user Python site packages
- Generates MPI environment script

---

### Tool Layer (Desktop Linux Only)
If archives exist in opensource_tools/:
- Extract GeoServer locally
- Extract Node locally
- Build anuga-viewer if dependencies exist

On HPC, this layer is skipped entirely. GeoServer, Node, and the viewer are not installed.

---

## 7. Post Installation Verification

### Verify ANUGA + MPI
```bash
cd build
make test_anuga
```

Expected:
- mpi4py imports successfully
- ANUGA imports successfully
- MPI compiler detected

---

### Verify Tools Environment
```bash
source build/setup_tools_env.sh
make test_tools
```

Checks:
- Node path
- GeoServer presence
- Viewer path (if built)

---

## 8. Environment Scripts (IMPORTANT)

### Simulation Environment
Before running simulations:

```bash
source build/setup_mpi_env.sh
```

---

### Tools Environment
Before running GeoServer / Node / Viewer:

```bash
source build/setup_tools_env.sh
```
---

## 9. Directory Layout After Install
```plaintext
├── build/
|   ├── setup_mpi_env.sh
|   ├── setup_tools_env.sh
|   ├── geoserver_start.sh
|   └── geoserver_stop.sh
├── anuga_core/
├── opensource_tools/
└── mahanadi_test_case/
```
---

## 10. Common Installation Issues

### MPI Not Found
Desktop: check OpenMPI install via apt/dnf.
HPC: load the MPI module manually before setup:
```bash
module avail 2>&1 | grep -i mpi
module load <mpi_module>
```

---

### mpi4py Build Fails
Usually MPI compiler not visible.

Fix:
```bash
export MPICC=$(which mpicc)
```

---
### GeoServer Not Starting
GeoServer is only available on desktop Linux. It is not installed or started on HPC clusters.
On desktop, check Java:
```bash
java -version
```

### GEOTIFF_CSV Error on HPC
If conda env activation crashes with an unbound variable error, run:
```bash
export GEOTIFF_CSV=""
```
Then rerun setup.

---

## 11. Clean Reinstall

Remove build artifacts:
```bash
make clean
```

Full clean:
```bash
make clean-all
```

Then reinstall:
```bash
make setup
```
---

## Next Step

Once installation is verified → Go to:
RUNNING.md