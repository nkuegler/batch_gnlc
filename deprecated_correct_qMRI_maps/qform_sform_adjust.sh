#!/bin/bash

FSL_VERSION=6.0.7.11 

# Check if a path argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <path_to_file>"
    exit 1
fi

input_path="$1"

# Change to the directory where the input file is located
cd "$(dirname "$input_path")" || { echo "Failed to change directory"; exit 1; }


# Check if file exists
if [ ! -f "$input_path" ]; then
    echo "Error: File '$input_path' does not exist"
    exit 1
fi

# Check if file has .nii or .nii.gz extension
if [[ "$input_path" =~ \.nii(\.gz)?$ ]]; then
    # Extract header information
    sform_code=$(FSL --version $FSL_VERSION fslorient -getsformcode "$input_path")
    qform_code=$(FSL --version $FSL_VERSION fslorient -getqformcode "$input_path")


    # Check if all conditions match
    if [ "$sform_code" -eq 2 ] && [ "$qform_code" -eq 2 ]; then
        # 2 stands for "Aligned Anat", while 1 stands for "Scanner Anat"
        
        # Create temp directory in the working directory if it doesn't exist
        mkdir -p hdr_mod
        
        mod_input="hdr_mod/$(basename "${input_path%.*}")_hdrMod.${input_path##*.}"

        echo "Copying $(basename "${input_path}") to hdr_mod directory"
        cp "$input_path" "$mod_input"
        
        FSL --version $FSL_VERSION fslorient -setsformcode 1 "$mod_input"
        FSL --version $FSL_VERSION fslorient -setqformcode 1 "$mod_input"

    else
        echo "Header not modified for $input_path"
        exit 2
    fi
else
    echo "No .nii or .nii.gz extension in $input_path"
    exit 3
fi

exit 0
