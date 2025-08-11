#!/bin/bash

#
#SBATCH -c 16					# 16 cores
#SBATCH --mem 32G				# estimated 32G RAM
#SBATCH --time 90				# estimated 90 minutes maximum
#SBATCH -o /data/u_kuegler_software/git/batch_gnlc/correct_MagOnly/logs/%j.out	# redirect the output
#

input_dir=$1
working_dir=$2
pattern=$3
scanner_name=$4
output_dir=$5
skip_jacobian=$6 # if true, jacobian modulation will be skipped
delete_working_dir=$7 # if true, the working directory will be deleted after processing
container_path=$8 # optional: path to singularity container


FSL_VERSION=6.0.7.11 # only relevant if running on the host system, Version in the container is specified in the build script
fn_pattern=$input_dir/*$pattern*.nii
GNLC_SCRIPT=/data/u_kuegler_software/git/gradient-nonlinearity-correction-scripts/runCorrection.sh

# Specify the absolute path of this script (for re-executing the script inside the container)
SCRIPT_PATH="/data/u_kuegler_software/git/batch_gnlc/correct_MagOnly/gnlc_slurm_mag.sh"

if [[ "$container_path" != "--inside-container" ]]; then
    echo "input_dir: $input_dir"
    echo "working_dir: $working_dir"
    echo "skip_jacobian: $skip_jacobian"
    echo "delete_working_dir: $delete_working_dir"
    echo "container_path: $container_path"
    echo "--------------"
fi

# If container path is specified, run the entire script inside singularity
if [[ -n "$container_path" && "$container_path" != "--inside-container" ]]; then
    echo ">>> Running script inside singularity container: $container_path"
    # Re-execute this script inside the container with a special flag to indicate container execution
    singularity exec "$container_path" "$SCRIPT_PATH" "$input_dir" "$working_dir" "$pattern" "$scanner_name" "$output_dir" "$skip_jacobian" "$delete_working_dir" "--inside-container"
    exit $?
fi

# Check if we're running inside container (indicated by the special flag)
inside_container=false
if [[ "$container_path" == "--inside-container" ]]; then
    inside_container=true
    echo ">>> Running inside singularity container"
else
    echo ">>> Running on host system"
fi

# Set FSL command prefix based on execution environment
if [[ "$inside_container" == "true" ]]; then
    FSL_CMD=""  # No FSL version prefix needed in container
else
    FSL_CMD="FSL --version $FSL_VERSION" # Use FSL version on host
fi

# make grad_unwarp environment available (only on host)
# TODO: this conda environment must be added to the container as well
if [[ "$inside_container" == "false" ]]; then
    source ~/bash.conda
    conda activate grad_unwarp
fi


echo ">>> Running gradient nonlinearity correction on files matching:" 
echo "$fn_pattern"
$FSL_CMD $GNLC_SCRIPT -w $working_dir $scanner_name $fn_pattern
# will save the results in input_dir/undistorted
echo "Done"
echo

undistorted_dir="$input_dir/undistorted"

if [ ! -d "$undistorted_dir" ]; then
    echo "Directory not found: $undistorted_dir"
    exit 1
fi

if [ ! -d "$output_dir" ]; then
    mkdir -p "$output_dir"
fi


echo ">>> Applying jacobian modulation to the undistorted images containing '$pattern' files in: $undistorted_dir"
echo "    >>> Output will be saved in: $output_dir"
if [[ "$skip_jacobian" == "true" ]]; then
    echo "    >>> Skipping jacobian modulation."
else
    echo "    >>> Applying jacobian modulation."
fi

# Rename files correctly and copy corresponding JSON files
echo ">>> Renaming files and copying JSON files to output directory: $output_dir"

find "$undistorted_dir" -maxdepth 1 -type f -name "*${pattern}*_desc-undistorted.nii*" -print0 | \
while IFS= read -r -d '' img_undistorted; do
    # Extract the suffix before _desc-undistorted (e.g., _MPM)
    base_part="${img_undistorted%_desc-undistorted*}" # remove everything from _desc-undistorted onwards
    suffix="_${base_part##*_}" 

    if [[ "$img_undistorted" == *.nii.gz ]]; then
        ext=".nii.gz"
    else
        ext=".nii"
    fi

    # Move suffix after desc-undistorted
    img_undistorted_out="$output_dir/$(basename "${img_undistorted%${suffix}_desc-undistorted*}_desc-undistorted${suffix}${ext}")"

    if [[ "$skip_jacobian" == "true" ]]; then
        mv "$img_undistorted" "$img_undistorted_out"
    else
        img_undistorted_out="${img_undistorted_out/desc-undistorted/desc-undistortedJac}"
        # Apply jacobian intensity correction
        $FSL_CMD fslmaths "$img_undistorted" -mul $working_dir/warp_jacobian.nii.gz "$img_undistorted_out"
        gunzip "$img_undistorted_out" 2>/dev/null || true
    fi

    # Copy corresponding JSON file to output_dir
    json_file="${img_undistorted%${ext}}.json"
    if [[ ! -f "$json_file" ]]; then
        echo "Warning: JSON file not found: $json_file - skipping JSON copy for this file"
        continue
    fi
    json_out="${img_undistorted_out%${ext}}.json"
    cp "$json_file" "$json_out"

    # Update JSON file to reflect gradient nonlinearity correction
    if [[ -f "$json_out" ]]; then
        # Use jq to update the JSON file
        if jq '.NonlinearGradientCorrection = true | .NonlinearGradientCorrectionType = "3D"' "$json_out" > "$json_out.tmp" 2>/dev/null; then
            mv "$json_out.tmp" "$json_out"
            echo "    >>> Updated metadata of JSON file: $(basename "$json_out" .json)"
        else
            echo "Warning: Failed to update JSON file: $json_out"
            rm -f "$json_out.tmp"
        fi
    fi

done

# Remove the working directory if requested
if [[ "$delete_working_dir" == "true" ]]; then
    echo ">>> Removing working directory: $working_dir"
    rm -rf "$working_dir"
    ## TODO: Move deletion of the undistorted directory in a separate job called after all contrasts are finished
    rm -rf $undistorted_dir
else
    echo ">>> Working directory preserved: $working_dir"
    echo ">>> Moving the undistorted/ directory to the working directory"
    mv "$undistorted_dir" "$working_dir"
    echo "Done"
fi



echo "Processing complete."
