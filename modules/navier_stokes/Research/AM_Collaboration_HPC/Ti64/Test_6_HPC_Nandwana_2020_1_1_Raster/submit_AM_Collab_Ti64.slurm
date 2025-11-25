#!/bin/bash


# Submit this script with: sbatch thefilename

#SBATCH --time=72:00:00 # walltime

#SBATCH --ntasks-per-node=47 # number of processor cores (i.e. tasks)

#SBATCH --nodes=3 # number of nodes

#SBATCH --wckey=ne_ldrd # Project Code

#SBATCH --partition=general  # short, general, hbm (check needed)

#SBATCH --job-name="ALETempFieldforCA"

#SBATCH -e slurm-%j.err # %j will be replaced by the SLURM_JOB_ID

#SBATCH -o slurm-%j.out # %j will be replaced by the SLURM_JOB_ID

#SBATCH --mail-user=tteng2@ncsu.edu # email address

#SBATCH --mail-type=BEGIN,END,FAIL

 
# cd $SLURM_SUBMIT_DIR   # Not Required
 
module purge
module load use.moose moose-dev-openmpi/2025.09.18

##module load pbs
## module load cmake/3.27.7-gcc-12.3.0-5cfk
## module load gcc/12.3.0-gcc-10.5.0-vx2f
## module load mvapich2/2.3.7-1-gcc-12.3.0
## ml use.moose moose-dev-openmpi/2025.03.24
##module load cmake/3.22.3-gcc-9.3.0-ngra gcc/9.3.0-gcc-4.8.5-twls openmpi/4.0.5_ucx1.9
##module load mvapich2 cmake
##module load use.moose PETSc/3.11.4-GCC
 
##module load PETSc/3.10.3-foss-2018b
##module load MVAPICH2/2.2-GCC-5.4.0-2.28
##module load PETSc
##export OMP_NUM_THREADS=1


##which mpiexec

mpiexec -n 141 moose-dev-exec /home/tengtsu/projects_moose/moose/modules/navier_stokes/navier_stokes-opt -i 3d_ss_mod1_Ti64_NoConvectiveRadiactive.i -log_view >> 2025_11_15_MOOSE_ALE_TempField.log
## mpiexec -n 48 moose-dev-exec $HOME/projects/marmot/marmot-opt -i 2024_09_11_darkzone_subgrain_nuc4_T1000_scaling3_baseline.i -log_view >> 2024_09_11_darkzone_subgrain_nuc4_T1000_scaling3_baseline.log
## mpiexec $HOME/projects/marmot/marmot-opt -i HBS_bub_vol_test.i -log_view >> HBS_bub_vol_test.log

#############################
date     #! print date and time