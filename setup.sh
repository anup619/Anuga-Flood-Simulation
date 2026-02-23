#!/bin/bash
# =============================================================================
# ANUGA Unified Setup Script
# Supports:
#   - Ubuntu / Debian          (apt, with sudo)
#   - Rocky / AlmaLinux / RHEL (dnf, with sudo)
#   - HPC clusters             (module system + conda, NO sudo required)
#
# HPC mode is auto-detected when:
#   - 'module' command is present AND sudo/package-manager doesn't work
# Override: FORCE_HPC=1 or FORCE_HPC=0
# =============================================================================
set -euo pipefail

echo ""
echo "=== ANUGA Setup (Unified: Debian / Rocky / HPC) ==="
echo ""

# -----------------------------
# Paths
# -----------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANUGA_DIR="${ROOT_DIR}/anuga_core"
TOOLS_DIR="${ROOT_DIR}/opensource_tools"
BUILD_DIR="${ROOT_DIR}/build"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-anuga_env}"

# Optional desktop tools (skipped on HPC)
GEOSERVER_ZIP="${TOOLS_DIR}/geoserver-2.28.2-bin.zip"
GEOSERVER_DIR="${TOOLS_DIR}/geoserver-2.28.2-bin"
NODE_TAR="${TOOLS_DIR}/node-v24.13.0-linux-x64.tar.xz"
NODE_DIR="${TOOLS_DIR}/node-v24.13.0-linux-x64"
VIEWER_DIR="${TOOLS_DIR}/anuga-viewer"
INSTALL_ANUGA_VIEWER="${INSTALL_ANUGA_VIEWER:-auto}"

# =============================================================================
# STEP 0: Detect environment
# =============================================================================
echo "[0/7] Detecting environment..."

HPC_MODE=false
PKG_MGR=""
SUDO=""

# Detect sudo
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
fi

# Detect HPC (module system present)
HPC_DETECTED=false
if command -v module >/dev/null 2>&1; then
  HPC_DETECTED=true
fi

# Check if package manager actually works (can we install without errors?)
PKG_MGR_WORKS=false
if [ -n "$PKG_MGR" ] && [ -n "$SUDO" ]; then
  if [ "$PKG_MGR" = "apt" ] && $SUDO apt-get -s install curl >/dev/null 2>&1; then
    PKG_MGR_WORKS=true
  elif [ "$PKG_MGR" = "dnf" ] && $SUDO dnf -q --assumeno install curl >/dev/null 2>&1; then
    PKG_MGR_WORKS=true
  fi
fi

# HPC mode = module system present AND package manager doesn't work with sudo
if $HPC_DETECTED && ! $PKG_MGR_WORKS; then
  HPC_MODE=true
fi

# Manual overrides
[ "${FORCE_HPC:-}" = "1" ] && HPC_MODE=true
[ "${FORCE_HPC:-}" = "0" ] && HPC_MODE=false

if $HPC_MODE; then
  echo "  Mode     : HPC (module + conda, no sudo)"
else
  echo "  Mode     : Desktop Linux ($PKG_MGR + sudo)"
fi

# =============================================================================
# ██████╗ ███████╗███████╗██╗  ██╗████████╗ ██████╗ ██████╗
# ██╔══██╗██╔════╝██╔════╝██║ ██╔╝╚══██╔══╝██╔═══██╗██╔══██╗
# ██║  ██║█████╗  ███████╗█████╔╝    ██║   ██║   ██║██████╔╝
# ██║  ██║██╔══╝  ╚════██║██╔═██╗    ██║   ██║   ██║██╔═══╝
# ██████╔╝███████╗███████║██║  ██╗   ██║   ╚██████╔╝██║
# ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  (apt/dnf)
# =============================================================================
if ! $HPC_MODE; then

  # ---------------------------------------------------------------------------
  # 1: System packages
  # ---------------------------------------------------------------------------
  echo ""
  echo "[1/7] Installing system dependencies ($PKG_MGR)..."

  if [ "$PKG_MGR" = "apt" ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y \
      gcc g++ make cmake git ninja-build \
      python3 python3-pip python3-dev \
      pkg-config \
      libnetcdf-dev \
      libopenmpi-dev openmpi-bin \
      unzip tar curl \
      default-jre

  elif [ "$PKG_MGR" = "dnf" ]; then
    $SUDO dnf -y install \
      gcc gcc-c++ make cmake git ninja-build \
      python3 python3-pip python3-devel \
      pkgconf-pkg-config \
      netcdf-devel \
      openmpi openmpi-devel \
      unzip tar curl \
      java-17-openjdk || true
    # Fallback if java-17 not available
    command -v java >/dev/null 2>&1 || $SUDO dnf -y install java-latest-openjdk || true

  else
    echo "ERROR: No supported package manager (apt/dnf) found."
    echo "       Install gcc, cmake, git, python3, libnetcdf-dev, openmpi manually."
    exit 1
  fi

  # ---------------------------------------------------------------------------
  # 2: Java check (desktop only — needed for GeoServer)
  # ---------------------------------------------------------------------------
  echo ""
  echo "[2/7] Checking Java..."
  command -v java >/dev/null 2>&1 || {
    echo "ERROR: Java not found after install."
    echo "       GeoServer requires Java (OpenJDK). Install manually."
    exit 1
  }
  echo "  Java OK: $(java -version 2>&1 | head -n 1)"

  # ---------------------------------------------------------------------------
  # 3: MPI path setup
  # ---------------------------------------------------------------------------
  echo ""
  echo "[3/7] Setting up MPI..."
  if ! command -v mpicc >/dev/null 2>&1; then
    for d in \
      /usr/lib64/openmpi/bin \
      /usr/lib/openmpi/bin \
      /usr/lib/x86_64-linux-gnu/openmpi/bin \
      /usr/lib/aarch64-linux-gnu/openmpi/bin \
      /opt/openmpi/bin /opt/ompi/bin \
      /usr/local/openmpi/bin; do
      if [ -x "$d/mpicc" ]; then
        export PATH="$d:$PATH"
        base="$(dirname "$d")"
        [ -d "$base/lib64" ] && export LD_LIBRARY_PATH="$base/lib64:${LD_LIBRARY_PATH:-}"
        [ -d "$base/lib" ]   && export LD_LIBRARY_PATH="$base/lib:${LD_LIBRARY_PATH:-}"
        break
      fi
    done
  fi
  command -v mpicc >/dev/null 2>&1 || {
    echo "ERROR: mpicc not found. Check OpenMPI installation."
    exit 1
  }
  echo "  MPI compiler: $(command -v mpicc)"
  mpicc --version 2>&1 | head -n 1 || true

  # ---------------------------------------------------------------------------
  # 4: Python dependencies
  # ---------------------------------------------------------------------------
  echo ""
  echo "[4/7] Installing Python dependencies..."
  PY=python3
  PIP_FLAGS=""
  $PY -m pip install --help 2>&1 | grep -q "break-system-packages" && PIP_FLAGS="--break-system-packages"

  $PY -m pip install --upgrade pip setuptools wheel $PIP_FLAGS
  $PY -m pip install --upgrade cython meson meson-python ninja $PIP_FLAGS
  $PY -m pip install --upgrade numpy scipy matplotlib tomli $PIP_FLAGS
  $PY -m pip install --upgrade netcdf4 pyshp $PIP_FLAGS
  $PY -m pip install --upgrade dill pymetis pytools polyline triangle $PIP_FLAGS

  echo "  Building mpi4py from source..."
  $PY -m pip uninstall -y mpi4py >/dev/null 2>&1 || true
  MPICC="$(command -v mpicc)" $PY -m pip install --no-cache-dir --no-binary mpi4py mpi4py $PIP_FLAGS
  $PY -c "import mpi4py; print('  ✓ mpi4py:', mpi4py.__version__)"

  # ---------------------------------------------------------------------------
  # 5: GeoServer + Node + anuga-viewer (desktop only)
  # ---------------------------------------------------------------------------
  echo ""
  echo "[5/7] Setting up optional tools (GeoServer / Node / anuga-viewer)..."
  mkdir -p "$TOOLS_DIR"

  if [ -f "$GEOSERVER_ZIP" ]; then
    [ ! -d "$GEOSERVER_DIR" ] && unzip -q "$GEOSERVER_ZIP" -d "$GEOSERVER_DIR" && echo "  GeoServer unpacked." || echo "  GeoServer already unpacked."
  else
    echo "  WARNING: GeoServer zip not found at $GEOSERVER_ZIP (skipping)"
  fi

  if [ -f "$NODE_TAR" ]; then
    [ ! -d "$NODE_DIR" ] && tar -xf "$NODE_TAR" -C "$TOOLS_DIR" && echo "  Node extracted." || echo "  Node already extracted."
  else
    echo "  WARNING: Node tarball not found at $NODE_TAR (skipping)"
  fi

  build_viewer=false
  [ "$INSTALL_ANUGA_VIEWER" = "1" ] && build_viewer=true
  [ "$INSTALL_ANUGA_VIEWER" = "auto" ] && build_viewer=true

  if $build_viewer; then
    if [ "$PKG_MGR" = "apt" ]; then
      $SUDO apt-get install -y libgdal-dev libcppunit-dev libopenscenegraph-dev 2>/dev/null || build_viewer=false
    elif [ "$PKG_MGR" = "dnf" ]; then
      if dnf info gdal-devel >/dev/null 2>&1; then
        $SUDO dnf -y install OpenSceneGraph-devel cppunit-devel gdal-devel 2>/dev/null || build_viewer=false
      else
        echo "  WARNING: gdal-devel unavailable — skipping anuga-viewer."
        build_viewer=false
      fi
    fi
  fi

  if $build_viewer; then
    [ ! -d "$VIEWER_DIR" ] && git clone https://github.com/GeoscienceAustralia/anuga-viewer.git "$VIEWER_DIR"
    pushd "$VIEWER_DIR" >/dev/null
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    mkdir -p "$VIEWER_DIR/local"
    make install PREFIX="$VIEWER_DIR/local" 2>/dev/null || make install || true
    popd >/dev/null
  else
    echo "  anuga-viewer: skipped."
  fi

  # ---------------------------------------------------------------------------
  # 6: Clone + build ANUGA via CMake
  # ---------------------------------------------------------------------------
  echo ""
  echo "[6/7] Building ANUGA via CMake..."
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"
  cmake .. \
    -DMPI_C_COMPILER="$(command -v mpicc)" \
    -DMPI_CXX_COMPILER="$(command -v mpicxx 2>/dev/null || command -v mpic++ 2>/dev/null || echo '')"
  make setup

  # ---------------------------------------------------------------------------
  # 7: Generate env scripts (desktop)
  # ---------------------------------------------------------------------------
  echo ""
  echo "[7/7] Writing environment scripts..."

  cat > "${BUILD_DIR}/setup_tools_env.sh" << EOF
#!/bin/bash
# Source this before using Node/GeoServer/anuga-viewer
export PATH="\$HOME/.local/bin:\$PATH"
[ -d "${NODE_DIR}" ]             && export NODE_HOME="${NODE_DIR}" && export PATH="\$NODE_HOME/bin:\$PATH"
[ -d "${GEOSERVER_DIR}" ]        && export GEOSERVER_HOME="${GEOSERVER_DIR}"
[ -d "${VIEWER_DIR}/local/bin" ] && export PATH="\$PATH:${VIEWER_DIR}/local/bin"
[ -d "${VIEWER_DIR}/bin" ]       && export PATH="\$PATH:${VIEWER_DIR}/bin"
echo "Tools environment configured."
echo "NODE_HOME=\${NODE_HOME:-not set}"
echo "GEOSERVER_HOME=\${GEOSERVER_HOME:-not set}"
EOF
  chmod +x "${BUILD_DIR}/setup_tools_env.sh"

  cat > "${BUILD_DIR}/geoserver_start.sh" << EOF
#!/bin/bash
source "\$(dirname "\$0")/setup_tools_env.sh" >/dev/null 2>&1 || true
[ -z "\${GEOSERVER_HOME:-}" ] && echo "ERROR: GEOSERVER_HOME not set." && exit 1
nohup bash "\$GEOSERVER_HOME/bin/startup.sh" > "\$GEOSERVER_HOME/../geoserver.out" 2>&1 &
echo "GeoServer starting. Log: \$GEOSERVER_HOME/../geoserver.out"
EOF
  chmod +x "${BUILD_DIR}/geoserver_start.sh"

  cat > "${BUILD_DIR}/geoserver_stop.sh" << EOF
#!/bin/bash
source "\$(dirname "\$0")/setup_tools_env.sh" >/dev/null 2>&1 || true
[ -z "\${GEOSERVER_HOME:-}" ] && echo "ERROR: GEOSERVER_HOME not set." && exit 1
bash "\$GEOSERVER_HOME/bin/shutdown.sh" || true
echo "GeoServer stop requested."
EOF
  chmod +x "${BUILD_DIR}/geoserver_stop.sh"

  echo ""
  echo "================================================================"
  echo "  ANUGA Desktop Setup Complete!"
  echo "================================================================"
  echo "  Test ANUGA:        cd build && make test_anuga"
  echo "  Tools env:         source build/setup_tools_env.sh"
  echo "  Start GeoServer:   bash build/geoserver_start.sh"
  echo "  Stop GeoServer:    bash build/geoserver_stop.sh"
  echo "  Run with MPI:      source build/setup_mpi_env.sh"
  echo "                     mpirun -np 4 python3 simulation.py"
  echo "================================================================"
  exit 0
fi

# =============================================================================
# ██╗  ██╗██████╗  ██████╗
# ██║  ██║██╔══██╗██╔════╝
# ███████║██████╔╝██║
# ██╔══██║██╔═══╝ ██║
# ██║  ██║██║     ╚██████╗
# ╚═╝  ╚═╝╚═╝      ╚═════╝  (module + conda)
# =============================================================================

# ---------------------------------------------------------------------------
# 1: Load MPI module
# ---------------------------------------------------------------------------
echo ""
echo "[1/7] Loading MPI module..."

MPI_LOADED=false
command -v mpicc >/dev/null 2>&1 && MPI_LOADED=true && echo "  mpicc already in PATH: $(command -v mpicc)"

if ! $MPI_LOADED; then
  for mod in openmpi-4.1.6 compiler/openmpi/4.1.4 openmpi/4.1.4 apps/intel_mpi_2021.14 compiler/oneapi2024/mpi/2021.11 mpich; do
    if module load "$mod" 2>/dev/null; then
      echo "  Loaded module: $mod"
      MPI_LOADED=true
      break
    fi
  done
fi

# Fallback: search common HPC paths
if ! command -v mpicc >/dev/null 2>&1; then
  for d in /usr/lib64/openmpi/bin /usr/lib/openmpi/bin /opt/openmpi/bin /home/apps/openmpi/bin; do
    if [ -x "$d/mpicc" ]; then
      export PATH="$d:$PATH"
      base="$(dirname "$d")"
      [ -d "$base/lib64" ] && export LD_LIBRARY_PATH="$base/lib64:${LD_LIBRARY_PATH:-}"
      [ -d "$base/lib" ]   && export LD_LIBRARY_PATH="$base/lib:${LD_LIBRARY_PATH:-}"
      MPI_LOADED=true; break
    fi
  done
fi

command -v mpicc >/dev/null 2>&1 || {
  echo "ERROR: mpicc not found. Load an MPI module manually first:"
  echo "  module avail 2>&1 | grep -i mpi"
  echo "  module load <mpi_module>"
  echo "Then rerun: bash setup.sh"
  exit 1
}
echo "  MPI compiler: $(command -v mpicc)"
mpicc --version 2>&1 | head -n 1 || true

# ---------------------------------------------------------------------------
# 2: Conda environment
# ---------------------------------------------------------------------------
echo ""
echo "[2/7] Setting up conda environment: $CONDA_ENV_NAME"

command -v conda >/dev/null 2>&1 || {
  echo "ERROR: conda not found."
  echo "  Load a conda/miniconda module, or add miniconda to PATH."
  exit 1
}

source "$(conda info --base)/etc/profile.d/conda.sh"

if conda env list 2>/dev/null | grep -qE "^${CONDA_ENV_NAME}[[:space:]]"; then
  echo "  Conda env '$CONDA_ENV_NAME' already exists."
else
  echo "  Creating conda env '$CONDA_ENV_NAME' (Python 3.11)..."
  conda create -y -n "$CONDA_ENV_NAME" python=3.11
fi

conda activate "$CONDA_ENV_NAME"
PY="$(which python)"
echo "  Python: $PY ($(python --version))"

# ---------------------------------------------------------------------------
# 3: Python dependencies
# ---------------------------------------------------------------------------
echo ""
echo "[3/7] Installing Python dependencies..."

echo "  conda-forge packages..."
conda install -y -c conda-forge \
  numpy scipy matplotlib \
  netcdf4 \
  cython meson meson-python ninja \
  pip setuptools wheel \
  tomli pyshp dill triangle

echo "  pip packages..."
pip install --no-cache-dir pymetis pytools polyline

# ---------------------------------------------------------------------------
# 4: mpi4py from source
# ---------------------------------------------------------------------------
echo ""
echo "[4/7] Building mpi4py from source against loaded MPI..."

pip uninstall -y mpi4py 2>/dev/null || true
conda remove -y mpi4py 2>/dev/null || true

echo "  Using MPICC: $(command -v mpicc)"
MPICC="$(command -v mpicc)" pip install --no-cache-dir --no-binary mpi4py mpi4py
python -c "import mpi4py; print('  ✓ mpi4py:', mpi4py.__version__)"

# ---------------------------------------------------------------------------
# 5: Skip desktop tools on HPC
# ---------------------------------------------------------------------------
echo ""
echo "[5/7] Skipping GeoServer/Node/Java (HPC mode — not applicable on login nodes)"

# ---------------------------------------------------------------------------
# 6: Clone + install ANUGA
# ---------------------------------------------------------------------------
echo ""
echo "[6/7] Setting up ANUGA..."

if [ ! -d "$ANUGA_DIR" ]; then
  echo "  Cloning ANUGA (tag 3.2.0)..."
  git clone https://github.com/GeoscienceAustralia/anuga_core.git "$ANUGA_DIR"
  cd "$ANUGA_DIR"
  git checkout 3.2.0 || true
else
  echo "  ANUGA source already present at $ANUGA_DIR"
fi

cd "$ANUGA_DIR"
echo "  Installing ANUGA (editable)..."
pip install -e . --no-build-isolation --no-deps
python -c "import anuga; print('  ✓ ANUGA:', anuga.__version__)"

# ---------------------------------------------------------------------------
# 7: Write env + job scripts
# ---------------------------------------------------------------------------
echo ""
echo "[7/7] Writing environment and job scripts..."

mkdir -p "$BUILD_DIR"

MPICC_BIN="$(command -v mpicc)"
MPI_BIN_DIR="$(dirname "$MPICC_BIN")"
MPI_BASE_DIR="$(dirname "$MPI_BIN_DIR")"
CONDA_BASE_DIR="$(conda info --base)"

cat > "${BUILD_DIR}/setup_mpi_env.sh" << ENVEOF
#!/bin/bash
# Source this before running ANUGA with MPI
# Usage: source build/setup_mpi_env.sh

# Activate conda env
source "${CONDA_BASE_DIR}/etc/profile.d/conda.sh"
conda activate ${CONDA_ENV_NAME} 2>/dev/null || true

# Load MPI module if not already in PATH
if ! command -v mpicc >/dev/null 2>&1; then
  for mod in openmpi-4.1.6 compiler/openmpi/4.1.4 openmpi/4.1.4 apps/intel_mpi_2021.14 compiler/oneapi2024/mpi/2021.11 mpich; do
    module load "\$mod" 2>/dev/null && break || true
  done
fi

# Fallback hardcoded path from setup time
if ! command -v mpicc >/dev/null 2>&1; then
  export PATH="${MPI_BIN_DIR}:\$PATH"
  [ -d "${MPI_BASE_DIR}/lib64" ] && export LD_LIBRARY_PATH="${MPI_BASE_DIR}/lib64:\${LD_LIBRARY_PATH:-}"
  [ -d "${MPI_BASE_DIR}/lib" ]   && export LD_LIBRARY_PATH="${MPI_BASE_DIR}/lib:\${LD_LIBRARY_PATH:-}"
fi

echo "ANUGA environment ready."
echo "  Python : \$(which python)"
echo "  mpicc  : \$(command -v mpicc 2>/dev/null || echo 'not found')"
ENVEOF
chmod +x "${BUILD_DIR}/setup_mpi_env.sh"

cat > "${BUILD_DIR}/test_anuga.sh" << TESTEOF
#!/bin/bash
set -euo pipefail
source "\$(dirname "\$0")/setup_mpi_env.sh"
echo ""
echo "=== Testing ANUGA ==="
python -c "import mpi4py; print('  ✓ mpi4py:', mpi4py.__version__)"
python -c "import anuga; print('  ✓ ANUGA:', anuga.__version__)"
python -c "import anuga; from anuga import myid, numprocs; print('  ✓ myid:', myid, '| numprocs:', numprocs)"
echo "=== All tests passed ==="
echo ""
echo "Run with MPI:"
echo "  source build/setup_mpi_env.sh"
echo "  mpirun -np 4 python your_simulation.py"
TESTEOF
chmod +x "${BUILD_DIR}/test_anuga.sh"

# PBS/SLURM template
cat > "${ROOT_DIR}/run_anuga_job.sh" << JOBEOF
#!/bin/bash
#PBS -N anuga_job
#PBS -l select=1:ncpus=8:mpiprocs=8
#PBS -l walltime=02:00:00
#PBS -q workq

# --- SLURM (comment PBS lines above, uncomment below) ---
## SBATCH --job-name=anuga_job
## SBATCH --ntasks=8
## SBATCH --time=02:00:00

cd \${PBS_O_WORKDIR:-\${SLURM_SUBMIT_DIR:-.}}

source "\$(dirname "\$0")/build/setup_mpi_env.sh"

mpirun -np 8 python your_simulation.py
JOBEOF
chmod +x "${ROOT_DIR}/run_anuga_job.sh"

echo ""
echo "================================================================"
echo "  ANUGA HPC Setup Complete!"
echo "================================================================"
echo "  Conda env : $CONDA_ENV_NAME"
echo "  Python    : $PY"
echo "  MPI       : $(command -v mpicc)"
echo "  ANUGA dir : $ANUGA_DIR"
echo ""
echo "  Test:        bash build/test_anuga.sh"
echo "  Load env:    source build/setup_mpi_env.sh"
echo "  Submit job:  qsub run_anuga_job.sh   (PBS)"
echo "               sbatch run_anuga_job.sh  (SLURM)"
echo "================================================================"