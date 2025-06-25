#!/bin/bash

#
#SBATCH -c 16					# 16 cores
#SBATCH --mem 64G				# estimated 64G RAM
#SBATCH --time 150				# estimated 100 minutes maximum
#SBATCH -o /data/u_kuegler_software/git/batch_gnlc/RealImag/logs/%j.out	# redirect the output
#
# Real time consumption for (16 cores, 64G request) are about ....

# Parse optional arguments
WORKING_DIR=""
PATTERN=""

while getopts "w:p:" opt; do
    case $opt in
        w)
            WORKING_DIR="$OPTARG"
            ;;
        p)
            PATTERN="$OPTARG"
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
    echo "Usage: $0 [-w WORKING_DIR] [-p PATTERN] INPUT_DIR"
    exit 1
fi

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

# Execute the command
# use eval instead of ./ for dynamic command construction
eval "./runGNLC_re_im.sh $CMD_ARGS \"$INPUT_DIR\""