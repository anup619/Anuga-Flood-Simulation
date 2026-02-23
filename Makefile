# =============================================================================
# Makefile - ANUGA Unified Build System
# Works on: Ubuntu/Debian (apt), Rocky/AlmaLinux (dnf), HPC (modules+conda)
# =============================================================================

.PHONY: all setup install test verify \
        geoserver-start geoserver-stop \
        submit-pbs submit-slurm \
        clean clean-outputs clean-anuga clean-opensourcetools clean-all help

all: setup

# -----------------------------
# Main setup (runs setup.sh — auto-detects environment)
# -----------------------------
setup:
	@echo "Running ANUGA setup (auto-detects: apt / dnf / HPC)..."
	@if [ ! -f setup.sh ]; then \
		echo "ERROR: setup.sh not found"; exit 1; \
	fi
	@chmod +x setup.sh
	@./setup.sh

install: setup

# -----------------------------
# Test ANUGA installation
# -----------------------------
test:
	@echo "Testing ANUGA installation..."
	@if [ ! -f build/test_anuga.sh ]; then \
		echo "ERROR: build/test_anuga.sh not found. Run 'make setup' first."; exit 1; \
	fi
	@bash build/test_anuga.sh

# -----------------------------
# Quick import check
# -----------------------------
verify:
	@echo "Quick ANUGA import check..."
	@if [ ! -f build/setup_mpi_env.sh ]; then \
		echo "ERROR: build/setup_mpi_env.sh not found. Run 'make setup' first."; exit 1; \
	fi
	@bash -c "source build/setup_mpi_env.sh >/dev/null 2>&1 && \
		python -c 'import anuga; print(\"✓ ANUGA\", anuga.__version__)' && \
		python -c 'import mpi4py; print(\"✓ mpi4py\", mpi4py.__version__)'"

# -----------------------------
# GeoServer (desktop only)
# -----------------------------
geoserver-start:
	@echo "Starting GeoServer..."
	@if [ ! -f build/geoserver_start.sh ]; then \
		echo "ERROR: build/geoserver_start.sh not found."; \
		echo "       GeoServer is only available on desktop Linux (not HPC)."; exit 1; \
	fi
	@bash build/geoserver_start.sh

geoserver-stop:
	@echo "Stopping GeoServer..."
	@if [ ! -f build/geoserver_stop.sh ]; then \
		echo "ERROR: build/geoserver_stop.sh not found."; \
		echo "       GeoServer is only available on desktop Linux (not HPC)."; exit 1; \
	fi
	@bash build/geoserver_stop.sh

# -----------------------------
# Job submission (HPC only)
# -----------------------------
submit-pbs:
	@echo "Submitting ANUGA job via PBS..."
	@if [ ! -f run_anuga_job.sh ]; then \
		echo "ERROR: run_anuga_job.sh not found. Run 'make setup' first."; exit 1; \
	fi
	qsub run_anuga_job.sh

submit-slurm:
	@echo "Submitting ANUGA job via SLURM..."
	@if [ ! -f run_anuga_job.sh ]; then \
		echo "ERROR: run_anuga_job.sh not found. Run 'make setup' first."; exit 1; \
	fi
	sbatch run_anuga_job.sh

# -----------------------------
# Clean targets
# -----------------------------
clean:
	@echo "Cleaning build directory..."
	@if [ -d build ]; then \
		rm -rf build/; echo "Build directory removed."; \
	else \
		echo "Build directory does not exist (already clean)."; \
	fi

clean-outputs:
	@echo "Cleaning ANUGA simulation outputs..."
	@if [ -d mahanadi_test_case/mesh_cache ]; then \
		rm -rf mahanadi_test_case/mesh_cache/*; echo "Cleared mesh_cache."; \
	else echo "mesh_cache directory does not exist."; fi
	@if [ -d mahanadi_test_case/anuga_outputs ]; then \
		rm -rf mahanadi_test_case/anuga_outputs/*; echo "Cleared anuga_outputs."; \
	else echo "anuga_outputs directory does not exist."; fi
	@rm -rf mahanadi_test_case/__pycache__ mahanadi_test_case/anuga_pmesh_gui.log 2>/dev/null || true
	@echo "Simulation outputs cleaned."

clean-anuga:
	@echo "Removing ANUGA source..."
	@if [ -d anuga_core ]; then \
		rm -rf anuga_core/; echo "ANUGA source removed."; \
	else echo "ANUGA source directory does not exist."; fi

clean-opensourcetools:
	@echo "Removing optional tools..."
	@rm -rf opensource_tools/geoserver-2.28.2-bin/ 2>/dev/null && echo "GeoServer removed." || true
	@rm -rf opensource_tools/node-v24.13.0-linux-x64/ 2>/dev/null && echo "Node removed." || true
	@rm -rf opensource_tools/anuga-viewer/ 2>/dev/null && echo "anuga-viewer removed." || true
	@echo "OpenSourceTools cleaned."

clean-all: clean clean-outputs clean-anuga clean-opensourcetools
	@rm -rf anuga-viewer-app/node_modules/ 2>/dev/null && echo "React node_modules removed." || true
	@rm -f run_anuga_job.sh 2>/dev/null || true
	@echo "Complete cleanup done."

# -----------------------------
# Help
# -----------------------------
help:
	@echo ""
	@echo "ANUGA Unified Build System"
	@echo "Auto-detects: Ubuntu/Debian (apt) | Rocky/AlmaLinux (dnf) | HPC (module+conda)"
	@echo ""
	@echo "Core targets:"
	@echo "  make setup            - Install deps + build ANUGA (auto-detects env)"
	@echo "  make install          - Alias for setup"
	@echo "  make test             - Test mpi4py + ANUGA import"
	@echo "  make verify           - Quick import sanity check"
	@echo ""
	@echo "Desktop Linux only:"
	@echo "  make geoserver-start  - Start GeoServer (detached)"
	@echo "  make geoserver-stop   - Stop GeoServer"
	@echo ""
	@echo "HPC only:"
	@echo "  make submit-pbs       - Submit job via qsub (PBS)"
	@echo "  make submit-slurm     - Submit job via sbatch (SLURM)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            - Remove build/"
	@echo "  make clean-outputs    - Remove simulation outputs"
	@echo "  make clean-anuga      - Remove anuga_core/ source"
	@echo "  make clean-opensourcetools - Remove GeoServer/Node/viewer"
	@echo "  make clean-all        - Remove everything"
	@echo ""
	@echo "Environment overrides:"
	@echo "  FORCE_HPC=1 make setup          - Force HPC mode"
	@echo "  FORCE_HPC=0 make setup          - Force desktop mode"
	@echo "  CONDA_ENV_NAME=myenv make setup - Use custom conda env name"
	@echo "  INSTALL_ANUGA_VIEWER=0 make setup - Skip anuga-viewer"
	@echo ""