#!/bin/bash
# =============================================================================
# Param Shavak ANUGA — Smart Setup Script
# Supports: Ubuntu/Debian, Rocky/AlmaLinux/RHEL, HPC (no sudo), Param Shavak
#
# Self-healing: detects environment first, acts second.
# Only hard-fails when there is truly no path forward.
# =============================================================================
set -euo pipefail

# =============================================================================
# SECTION 0 — PREFLIGHT / ENVIRONMENT DETECTION
# Everything is detected here. Nothing is installed yet.
# =============================================================================

echo ""
echo "=== ANUGA Setup (Unified: Debian / Rocky / HPC) ==="
echo ""
echo "[0/7] Detecting environment..."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${ROOT_DIR}/opensource_tools"
GEOSERVER_ZIP="${TOOLS_DIR}/geoserver-2.28.2-bin.zip"
GEOSERVER_DIR="${TOOLS_DIR}/geoserver-2.28.2-bin"
NODE_TAR="${TOOLS_DIR}/node-v24.13.0-linux-x64.tar.xz"
NODE_DIR="${TOOLS_DIR}/node-v24.13.0-linux-x64"
VIEWER_DIR="${TOOLS_DIR}/anuga-viewer"
INSTALL_ANUGA_VIEWER="${INSTALL_ANUGA_VIEWER:-auto}"

# ── Sudo detection (actually test it, don't just check if it exists) ──────────
SUDO=""
SUDO_WORKS=false
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    SUDO="sudo"
    SUDO_WORKS=true
  fi
fi

# ── Package manager detection ─────────────────────────────────────────────────
PKG_MGR=""
if command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt"
fi

# ── Module system detection (HPC indicator) ──────────────────────────────────
HPC_DETECTED=false
if command -v module >/dev/null 2>&1; then
  # Only trust module system if it actually has something loaded
  if module avail 2>&1 | grep -qv "^$"; then
    HPC_DETECTED=true
  fi
fi

# ── Conda detection (actually verify it works, don't just check the command) ─
CONDA_OK=false
CONDA_CMD=""
if command -v conda >/dev/null 2>&1; then
  # Test if conda is functional (not a zombie shell function)
  if conda info --base >/dev/null 2>&1; then
    CONDA_BASE="$(conda info --base 2>/dev/null)"
    # Verify base is not broken (pointing to /usr is a known broken state)
    if [ -n "$CONDA_BASE" ] && [ "$CONDA_BASE" != "/usr" ] && [ -d "$CONDA_BASE/bin" ]; then
      CONDA_OK=true
      CONDA_CMD="conda"
    fi
  fi
fi

# ── Python detection: find the best python3 where pip points to same version ─
PY=""
PY_VERSION=""
for candidate in python3.11 python3.10 python3.9 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    _ver=$("$candidate" --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
    # Check if pip installed for this exact python points to same version
    _pip_ver=$("$candidate" -m pip --version 2>/dev/null | grep -oP "python \K[0-9]+\.[0-9]+" || echo "")
    if [ "$_ver" = "$_pip_ver" ] || [ -z "$_pip_ver" ]; then
      PY="$candidate"
      PY_VERSION="$_ver"
      break
    fi
  fi
done

# If no perfectly matched python found, fallback to python3.11 or python3
if [ -z "$PY" ]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PY="python3.11"
    PY_VERSION="3.11"
  elif command -v python3 >/dev/null 2>&1; then
    PY="python3"
    PY_VERSION="$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)"
  fi
fi

# ── pip flags ────────────────────────────────────────────────────────────────
PIP_FLAGS="--user"
if [ -n "$PY" ] && "$PY" -m pip install --help 2>&1 | grep -q "break-system-packages"; then
  PIP_FLAGS="--user --break-system-packages"
fi

# ── MPI detection: search common paths if not in PATH ────────────────────────
MPI_FOUND=false
MPI_BIN=""
if command -v mpicc >/dev/null 2>&1; then
  MPI_FOUND=true
  MPI_BIN="$(dirname "$(command -v mpicc)")"
else
  for d in \
    /usr/lib64/openmpi/bin \
    /usr/lib/openmpi/bin \
    /usr/lib/x86_64-linux-gnu/openmpi/bin \
    /usr/lib/aarch64-linux-gnu/openmpi/bin \
    /opt/openmpi/bin \
    /opt/ompi/bin \
    /usr/local/openmpi/bin \
    /usr/mpi/gcc/openmpi*/bin \
    /cm/shared/apps/openmpi/*/bin; do
    if [ -x "$d/mpicc" ]; then
      export PATH="$d:$PATH"
      base="$(dirname "$d")"
      [ -d "$base/lib64" ] && export LD_LIBRARY_PATH="$base/lib64:${LD_LIBRARY_PATH:-}"
      [ -d "$base/lib" ]   && export LD_LIBRARY_PATH="$base/lib:${LD_LIBRARY_PATH:-}"
      MPI_FOUND=true
      MPI_BIN="$d"
      break
    fi
  done
fi

# ── Decide operating mode ─────────────────────────────────────────────────────
# Priority: Desktop with sudo > HPC with conda > HPC pip-only > fail
MODE="unknown"
if $SUDO_WORKS && [ -n "$PKG_MGR" ]; then
  MODE="desktop"
elif $CONDA_OK; then
  MODE="hpc-conda"
elif [ -n "$PY" ] && $MPI_FOUND; then
  MODE="hpc-pip"
elif ! $MPI_FOUND && [ -n "$PKG_MGR" ] && ! $SUDO_WORKS; then
  MODE="needs-admin"
fi

# ── Print detection summary ───────────────────────────────────────────────────
echo "  ┌─────────────────────────────────────────┐"
echo "  │         Environment Detection            │"
echo "  ├─────────────────────────────────────────┤"
printf "  │  Mode       : %-26s│\n" "$MODE"
printf "  │  Python     : %-26s│\n" "${PY:-not found} (${PY_VERSION:-?})"
printf "  │  pip flags  : %-26s│\n" "${PIP_FLAGS}"
printf "  │  sudo works : %-26s│\n" "$SUDO_WORKS"
printf "  │  pkg manager: %-26s│\n" "${PKG_MGR:-none}"
printf "  │  MPI found  : %-26s│\n" "$MPI_FOUND (${MPI_BIN:-not in PATH})"
printf "  │  conda OK   : %-26s│\n" "$CONDA_OK"
printf "  │  HPC modules: %-26s│\n" "$HPC_DETECTED"
echo "  └─────────────────────────────────────────┘"
echo ""

# ── Hard fail if no viable path exists ───────────────────────────────────────
if [ "$MODE" = "unknown" ] || [ "$MODE" = "needs-admin" ]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                  SETUP CANNOT CONTINUE                      ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  if [ -z "$PY" ]; then
    echo "║  ✗ No Python 3 found.                                        ║"
    echo "║    Fix: ask admin to run:                                    ║"
    echo "║    sudo dnf install -y python3 python3-pip python3-devel     ║"
  fi
  if ! $MPI_FOUND; then
    echo "║  ✗ MPI (mpicc) not found anywhere on this system.            ║"
    echo "║    Fix: ask admin to run:                                    ║"
    echo "║    sudo dnf install -y openmpi openmpi-devel                 ║"
    echo "║    OR: module load <mpi_module>  (check: module avail)       ║"
  fi
  if ! $SUDO_WORKS && [ -z "$CONDA_CMD" ]; then
    echo "║  ✗ No sudo access and no working conda.                      ║"
    echo "║    Fix: ask admin to install system packages once, OR        ║"
    echo "║    install miniconda: https://docs.conda.io/en/latest/       ║"
  fi
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 1
fi

# =============================================================================
# SECTION 1 — SYSTEM PACKAGES (only if sudo works)
# =============================================================================
echo "[1/7] Installing system dependencies..."

if [ "$MODE" = "desktop" ]; then
  if [ "$PKG_MGR" = "dnf" ]; then
    $SUDO dnf -y install \
      gcc gcc-c++ make cmake git ninja-build \
      python3 python3-pip python3-devel \
      pkgconf-pkg-config \
      netcdf-devel \
      openmpi openmpi-devel \
      unzip tar curl \
      java-17-openjdk 2>/dev/null || \
    $SUDO dnf -y install java-latest-openjdk 2>/dev/null || true

  elif [ "$PKG_MGR" = "apt" ]; then
    $SUDO apt-get update -q
    $SUDO apt-get install -y \
      gcc g++ make cmake git ninja-build \
      python3 python3-pip python3-dev \
      pkg-config \
      libnetcdf-dev \
      libopenmpi-dev openmpi-bin \
      unzip tar curl \
      default-jre
  fi

  # Re-detect MPI after install (it may have just been installed)
  if ! $MPI_FOUND; then
    for d in \
      /usr/lib64/openmpi/bin \
      /usr/lib/openmpi/bin \
      /usr/lib/x86_64-linux-gnu/openmpi/bin; do
      if [ -x "$d/mpicc" ]; then
        export PATH="$d:$PATH"
        base="$(dirname "$d")"
        [ -d "$base/lib64" ] && export LD_LIBRARY_PATH="$base/lib64:${LD_LIBRARY_PATH:-}"
        [ -d "$base/lib" ]   && export LD_LIBRARY_PATH="$base/lib:${LD_LIBRARY_PATH:-}"
        MPI_FOUND=true
        MPI_BIN="$d"
        break
      fi
    done
  fi

else
  echo "  Skipping system package install (no sudo). Using existing system packages."
fi

# =============================================================================
# SECTION 2 — MPI VERIFICATION
# =============================================================================
echo "[2/7] Verifying MPI..."

if ! command -v mpicc >/dev/null 2>&1; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ✗ mpicc still not found after install attempt.              ║"
  echo "║    If on HPC, load your MPI module first:                    ║"
  echo "║      module avail 2>&1 | grep -i mpi                         ║"
  echo "║      module load <mpi_module>                                ║"
  echo "║    Then rerun: bash setup.sh                                 ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  exit 1
fi

echo "  MPI compiler: $(command -v mpicc)"
mpicc --version 2>&1 | head -n 1 || true

# =============================================================================
# SECTION 3 — JAVA VERIFICATION
# =============================================================================
echo "[3/7] Checking Java..."
if ! command -v java >/dev/null 2>&1; then
  echo "  WARNING: Java not found. GeoServer will not work."
  echo "  Fix: sudo dnf install -y java-17-openjdk"
  echo "  Continuing without Java (simulation will still work)."
else
  echo "  Java OK: $(java -version 2>&1 | head -n 1)"
fi

# =============================================================================
# SECTION 4 — PYTHON DEPENDENCIES
# Installs into the CORRECT python (the one CMake will use)
# =============================================================================
echo "[4/7] Installing Python dependencies..."
echo "  Using Python: $PY ($PY_VERSION)"
echo "  pip flags: $PIP_FLAGS"

# Upgrade pip first
"$PY" -m pip install --upgrade pip setuptools wheel $PIP_FLAGS 2>/dev/null || \
"$PY" -m pip install --upgrade pip setuptools wheel 2>/dev/null || true

# Build tools
echo "  Installing build tools (meson, cython, ninja)..."
"$PY" -m pip install --upgrade cython meson meson-python ninja $PIP_FLAGS

# Scientific stack
echo "  Installing scientific stack (numpy, scipy, matplotlib)..."
"$PY" -m pip install --upgrade numpy scipy matplotlib tomli $PIP_FLAGS

# Geo / IO
echo "  Installing geo/IO libraries (netcdf4, pyshp)..."
"$PY" -m pip install --upgrade netcdf4 pyshp $PIP_FLAGS

# ANUGA-specific
echo "  Installing ANUGA-specific deps (dill, pymetis, triangle, six)..."
"$PY" -m pip install --upgrade dill pymetis pytools polyline triangle six $PIP_FLAGS

# mpi4py — MUST be built from source against the correct mpicc
echo "  Building mpi4py from source (this takes ~1 min)..."
"$PY" -m pip uninstall -y mpi4py 2>/dev/null || true
MPICC="$(command -v mpicc)" "$PY" -m pip install \
  --no-cache-dir --no-binary mpi4py mpi4py $PIP_FLAGS

# Verify
echo "  Verifying mpi4py..."
"$PY" -c "import mpi4py; print('  ✓ mpi4py:', mpi4py.__version__)"
echo "  Verifying numpy..."
"$PY" -c "import numpy; print('  ✓ numpy:', numpy.__version__)"

# =============================================================================
# SECTION 5 — TOOLS (GeoServer / Node / anuga-viewer)
# =============================================================================
echo "[5/7] Setting up optional tools (GeoServer / Node / anuga-viewer)..."
mkdir -p "$TOOLS_DIR"

# GeoServer
if [ -f "$GEOSERVER_ZIP" ]; then
  if [ ! -d "$GEOSERVER_DIR" ]; then
    echo "  Unpacking GeoServer..."
    unzip -q "$GEOSERVER_ZIP" -d "$GEOSERVER_DIR"
    echo "  GeoServer unpacked."
  else
    echo "  GeoServer already unpacked."
  fi
else
  echo "  WARNING: GeoServer zip not found at: $GEOSERVER_ZIP"
  echo "           Place geoserver-2.28.2-bin.zip in opensource_tools/ to enable."
fi

# Node
if [ -f "$NODE_TAR" ]; then
  if [ ! -d "$NODE_DIR" ]; then
    echo "  Extracting Node..."
    tar -xf "$NODE_TAR" -C "$TOOLS_DIR"
    echo "  Node extracted."
  else
    echo "  Node already extracted."
  fi
else
  echo "  WARNING: Node tarball not found at: $NODE_TAR"
  echo "           Place node-v24.13.0-linux-x64.tar.xz in opensource_tools/ to enable."
fi

# anuga-viewer (best effort)
build_viewer=false
[ "$INSTALL_ANUGA_VIEWER" = "1" ] && build_viewer=true
[ "$INSTALL_ANUGA_VIEWER" = "0" ] && build_viewer=false
[ "$INSTALL_ANUGA_VIEWER" = "auto" ] && build_viewer=true

if $build_viewer; then
  viewer_deps_ok=false
  if [ "$PKG_MGR" = "apt" ] && $SUDO_WORKS; then
    $SUDO apt-get install -y libgdal-dev libcppunit-dev libopenscenegraph-dev 2>/dev/null && viewer_deps_ok=true
  elif [ "$PKG_MGR" = "dnf" ] && $SUDO_WORKS; then
    if dnf info gdal-devel >/dev/null 2>&1; then
      $SUDO dnf -y install OpenSceneGraph-devel cppunit-devel gdal-devel 2>/dev/null && viewer_deps_ok=true
    else
      echo "  WARNING: gdal-devel unavailable — skipping anuga-viewer."
    fi
  else
    echo "  WARNING: No sudo — skipping anuga-viewer system deps."
  fi

  if $viewer_deps_ok; then
    [ ! -d "$VIEWER_DIR" ] && git clone https://github.com/GeoscienceAustralia/anuga-viewer.git "$VIEWER_DIR"
    pushd "$VIEWER_DIR" >/dev/null
    make -j"$(nproc 2>/dev/null || echo 2)"
    mkdir -p "$VIEWER_DIR/local"
    make install PREFIX="$VIEWER_DIR/local" 2>/dev/null || make install || true
    popd >/dev/null
    echo "  anuga-viewer built."
  else
    echo "  anuga-viewer: skipped."
  fi
fi

# =============================================================================
# SECTION 6 — BUILD ANUGA VIA CMAKE
# Passes the CORRECT python to CMake so it matches what pip installed into
# =============================================================================
echo "[6/7] Building ANUGA via CMake..."

PY_FULL_PATH="$(command -v "$PY")"
mkdir -p "${ROOT_DIR}/build"
cd "${ROOT_DIR}/build"

cmake .. \
  -DPython3_EXECUTABLE="$PY_FULL_PATH" \
  -DMPI_C_COMPILER="$(command -v mpicc)" \
  -DMPI_CXX_COMPILER="$(command -v mpicxx 2>/dev/null || command -v mpic++ 2>/dev/null || echo '')"

make setup

# =============================================================================
# SECTION 7 — GENERATE ENV SCRIPTS
# =============================================================================
echo "[7/7] Writing environment scripts..."

# MPI env (also bakes in the Python that was used)
cat > "${ROOT_DIR}/build/setup_mpi_env.sh" << EOF
#!/bin/bash
# Source this before running ANUGA simulations
export PATH="\$HOME/.local/bin:${MPI_BIN}:\$PATH"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:\${LD_LIBRARY_PATH:-}"

# Alias python3 to the correct version used during build
export ANUGA_PYTHON="${PY_FULL_PATH}"

if command -v mpicc >/dev/null 2>&1; then
  echo "MPI compiler: \$(command -v mpicc)"
else
  echo "WARNING: mpicc not found in PATH"
fi
EOF
chmod +x "${ROOT_DIR}/build/setup_mpi_env.sh"

# Tools env
cat > "${ROOT_DIR}/build/setup_tools_env.sh" << EOF
#!/bin/bash
# Source this before using Node/GeoServer/anuga-viewer

export PATH="\$HOME/.local/bin:\$PATH"

if [ -d "${NODE_DIR}" ]; then
  export NODE_HOME="${NODE_DIR}"
  export PATH="\$NODE_HOME/bin:\$PATH"
fi

if [ -d "${GEOSERVER_DIR}" ]; then
  export GEOSERVER_HOME="${GEOSERVER_DIR}"
fi

if [ -d "${VIEWER_DIR}/local/bin" ]; then
  export SWOLLEN_BINDIR="${VIEWER_DIR}/local/bin"
  export PATH="\$PATH:\$SWOLLEN_BINDIR"
elif [ -d "${VIEWER_DIR}/bin" ]; then
  export SWOLLEN_BINDIR="${VIEWER_DIR}/bin"
  export PATH="\$PATH:\$SWOLLEN_BINDIR"
fi

echo "Tools environment configured."
echo "  NODE_HOME     = \${NODE_HOME:-not set}"
echo "  GEOSERVER_HOME= \${GEOSERVER_HOME:-not set}"
echo "  SWOLLEN_BINDIR= \${SWOLLEN_BINDIR:-not set}"
EOF
chmod +x "${ROOT_DIR}/build/setup_tools_env.sh"

# GeoServer start
cat > "${ROOT_DIR}/build/geoserver_start.sh" << EOF
#!/bin/bash
set -euo pipefail
source "\$(dirname "\$0")/setup_tools_env.sh" >/dev/null 2>&1 || true
if [ -z "\${GEOSERVER_HOME:-}" ]; then
  echo "ERROR: GEOSERVER_HOME not set. Is GeoServer unpacked in opensource_tools/?"
  exit 1
fi
cd "\$GEOSERVER_HOME/bin"
nohup bash startup.sh > "\$GEOSERVER_HOME/../geoserver.out" 2>&1 &
echo "GeoServer starting. Log: \$GEOSERVER_HOME/../geoserver.out"
echo "Verify: curl -I http://localhost:8080/geoserver"
EOF
chmod +x "${ROOT_DIR}/build/geoserver_start.sh"

# GeoServer stop
cat > "${ROOT_DIR}/build/geoserver_stop.sh" << EOF
#!/bin/bash
set -euo pipefail
source "\$(dirname "\$0")/setup_tools_env.sh" >/dev/null 2>&1 || true
if [ -z "\${GEOSERVER_HOME:-}" ]; then
  echo "ERROR: GEOSERVER_HOME not set."
  exit 1
fi
cd "\$GEOSERVER_HOME/bin"
bash shutdown.sh || true
echo "GeoServer stop requested."
EOF
chmod +x "${ROOT_DIR}/build/geoserver_stop.sh"

# =============================================================================
# DONE
# =============================================================================
echo ""
echo "================================================================"
echo "  ANUGA Setup Complete!"
echo "================================================================"
echo "  Python used    : $PY_FULL_PATH ($PY_VERSION)"
echo "  MPI compiler   : $(command -v mpicc)"
echo "  Mode           : $MODE"
echo "----------------------------------------------------------------"
echo "  Test ANUGA:        cd build && make test_anuga"
echo "  Tools env:         source build/setup_tools_env.sh"
echo "  Start GeoServer:   bash build/geoserver_start.sh"
echo "  Stop GeoServer:    bash build/geoserver_stop.sh"
echo "  Run with MPI:      source build/setup_mpi_env.sh"
echo "                     mpirun -np 16 $PY simulation.py"
echo "================================================================"
echo ""