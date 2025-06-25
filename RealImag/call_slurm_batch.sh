#!/bin/bash

# Script to cycle through a list of paths and submit SLURM jobs
# using the slurm_gnlc_proc.sh script

set -e

usage() {
echo \
"
$(basename $0): Cycles through specified paths and submits SLURM jobs for GNLC processing.

USAGE:
    $(basename $0) [options] <path1> <path2> <path3> ...

OPTIONS:
    -h | --help: print help text and exit
    -w DIRECTORY | --workingdir DIRECTORY: working directory for output files
    -p PATTERN | --pattern PATTERN: file pattern to match (optional, default: *_MPM.nii)
    -d SECONDS | --delay SECONDS: delay between job submissions in seconds (default: 5)
    --dry-run: show commands that would be executed without actually submitting jobs

EXAMPLES:
    $(basename $0) -w /tmp/gnlc_work /path/to/data1 /path/to/data2 /path/to/data3
    $(basename $0) -w /tmp/gnlc_work -p '*_magnitude.nii' -d 10 /data/subject1 /data/subject2
    $(basename $0) --dry-run -w /tmp/gnlc_work /path/to/data1 /path/to/data2

AUTHOR:
    Niklas Kuegler (kuegler@cbs.mpg.de)
"
}


# TODO: currently the same working directory is used for all input paths

# Default parameters
working_dir=""
pattern=""
delay=5
dry_run=false
paths=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -w|--workingdir)
            working_dir="$2"
            shift 2
            ;;
        -p|--pattern)
            pattern="$2"
            shift 2
            ;;
        -d|--delay)
            delay="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1"
            usage
            exit 1
            ;;
        *)
            # Collect all remaining arguments as paths
            paths+=("$1")
            shift
            ;;
    esac
done

# Validation
if [[ -z "$working_dir" ]]; then
    echo "Error: Working directory (-w) is required"
    usage
    exit 1
fi

if [[ ${#paths[@]} -eq 0 ]]; then
    echo "Error: At least one input path must be specified"
    usage
    exit 1
fi

# Check if working directory exists, create if it doesn't
if [[ ! -d "$working_dir" ]]; then
    echo "Creating working directory: $working_dir"
    if [[ "$dry_run" == "false" ]]; then
        mkdir -p "$working_dir"
    fi
fi

# Get the absolute path of the slurm script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slurm_script="$script_dir/slurm_gnlc_proc.sh"

if [[ ! -f "$slurm_script" ]]; then
    echo "Error: SLURM script not found at $slurm_script"
    exit 1
fi

echo "=========================================="
# echo "GNLC Batch Job Submission"
# echo "=========================================="
# echo "Working directory: $working_dir"
# echo "File pattern: ${pattern:-*_MPM.nii (default)}"
# echo "Delay between submissions: ${delay}s"
# echo "Number of paths to process: ${#paths[@]}"
# echo "Dry run: $dry_run"
# echo "=========================================="

# Counter for job numbering
job_counter=1

# Cycle through each path and submit SLURM job
for input_path in "${paths[@]}"; do
    echo
    echo "Processing path $job_counter/${#paths[@]}: $input_path"
    
    # Check if input path exists
    if [[ ! -d "$input_path" ]]; then
        echo "Warning: Input path does not exist: $input_path"
        echo "Skipping..."
        ((job_counter++))
        continue
    fi
    
    # Build command arguments
    CMD_ARGS=""
    if [[ -n "$working_dir" ]]; then
        CMD_ARGS="$CMD_ARGS -w \"$working_dir\""
    fi
    if [[ -n "$pattern" ]]; then
        CMD_ARGS="$CMD_ARGS -p \"$pattern\""
    fi
    
    # Prepare SLURM command
    slurm_cmd="sbatch \"$slurm_script\" $CMD_ARGS \"$input_path\""
    
    # echo "Command: $slurm_cmd"
    
    if [[ "$dry_run" == "false" ]]; then
        # Submit the job
        out=$(eval $slurm_cmd)
        echo "$out"
        
        # Add delay between submissions (except for the last job)
        if [[ $job_counter -lt ${#paths[@]} ]]; then
            echo "Waiting ${delay}s before next submission..."
            sleep "$delay"
        fi
    else
        echo "DRY RUN: Would submit job"
    fi
    
    ((job_counter++))
done

echo
echo "=========================================="
echo "Batch submission completed!"
echo "Total paths processed: ${#paths[@]}"
if [[ "$dry_run" == "false" ]]; then
    echo "Check job status with: squeue -u \$USER"
    echo "Monitor logs in: $script_dir/logs/"
else
    echo "This was a dry run - no jobs were actually submitted"
fi
echo "=========================================="