#!/bin/bash

input_dir=$1
working_dir=$2
pattern=$3

FSL_VERSION=6.0.7.11 

fn_pattern=$input_dir/*$pattern*part-res*.nii # unique pattern of the real and imaginary images

echo "input_dir: $input_dir"
echo "working_dir: $working_dir"

# make grad_unwarp environment available
source ~/bash.conda
conda activate grad_unwarp

echo "Running gradient nonlinearity correction on files matching:" 
echo "$fn_pattern"
FSL --version $FSL_VERSION /data/u_kuegler_software/git/gradient-nonlinearity-correction-scripts/runCorrection.sh -w $working_dir Terra $fn_pattern
# will save the results in input_dir/undistorted
echo

undistorted_dir="$input_dir/undistorted"

if [ ! -d "$undistorted_dir" ]; then
    echo "Directory not found: $undistorted_dir"
    exit 1
fi

echo "Applying jacobian modulation and calculating magnitude and phase for files matching for $pattern files in: $undistorted_dir"
for real_file in "$undistorted_dir"/*"$pattern"*_part-resReal_*_desc-undistorted.nii; do
    imag_file="${real_file/part-resReal/part-resImag}"

    real_file_jac="${real_file/desc-undistorted/desc-undistortedJac}"
    imag_file_jac="${imag_file/desc-undistorted/desc-undistortedJac}"
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
        #/data/pt_02262/data/TH_bids/test_GNC_comparison/sub-004/ses-04/LORAKS/anat/wd_re_im/undistorted/*_part-resReal_*_desc-undistorted.nii

    fi
done


