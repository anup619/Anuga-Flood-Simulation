cmake_minimum_required(VERSION 3.15)
project(ANUGA_Setup)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Use the exact Python interpreter found (respects active conda env)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# -----------------------------------------------------------------------
# pkg-config / system library checks
# On HPC these are optional — conda + module system provides the libs.
# On desktop Linux (apt/dnf) these are required.
# -----------------------------------------------------------------------
find_package(PkgConfig QUIET)

if(PKG_CONFIG_FOUND)
  message(STATUS "pkg-config available — checking system libraries...")

  # GDAL (optional everywhere)
  pkg_check_modules(GDAL gdal)
  if(GDAL_FOUND)
    message(STATUS "Found GDAL: ${GDAL_VERSION}")
  else()
    message(STATUS "GDAL not found (ok — optional, only needed for anuga-viewer)")
  endif()

  # NetCDF
  pkg_check_modules(NETCDF netcdf)
  if(NETCDF_FOUND)
    message(STATUS "Found NetCDF via pkg-config: ${NETCDF_VERSION}")
  else()
    message(STATUS "NetCDF not found via pkg-config (ok on HPC — conda provides netcdf4 at runtime)")
  endif()

else()
  message(STATUS "pkg-config not available (common on HPC) — skipping system library checks")
  message(STATUS "  netcdf4 and gdal will be provided by conda at runtime")
endif()

# -----------------------------------------------------------------------
# MPI — required. On HPC, user must load MPI module before running cmake.
# -----------------------------------------------------------------------
find_package(MPI REQUIRED)
if(MPI_FOUND)
  message(STATUS "Found MPI")
  message(STATUS "  MPI C compiler  : ${MPI_C_COMPILER}")
  message(STATUS "  MPI CXX compiler: ${MPI_CXX_COMPILER}")
else()
  message(FATAL_ERROR
    "MPI not found.\n"
    "Desktop: install libopenmpi-dev (apt) or openmpi-devel (dnf)\n"
    "HPC:     load an MPI module first, e.g.:\n"
    "           module load openmpi-4.1.6\n"
    "         then re-run cmake"
  )
endif()

# -----------------------------
# Paths
# -----------------------------
set(ANUGA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/anuga_core")
set(TOOLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/opensource_tools")

# -----------------------------
# Clone ANUGA (idempotent)
# -----------------------------
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/clone_anuga.sh
"#!/bin/bash
set -euo pipefail
if [ ! -d \"${ANUGA_DIR}\" ]; then
  echo \"Cloning ANUGA repository...\"
  git clone https://github.com/GeoscienceAustralia/anuga_core.git \"${ANUGA_DIR}\"
  cd \"${ANUGA_DIR}\"
  git checkout 3.2.0 || true
  echo \"ANUGA cloned (tag 3.2.0).\"
else
  echo \"ANUGA source already present at ${ANUGA_DIR}\"
fi
")

add_custom_target(clone_anuga
  COMMAND chmod +x ${CMAKE_CURRENT_BINARY_DIR}/clone_anuga.sh
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/clone_anuga.sh
  COMMENT "Cloning ANUGA repository"
)

# -----------------------------
# MPI environment helper
# Works on both desktop (fixed paths) and HPC (module fallback)
# -----------------------------
set(MPI_ENV_CONTENT "#!/bin/bash
# Source this before running ANUGA with MPI
# Works on: Ubuntu/Debian, Rocky/AlmaLinux, HPC (Param Rudra etc.)
# Usage: source build/setup_mpi_env.sh

export PATH=\"\$HOME/.local/bin:\$PATH\"

# HPC: try to load MPI module if mpicc not already in PATH
if ! command -v mpicc >/dev/null 2>&1; then
  if command -v module >/dev/null 2>&1; then
    for mod in openmpi-4.1.6 compiler/openmpi/4.1.4 openmpi/4.1.4 \\
               apps/intel_mpi_2021.14 compiler/oneapi2024/mpi/2021.11 mpich; do
      module load \"\$mod\" 2>/dev/null && break || true
    done
  fi
fi

# Desktop: search known MPI paths
if ! command -v mpicc >/dev/null 2>&1; then
  for d in \\
    /usr/lib64/openmpi/bin \\
    /usr/lib/openmpi/bin \\
    /usr/lib/x86_64-linux-gnu/openmpi/bin \\
    /usr/lib/aarch64-linux-gnu/openmpi/bin \\
    /opt/openmpi/bin /opt/ompi/bin \\
    /usr/local/openmpi/bin \\
    /home/apps/openmpi/bin; do
    if [ -x \"\$d/mpicc\" ]; then
      export PATH=\"\$d:\$PATH\"
      base=\"\$(dirname \"\$d\")\"
      [ -d \"\$base/lib64\" ] && export LD_LIBRARY_PATH=\"\$base/lib64:\${LD_LIBRARY_PATH:-}\"
      [ -d \"\$base/lib\" ]   && export LD_LIBRARY_PATH=\"\$base/lib:\${LD_LIBRARY_PATH:-}\"
      break
    fi
  done
fi

if command -v mpicc >/dev/null 2>&1; then
  echo \"MPI compiler: \$(command -v mpicc)\"
else
  echo \"WARNING: mpicc not found in PATH\"
fi
")

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh "${MPI_ENV_CONTENT}")

add_custom_target(write_env
  COMMAND ${CMAKE_COMMAND} -E echo "MPI environment script written"
  COMMENT "Writing MPI environment helper"
)

# -----------------------------
# Build/install ANUGA
# Handles both desktop (--user + --break-system-packages)
# and HPC (conda env, no --user needed)
# -----------------------------
set(BUILD_ANUGA_CONTENT "#!/bin/bash
set -euo pipefail

export PATH=\"\$HOME/.local/bin:\$PATH\"
PY=\"${Python3_EXECUTABLE}\"

if [ -f \"${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh\" ]; then
  source \"${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh\" >/dev/null 2>&1 || true
fi

command -v mpicc >/dev/null 2>&1 || { echo \"ERROR: mpicc not found.\"; exit 1; }
command -v meson >/dev/null 2>&1 || { echo \"ERROR: meson not found. Run setup.sh first.\"; exit 1; }

cd \"${ANUGA_DIR}\"
echo \"Building and installing ANUGA...\"

# Detect if inside a conda env (then --user is not needed/wanted)
IN_CONDA=false
[ -n \"\${CONDA_PREFIX:-}\" ] && IN_CONDA=true

# Detect --break-system-packages support
PIP_EXTRA=\"\"
if \"\$PY\" -m pip install --help 2>&1 | grep -q 'break-system-packages'; then
  PIP_EXTRA=\"--break-system-packages\"
fi

if \$IN_CONDA; then
  echo \"  Installing into conda env: \$CONDA_PREFIX\"
  \"\$PY\" -m pip install -e . --no-build-isolation --no-deps
else
  echo \"  Installing to ~/.local (user site-packages)\"
  \"\$PY\" -m pip install -e . --no-build-isolation --no-deps --user \$PIP_EXTRA
fi

echo \"ANUGA installation complete.\"
\"\$PY\" -c 'import anuga; print(\"  ✓ ANUGA version:\", anuga.__version__)'
")

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/build_anuga.sh "${BUILD_ANUGA_CONTENT}")

add_custom_target(build_anuga
  COMMAND chmod +x ${CMAKE_CURRENT_BINARY_DIR}/build_anuga.sh
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/build_anuga.sh
  DEPENDS clone_anuga write_env
  COMMENT "Installing ANUGA"
)

# -----------------------------
# Test ANUGA
# -----------------------------
set(TEST_ANUGA_CONTENT "#!/bin/bash
set -euo pipefail

PY=\"${Python3_EXECUTABLE}\"

if [ -f \"${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh\" ]; then
  source \"${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh\" >/dev/null 2>&1 || true
fi

echo \"\"
echo \"=== Testing ANUGA Installation ===\"

echo \"[1/3] Testing mpi4py...\"
\"\$PY\" -c 'import mpi4py; print(\"  ✓ mpi4py:\", mpi4py.__version__)'

echo \"[2/3] Testing ANUGA import...\"
\"\$PY\" -c 'import anuga; print(\"  ✓ ANUGA:\", anuga.__version__)'

echo \"[3/3] Testing ANUGA MPI init...\"
\"\$PY\" -c 'import anuga; from anuga import myid, numprocs; print(\"  ✓ myid:\", myid, \"| numprocs:\", numprocs)'

echo \"\"
echo \"=== All tests passed ===\"
echo \"\"
echo \"Run with MPI:\"
echo \"  source ${CMAKE_CURRENT_BINARY_DIR}/setup_mpi_env.sh\"
echo \"  mpirun -np 4 python3 simulation.py\"
")

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/test_anuga.sh "${TEST_ANUGA_CONTENT}")

add_custom_target(test_anuga
  COMMAND chmod +x ${CMAKE_CURRENT_BINARY_DIR}/test_anuga.sh
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/test_anuga.sh
  DEPENDS build_anuga
  COMMENT "Testing ANUGA installation"
)

# -----------------------------
# Optional tools check (desktop only)
# -----------------------------
set(TEST_TOOLS_CONTENT "#!/bin/bash
set -euo pipefail

if [ -f \"${CMAKE_CURRENT_BINARY_DIR}/setup_tools_env.sh\" ]; then
  source \"${CMAKE_CURRENT_BINARY_DIR}/setup_tools_env.sh\" >/dev/null 2>&1 || true
fi

echo \"\"
echo \"=== Testing Optional Tools ===\"

command -v node >/dev/null 2>&1 \\
  && echo \"  ✓ Node: \$(node -v)\" \\
  || echo \"  ⚠ Node not on PATH (expected if not on desktop Linux)\"

[ -n \"\${GEOSERVER_HOME:-}\" ] && [ -d \"\$GEOSERVER_HOME\" ] \\
  && echo \"  ✓ GEOSERVER_HOME=\$GEOSERVER_HOME\" \\
  || echo \"  ⚠ GeoServer not configured (expected on HPC)\"

echo \"=== Tool checks done ===\"
")

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/test_tools.sh "${TEST_TOOLS_CONTENT}")

add_custom_target(test_tools
  COMMAND chmod +x ${CMAKE_CURRENT_BINARY_DIR}/test_tools.sh
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/test_tools.sh
  COMMENT "Testing optional tools (Node/GeoServer)"
)

# -----------------------------
# Master targets
# -----------------------------
add_custom_target(setup
  DEPENDS build_anuga
  COMMENT "Complete ANUGA setup"
)

add_custom_target(clean_anuga
  COMMAND ${CMAKE_COMMAND} -E remove_directory ${ANUGA_DIR}
  COMMENT "Removing ANUGA source directory"
)

# -----------------------------
# Summary
# -----------------------------
message(STATUS "")
message(STATUS "========================================")
message(STATUS "ANUGA CMake Configuration")
message(STATUS "========================================")
message(STATUS "Python      : ${Python3_EXECUTABLE}")
message(STATUS "MPI C       : ${MPI_C_COMPILER}")
message(STATUS "MPI CXX     : ${MPI_CXX_COMPILER}")
if(NETCDF_FOUND)
  message(STATUS "NetCDF      : ${NETCDF_VERSION} (system)")
else()
  message(STATUS "NetCDF      : via conda (runtime)")
endif()
message(STATUS "ANUGA dir   : ${ANUGA_DIR}")
message(STATUS "")
message(STATUS "Targets:")
message(STATUS "  make setup       - Clone + install ANUGA")
message(STATUS "  make test_anuga  - Test mpi4py + ANUGA")
message(STATUS "  make test_tools  - Check Node/GeoServer (desktop only)")
message(STATUS "  make clean_anuga - Remove ANUGA source")
message(STATUS "")
message(STATUS "NOTE: On HPC, load MPI module BEFORE running cmake:")
message(STATUS "  module load openmpi-4.1.6 && cmake ..")
message(STATUS "========================================")