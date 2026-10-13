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
source ~/.bashrc.conda
conda activate grad_unwarp

# Load shared config from repo root
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/config.sh"

to_nii() {
    local f="$1"
    f="${f%.nii.gz}"
    f="${f%.nii}"
    echo "${f}.nii"
}

ensure_nii() {
    local f="$1"
    local nii
    nii="$(to_nii "$f")"
    if [[ -f "${nii}.gz" ]]; then
        gunzip -f "${nii}.gz" >/dev/null 2>&1 || true
    fi
    echo "$nii"
}

echo "Running gradient nonlinearity correction on files matching:" 
echo "$fn_pattern"
FSL --version $FSL_VERSION $CONFIG_GRAD_NONL_CORR_SCRIPTS/runCorrection.sh -w $working_dir $scanner_name $fn_pattern
# will save the results in input_dir/undistorted
echo

undistorted_dir="$input_dir/undistorted"

if [ ! -d "$undistorted_dir" ]; then
    echo "Directory not found: $undistorted_dir"
    exit 1
fi

echo "Applying jacobian modulation and calculating magnitude and phase for files matching $pattern in: $undistorted_dir"
find "$undistorted_dir" -maxdepth 1 -type f -name "*${pattern}*_part-resReal_*_desc-undistorted.nii*" -print0 | \
while IFS= read -r -d '' real_file; do
    imag_file="${real_file/part-resReal/part-resImag}"

    real_file="$(ensure_nii "$real_file")"
    imag_file="$(ensure_nii "$imag_file")"

    # Extract the suffix before _desc-undistorted (e.g., _MPM)
    base_part="${real_file%_desc-undistorted*}" # remove everything from _desc-undistorted onwards
    suffix="_${base_part##*_}" # extract the last part (e.g., _MPM)

    # Rebuild real_file filename with suffix moved after _desc-undistorted
    real_file_adj="${real_file%${suffix}_desc-undistorted*}_desc-undistorted${suffix}.nii"
    imag_file_adj="${imag_file%${suffix}_desc-undistorted*}_desc-undistorted${suffix}.nii"

    if [[ -f "$imag_file" ]]; then

        # Apply jacobian intensity correction
        real_file_jac="$(to_nii "${real_file_adj/desc-undistorted/desc-undistortedJac}")"
        imag_file_jac="$(to_nii "${imag_file_adj/desc-undistorted/desc-undistortedJac}")"
        FSL --version $FSL_VERSION fslmaths "$real_file" -mul $working_dir/warp_jacobian.nii.gz "$real_file_jac"
        FSL --version $FSL_VERSION fslmaths "$imag_file" -mul $working_dir/warp_jacobian.nii.gz "$imag_file_jac"
        real_file_jac="$(ensure_nii "$real_file_jac")"
        imag_file_jac="$(ensure_nii "$imag_file_jac")"

        resComplex_file="$(to_nii "${real_file_jac/part-resReal/part-resComplex}")"
        resMag_file="$(to_nii "${real_file_jac/part-resReal/part-mag}")"
        resPhase_file="$(to_nii "${real_file_jac/part-resReal/part-phase}")"

        # Transfer data back into Magnitude and Phase images
        mrcalc "$real_file_jac" "$imag_file_jac" -complex "$resComplex_file"
        mrcalc "$resComplex_file" -abs "$resMag_file"
        mrcalc "$resComplex_file" -phase "$resPhase_file"
    else
        echo "Imaginary file not found for $real_file"

    fi
done


