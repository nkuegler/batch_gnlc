#!/bin/bash

#
#SBATCH -c 16					# 16 cores
#SBATCH --mem 64G				# estimated 64G RAM
#SBATCH --time 150				# estimated 100 minutes maximum
#SBATCH -o /data/u_kuegler_software/git/batch_gnlc/correct_RealImag/logs/%j.out	# redirect the output
#
# Real time consumption for (16 cores, 64G request) are about ....

# Parse optional arguments
WORKING_DIR=""
PATTERN=""
OUTPUT_DIR=""

while getopts "w:p:o:" opt; do
    case $opt in
        w)
            WORKING_DIR="$OPTARG"
            ;;
        p)
            PATTERN="$OPTARG"
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Shift to get the remaining positional argument
shift $((OPTIND-1))

# INPUT_DIR is the required positional argument
INPUT_DIR=$1

if [ -z "$INPUT_DIR" ]; then
    echo "Error: INPUT_DIR is required"
    echo "Usage: $0 [-w WORKING_DIR] [-p PATTERN] -o OUTPUT_DIR INPUT_DIR"
    exit 1
fi

if [ -z "$OUTPUT_DIR" ]; then
    echo "Error: OUTPUT_DIR (-o) is required"
    echo "Usage: $0 [-w WORKING_DIR] [-p PATTERN] -o OUTPUT_DIR INPUT_DIR"
    exit 1
fi

# Output directory specified - create if needed
# Extract subject and session from INPUT_DIR for session-specific output
if [[ $INPUT_DIR =~ .*(sub-[^/]+)/(ses-[^/]+)/anat.* ]]; then
    SUBJECT="${BASH_REMATCH[1]}"
    SESSION="${BASH_REMATCH[2]}"
    echo "Using BIDS structure: $SUBJECT/$SESSION/anat"
else
    echo "Warning: Could not extract subject/session from path: $INPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
echo "Using output directory: $OUTPUT_DIR"

source ~/bash.conda
conda activate grad_unwarp

# Build command arguments
CMD_ARGS=""
if [ -n "$PATTERN" ]; then
    CMD_ARGS="$CMD_ARGS -p \"$PATTERN\""
fi
if [ -n "$WORKING_DIR" ]; then
    CMD_ARGS="$CMD_ARGS -w \"$WORKING_DIR\""
fi
# Always pass the determined output directory to runGNLC_re_im.sh
CMD_ARGS="$CMD_ARGS -o \"$OUTPUT_DIR\""

# Execute the command
# use eval instead of ./ for dynamic command construction
eval "./runGNLC_re_im.sh $CMD_ARGS \"$INPUT_DIR\""