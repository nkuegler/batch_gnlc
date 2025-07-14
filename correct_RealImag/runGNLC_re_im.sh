#!/bin/bash

set -e

usage() {
echo \
"
$(basename $0): Processes magnitude and phase image pairs using MagPhase_to_ReIm.sh.
Cycles through a parent directory to find matching magnitude and phase files.

USAGE:
	$(basename $0) [options] <scanner_name> <parent_directory>

INPUT:
    scanner_name: Scanner/system name (Connectom, Prisma_fit, Skyra_fit, Verio, Magnetom7T, and Terra)
    parent_directory: Parent directory containing magnitude and phase NIfTI files.

OPTIONS:
	-h | --help: print help text and exit
	-p PATTERN | --pattern PATTERN: file pattern to match (default: *_MPM.nii)
	-w DIRECTORY | --workingdir DIRECTORY: working directory for output files
	-d | --delete-workdir: delete working directory after processing (overrides default behavior)
	-o DIRECTORY | --output DIRECTORY: output directory for corrected magnitude files (default: <parent_directory>/corr_MagPh)

AUTHOR:
	Niklas Kuegler (kuegler@cbs.mpg.de)
"
}

# Default parameters
pattern="*_MPM.nii"
workingdir=""
output_dir=""
delete_workdir=false

# Give a hint if no arguments are provided
if [ $# -eq 0 ]; then
    echo "error: no arguments provided." >&2
    echo "try the \"-h\" option for information on how to use \"$(basename $0)\"." >&2
    exit 1
fi

# Read optional command line arguments
TEMP=$(getopt -o 'hp:w:o:d' --long 'help,pattern:,workingdir:,output:,delete-workdir' -n "$(basename $0)" -- "$@")
if [ $? -ne 0 ]; then
    echo "error: not all input arguments could be processed." >&2
    exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
    case "$1" in
        '-h'|'--help')
            usage
            exit 0
        ;;
        '-p'|'--pattern')
            pattern="$2"
            shift 2
            continue
        ;;
        '-w'|'--workingdir')
			# use a specified working directory which will not be deleted at the end of the calculation
			clearwd=false
			workingdir="$2"
			mkdir -p "$workingdir"
			echo working directory will be "$workingdir"
			shift 2
			continue
		;;
        '-d'|'--delete-workdir')
            delete_workdir=true
            shift
            continue
        ;;
        '-o'|'--output')
            output_dir="$2"
            shift 2
            continue
        ;;
        '--')
            shift
            break
        ;;
        *)
            echo "error parsing optional input arguments" >&2
            exit 1
        ;;
    esac
done

# Check for mandatory positional argument
if [ $# -lt 2 ]; then
    echo "error: expected scanner_name and parent_directory arguments." >&2
    echo "try the \"-h\" option for information on how to use \"$(basename $0)\"." >&2
    exit 1
fi

# Make a temporary working directory which will be deleted at the end of the calculation
if [ -z "$workingdir" ]; then
	clearwd=true
	workingdir=$(mktemp -d)
	echo working directory will be "$workingdir". It will be deleted at the end of the calculation.
    echo "-------"
fi

# Override clearwd if delete_workdir is true
if [ "$delete_workdir" = true ]; then
    clearwd=true
    echo "Working directory will be deleted after processing (forced by -d flag)"
fi

scanner_name="$1"
parent_directory="$2"
script_dir=$(dirname "$0")
re_im_creator="$script_dir/MagPhase_to_ReIm.sh"

# echo "Scanner: $scanner_name"

# Check if parent directory exists
if [ ! -d "$parent_directory" ]; then
    echo "Error: Parent directory '$parent_directory' does not exist" >&2
    exit 1
fi

# Check if MagPhase_to_ReIm.sh exists
if [ ! -f "$re_im_creator" ]; then
    echo "Error: MagPhase_to_ReIm.sh not found at '$re_im_creator'" >&2
    exit 1
fi


# Find all magnitude files
echo "----------"
echo ">>> Searching for magnitude files in: $parent_directory"
for mag_file in $(find "$parent_directory" -type f -name "*${pattern}*"); do
    if [[ "$(basename "$mag_file")" == *"part-mag"* ]]; then

        # Generate corresponding phase file name
        # If 'loraksRsos' in file name, the phase file will contain with 'loraks' instead
        if [[ "$(basename "$mag_file")" == *"loraksRsos"* ]]; then
            tmp_fname="${mag_file/loraksRsos/loraks}"
        else
            tmp_fname="$mag_file"
        fi

        phase_file="${tmp_fname/_part-mag/_part-phase}"
        
        if [ -f "$phase_file" ]; then
            echo "Processing pair:"
            echo "  Magnitude: $mag_file"
            echo "  Phase: $phase_file"
            
            # Run MagPhase_to_ReIm.sh to create real and imaginary images
            "$re_im_creator" -w "$workingdir" "$mag_file" "$phase_file"
            echo "---"
        else
            echo "Warning: No matching phase file found for $mag_file"
            echo "  Expected: $phase_file"
        fi
    fi
done

echo ">>> Real and Imag files created."
echo "----------"

####################

### run GNLC for MTw, PDw, T1w (real and imaginary images together) directly in workingdir
contrasts=("MTw" "PDw" "T1w")

# Parallelize GNLC jobs for each contrast
pids=()
files=()
error_files=()

echo ">>> Running GNLC for contrasts: ${contrasts[*]}"
echo "!!! The terminal output will be hold back until all jobs are finished !!!"

for contrast in "${contrasts[@]}"; do
    outfile=$(mktemp)
    errorfile=$(mktemp)
    files+=("$outfile")
    error_files+=("$errorfile")
    "$script_dir/gnlc_jac_MagPhase.sh" "$workingdir" "$workingdir/wd_$contrast" "$contrast" "$scanner_name" > "$outfile" 2> "$errorfile" & # redirect only stdout and stderr to temporary files
    pids+=($!)
done

# Wait for all background jobs to finish
for pid in "${pids[@]}"; do
    wait "$pid"
done

# Once done, output all results and check for errors. Remove temporary files.
for i in "${!files[@]}"; do
    echo "========="
    echo "stdout for job $((i+1)):"
    cat "${files[$i]}"
    
    # Check if there were any errors
    if [ -s "${error_files[$i]}" ]; then
        echo "stderr for job $((i+1)):"
        cat "${error_files[$i]}" >&2
    fi
    
    rm -f "${files[$i]}" "${error_files[$i]}"
done

echo
echo ">>> GNLC processing completed for all contrasts."
echo "----------"


echo ">>> Moving results to output directory."

# Determine output directory
if [ -z "$output_dir" ]; then
    output_dir="$parent_directory/corr_MagPh"
fi

mkdir -p "$output_dir"

# Move the result files to the output directory
echo "Moving magnitude and phase files to: $output_dir"
find "$workingdir/undistorted" -type f -name "*part-mag*desc-undistortedJac*.nii" -exec mv {} "$output_dir" \;
find "$workingdir/undistorted" -type f -name "*part-phase*desc-undistortedJac*.nii" -exec mv {} "$output_dir" \;


### TODO: better practice to keep the json with the nii file all the time
# Copy and rename corresponding JSON files
echo "Copying and renaming corresponding JSON files to: $output_dir"
find "$output_dir" -name "*desc-undistortedJac*.nii" -print0 | \
while IFS= read -r -d '' nii_file; do
    base="${nii_file%.nii}"
    # Try to find the original json file (before GNLC processing)
    # Remove _desc-undistortedJac, then add .json
    orig_base=$(basename "$nii_file")
    orig_base="${orig_base/_desc-undistortedJac/}"
    orig_base="${orig_base%.nii}"
    if [[ "$orig_base" == *"loraksRsos"* && "$orig_base" == *"phase"* ]]; then
        # during the processing, the phase names are changed from loraks to loraksRsos
        # to find the original json file, we need to account for this (and rename the json file while copying)
        orig_base="${orig_base/loraksRsos/loraks}"
    fi
    json_file=$(find "$parent_directory" -type f -name "${orig_base}.json" | head -n 1)
    if [[ -f "$json_file" ]]; then
        cp "$json_file" "${base}.json"
    fi
done

# Remove the temporary files
if $clearwd; then
    echo "Removing temporary files"
    rm -rf "$workingdir"
fi



echo "Done."