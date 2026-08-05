#!/bin/bash

# Submit this script with: sbatch thefilename

#SBATCH --time=168:00:00 # walltime
#SBATCH --ntasks-per-node=40 # number of processor cores (i.e. tasks)
#SBATCH --nodes=4 # number of nodes
#SBATCH --wckey ne_ldrd # Project Code
#SBATCH --partition=general  # short, general, hbm (check needed)
#SBATCH -J "umo_extrusion" # job name
#SBATCH -e slurm-%j.err # %j will be replaced by the SLURM_JOB_ID
#SBATCH -o slurm-%j.out # %j will be replaced by the SLURM_JOB_ID
#SBATCH --mail-user=tsuchun.teng@inl.gov # email address
#SBATCH --mail-type=BEGIN
#SBATCH --mail-type=END

# LOAD MODULES, INSERT CODE, AND RUN YOUR PROGRAMS HERE
#!/bin/bash
 
# cd $SLURM_SUBMIT_DIR   # Not Required
 
module purge
module load use.moose moose-dev-openmpi/2026.06.16

##which mpiexec

mpiexec -n 160 moose-dev-exec /home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt -i km_deformed_grain_nucleation_mod10.i

#############################
date     #! print date and time