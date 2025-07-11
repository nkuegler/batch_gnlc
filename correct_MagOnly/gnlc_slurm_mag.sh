#!/bin/bash

#
#SBATCH -c 16					# 16 cores
#SBATCH --mem 64G				# estimated 64G RAM
#SBATCH --time 100				# estimated 100 minutes maximum
#SBATCH -o /data/u_kuegler_software/git/batch_gnlc/correct_MagOnly/logs/%j.out	# redirect the output
#
# Real time consumption for (16 cores, 64G request) are about ....

input_dir=$1
working_dir=$2
pattern=$3
scanner_name=$4
output_dir=$5


FSL_VERSION=6.0.7.11
fn_pattern=$input_dir/*$pattern*.nii
GNLC_SCRIPT=/data/u_kuegler_software/git/gradient-nonlinearity-correction-scripts/runCorrection.sh


echo "input_dir: $input_dir"
echo "working_dir: $working_dir"


source ~/bash.preferences
conda activate grad_unwarp

echo "Running gradient nonlinearity correction on files matching:" 
echo "$fn_pattern"
FSL --version $FSL_VERSION $GNLC_SCRIPT -w $working_dir $scanner_name $fn_pattern
# will save the results in input_dir/undistorted
echo "Done"
echo


# TODO: apply jacobian correction
# TODO: stay consistent with the naming of the output files (3T and 7T)


# move the results to the actual output directory
echo "Moving results to: "
echo "$output_dir"
if [ -d "$input_dir/undistorted" ]; then
    mv $input_dir/undistorted/* $output_dir
    rm -rf $input_dir/undistorted
    echo "Done"
else
    echo "Warning: $input_dir/undistorted directory not found"
fi