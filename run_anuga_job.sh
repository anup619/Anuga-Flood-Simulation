#!/bin/bash
#SBATCH --job-name=anuga_simulation
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --time=02:00:00
#SBATCH --output=anuga_%j.out
#SBATCH --error=anuga_%j.err

# Clean environment first
module purge

# Load OpenMPI (must match what was used during setup)
module load openmpi-4.1.6

# Activate conda environment
source $HOME/software/anuga/miniconda3/bin/activate
conda activate anuga-env

# Suppress harmless GeoTIFF activation warning
export GEOTIFF_CSV=""

# Load ANUGA MPI environment (sets LD_LIBRARY_PATH etc.)
source $SLURM_SUBMIT_DIR/build/setup_mpi_env.sh

echo "============================================"
echo "Job ID        : $SLURM_JOB_ID"
echo "Job Name      : $SLURM_JOB_NAME"
echo "Nodes         : $SLURM_JOB_NUM_NODES"
echo "Tasks (cores) : $SLURM_NTASKS"
echo "Submit dir    : $SLURM_SUBMIT_DIR"
echo "Python        : $(which python)"
echo "mpirun        : $(which mpirun)"
echo "============================================"

# Move to project directory
cd $SLURM_SUBMIT_DIR

# Run simulation
echo "Starting ANUGA simulation with $SLURM_NTASKS MPI tasks..."
mpirun -np $SLURM_NTASKS python mahanadi_test_case/simulate.py

echo "Simulation complete."