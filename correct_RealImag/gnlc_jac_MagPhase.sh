#!/bin/bash

input_dir=$1
working_dir=$2
pattern=$3
scanner_name=$4

FSL_VERSION=6.0.7.11 

fn_pattern=$input_dir/*$pattern*part-res*.nii # unique pattern of the real and imaginary images

echo "input_dir: $input_dir"
echo "working_dir: $working_dir"
echo "scanner: $scanner_name"

# make grad_unwarp environment available
source ~/bash.conda
conda activate grad_unwarp

echo "Running gradient nonlinearity correction on files matching:" 
echo "$fn_pattern"
FSL --version $FSL_VERSION /data/u_kuegler_software/git/gradient-nonlinearity-correction-scripts/runCorrection.sh -w $working_dir $scanner_name $fn_pattern
# will save the results in input_dir/undistorted
echo

undistorted_dir="$input_dir/undistorted"

if [ ! -d "$undistorted_dir" ]; then
    echo "Directory not found: $undistorted_dir"
    exit 1
fi

echo "Applying jacobian modulation and calculating magnitude and phase for files matching for $pattern files in: $undistorted_dir"
find "$undistorted_dir" -maxdepth 1 -type f -name "*${pattern}*_part-resReal_*_desc-undistorted.nii*" -print0 | \
while IFS= read -r -d '' real_file; do
    imag_file="${real_file/part-resReal/part-resImag}"

    # Extract the suffix before _desc-undistorted (e.g., _MPM)
    base_part="${real_file%_desc-undistorted*}" # remove everything from _desc-undistorted onwards
    suffix="_${base_part##*_}" # extract the last part (e.g., _MPM)
    
    if [[ "$real_file" == *.nii.gz ]]; then
        ext=".nii.gz"
    else
        ext=".nii"
    fi

    # Rebuild real_file with suffix moved after _desc-undistorted
    real_file_adj="${real_file%${suffix}_desc-undistorted*}_desc-undistorted${suffix}${ext}"
    imag_file_adj="${imag_file%${suffix}_desc-undistorted*}_desc-undistorted${suffix}${ext}"

    real_file_jac="${real_file_adj/desc-undistorted/desc-undistortedJac}"
    imag_file_jac="${imag_file_adj/desc-undistorted/desc-undistortedJac}"
    resComplex_file="${real_file_jac/part-resReal/part-resComplex}"
    resMag_file="${real_file_jac/part-resReal/part-mag}"
    resPhase_file="${real_file_jac/part-resReal/part-phase}"

    if [[ -f "$imag_file" ]]; then

        # Apply jacobian intensity correction
        FSL --version $FSL_VERSION fslmaths "$real_file" -mul $working_dir/warp_jacobian.nii.gz "$real_file_jac"
        FSL --version $FSL_VERSION fslmaths "$imag_file" -mul $working_dir/warp_jacobian.nii.gz "$imag_file_jac"

        # Transfer data back into Magnitude and Phase images
        mrcalc "$real_file" "$imag_file" -complex "$resComplex_file"
        mrcalc "$resComplex_file" -abs "$resMag_file"
        mrcalc "$resComplex_file" -phase "$resPhase_file"
    else
        echo "Imaginary file not found for $real_file"

    fi
done


