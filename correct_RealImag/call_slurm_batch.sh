#!/bin/bash


# Note: Removed 'set -e' to prevent premature exit during continue statements

usage() {
echo \
"
$(basename $0): Automatically finds and submits SLURM jobs for GNLC processing on all anat directories within a BIDS-like structure.
It makes use of the slurm_gnlc_proc.sh script to process each anat directory found.

USAGE:
    $(basename $0) [options] <scanner_name> <parent_directory>

OPTIONS:
    -h | --help: print help text and exit
    -o DIRECTORY | --output DIRECTORY: output directory for all results (optional)
                                      If specified, creates BIDS structure: output/sub-xxx/ses-xx/anat/
                                      If not specified, outputs directly to each anat directory in the input directory
    -w | --workingdir: use persistent working directories (not deleted after processing)
    -d | --delete-workdir: delete working directory after processing
    -p PATTERN | --pattern PATTERN: file pattern to match (optional, default: *_MPM.nii)
    -t SECONDS | --delay SECONDS: delay between job submissions in seconds (default: 3)
    -sub SUBJECTS | --subjects SUBJECTS: comma-separated list (no spaces!) of subjects to process (e.g., sub-001,sub-002)
    -ses SESSIONS | --sessions SESSIONS: comma-separated list (no spaces!) of sessions to process (e.g., ses-01,ses-02)
                                        Note: -ses requires -sub to be specified
    --dry-run: show commands that would be executed without actually submitting jobs

ARGUMENTS:
    scanner_name: Scanner/system name (Connectom, Prisma_fit, Skyra_fit, Verio, Magnetom7T, and Terra)
    parent_directory: Parent directory containing BIDS-structured data

DESCRIPTION:
    The script searches for directories matching the pattern: parent_directory/sub-*/ses-*/anat/
    and submits a SLURM job for each anat directory found. Working directories will be created
    automatically within the output directory for each session.
    
    If -sub is specified, only processes the specified subjects. If -ses is also specified,
    only processes the specified sessions for those subjects. Without these flags, processes
    all subjects and sessions found.
    
    If -o is specified: Creates BIDS structure in output directory (output/sub-xxx/ses-xx/anat/)
    If -o is not specified: Outputs directly to each input anat directory

EXAMPLES:
    $(basename $0) Terra /path/to/bids/dataset
    $(basename $0) -o /tmp/gnlc_results Terra /path/to/bids/dataset
    $(basename $0) -o /tmp/gnlc_results -w -p '*_magnitude.nii' -t 10 Prisma_fit /data/bids_root
    $(basename $0) -sub \"sub-001,sub-002\" Terra /path/to/bids/dataset
    $(basename $0) -sub \"sub-001\" -ses \"ses-01,ses-02\" -o /tmp/results Terra /path/to/bids/dataset
    $(basename $0) --dry-run -w -d Terra /path/to/dataset

AUTHOR:
    Niklas Kuegler (kuegler@cbs.mpg.de)
"
}



# Key Features:
# Error Checking: Validates that paths exist before submitting jobs
# Progress Tracking: Shows which path is being processed (e.g., "Processing path 2/5")
# Job Management: Includes delays between submissions to avoid overwhelming the scheduler
# Dry Run Mode: Test your commands before actually submitting
# Comprehensive Logging: Clear output showing what's happening
# Automatic Directory Creation: Creates the working directory if it doesn't exist

# Default parameters
output_dir=""
use_workingdir=false
delete_workdir=false
pattern=""
delay=3
dry_run=false
scanner_name=""
parent_dir=""
subjects=""
sessions=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--output)
            output_dir="$2"
            shift 2
            ;;
        -w|--workingdir)
            use_workingdir=true
            shift
            ;;
        -d|--delete-workdir)
            delete_workdir=true
            shift
            ;;
        -p|--pattern)
            pattern="$2"
            shift 2
            ;;
        -t|--delay)
            delay="$2"
            shift 2
            ;;
        -sub|--subjects)
            subjects="$2"
            shift 2
            ;;
        -ses|--sessions)
            sessions="$2"
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
            # Accept scanner_name first, then parent_directory
            if [[ -z "$scanner_name" ]]; then
                scanner_name="$1"
                shift
            elif [[ -z "$parent_dir" ]]; then
                parent_dir="$1"
                shift
            else
                echo "Error: Too many arguments specified"
                usage
                exit 1
            fi
            ;;
    esac
done

# Validation
if [[ -z "$scanner_name" ]]; then
    echo "Error: Scanner name must be specified"
    usage
    exit 1
fi

if [[ -z "$parent_dir" ]]; then
    echo "Error: Parent directory must be specified"
    usage
    exit 1
fi

if [[ ! -d "$parent_dir" ]]; then
    echo "Error: Parent directory does not exist: $parent_dir"
    exit 1
fi

# Validate sessions flag usage
if [[ -n "$sessions" && -z "$subjects" ]]; then
    echo "Error: -ses/--sessions flag requires -sub/--subjects to be specified"
    usage
    exit 1
fi

# Validate scanner name
valid_scanners=("Connectom" "Prisma_fit" "Skyra_fit" "Verio" "Magnetom7T" "Terra")
scanner_valid=false
for valid in "${valid_scanners[@]}"; do
    if [[ "$scanner_name" == "$valid" ]]; then
        scanner_valid=true
        break
    fi
done
if [[ "$scanner_valid" == "false" ]]; then
    echo "Error: Invalid scanner name '$scanner_name'. Must be one of: ${valid_scanners[*]}"
    exit 1
fi

# Convert comma-separated subjects and sessions to arrays if specified
if [[ -n "$subjects" ]]; then
    IFS=',' read -ra subject_array <<< "$subjects"
else
    subject_array=()
fi

if [[ -n "$sessions" ]]; then
    IFS=',' read -ra session_array <<< "$sessions"
else
    session_array=()
fi

# Find all anat directories in the BIDS-like structure
echo "Searching for anat directories in: $parent_dir"
if [[ ${#subject_array[@]} -gt 0 ]]; then
    echo "Filtering for subjects: ${subject_array[*]}"
    if [[ ${#session_array[@]} -gt 0 ]]; then
        echo "Filtering for sessions: ${session_array[*]}"
    fi
fi

anat_dirs=()

if [[ ${#subject_array[@]} -eq 0 ]]; then
    # No subject filter - find all anat directories
    while IFS= read -r -d '' anat_dir; do
        anat_dirs+=("$anat_dir")
    done < <(find "$parent_dir" -type d -path "*/sub-*/ses-*/anat" -print0 2>/dev/null)
else
    # Filter by specified subjects and optionally sessions
    for subject in "${subject_array[@]}"; do
        if [[ ${#session_array[@]} -eq 0 ]]; then
            # No session filter - find all sessions for this subject
            while IFS= read -r -d '' anat_dir; do
                anat_dirs+=("$anat_dir")
            done < <(find "$parent_dir" -type d -path "*/${subject}/ses-*/anat" -print0 2>/dev/null)
        else
            # Filter by specific sessions for this subject
            for session in "${session_array[@]}"; do
                while IFS= read -r -d '' anat_dir; do
                    anat_dirs+=("$anat_dir")
                done < <(find "$parent_dir" -type d -path "*/${subject}/${session}/anat" -print0 2>/dev/null)
            done
        fi
    done
fi

if [[ ${#anat_dirs[@]} -eq 0 ]]; then
    if [[ ${#subject_array[@]} -gt 0 ]]; then
        echo "Error: No anat directories found for specified subjects/sessions"
        echo "Subjects: ${subject_array[*]}"
        if [[ ${#session_array[@]} -gt 0 ]]; then
            echo "Sessions: ${session_array[*]}"
        fi
    else
        echo "Error: No anat directories found matching pattern: */sub-*/ses-*/anat"
    fi
    echo "Please check that the parent directory contains the expected BIDS-like structure"
    exit 1
fi

echo "Found ${#anat_dirs[@]} anat directories to process"
if [[ ${#subject_array[@]} -gt 0 ]]; then
    echo "Subjects filter: ${subject_array[*]}"
    if [[ ${#session_array[@]} -gt 0 ]]; then
        echo "Sessions filter: ${session_array[*]}"
    fi
fi

# Check if output directory exists, create if it doesn't (only if specified)
if [[ -n "$output_dir" && ! -d "$output_dir" ]]; then
    echo "Creating output directory: $output_dir"
    if [[ "$dry_run" == "false" ]]; then
        mkdir -p "$output_dir"
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
# echo "Output directory: $output_dir"
# echo "Use working directories: $use_workingdir"
# echo "File pattern: ${pattern:-*_MPM.nii (default)}"
# echo "Delay between submissions: ${delay}s"
# echo "Number of anat directories to process: ${#anat_dirs[@]}"
# echo "Dry run: $dry_run"
# echo "=========================================="

# Counter for job numbering
job_counter=1
skipped_sessions=0

# Cycle through each anat directory and submit SLURM job
for anat_path in "${anat_dirs[@]}"; do
    echo
    echo "Processing anat directory $job_counter/${#anat_dirs[@]}: $anat_path"
    
    # Extract subject and session from the path
    if [[ $anat_path =~ .*(sub-[^/]+)/(ses-[^/]+)/anat.* ]]; then
        subject="${BASH_REMATCH[1]}"
        session="${BASH_REMATCH[2]}"
        
        # Determine the target output directory based on whether -o flag is used
        if [[ -n "$output_dir" ]]; then
            # BIDS structure in specified output directory
            target_output_dir="$output_dir/$subject/$session/anat"
            session_workdir="$target_output_dir/wd"
        else
            # Direct output to the input anat directory
            target_output_dir="$anat_path"/dist_corr
            session_workdir="$target_output_dir/wd"
        fi
        
        # Check if results already exist (look for *desc-undistortedJac.nii files)
        existing_files=$(find "$target_output_dir" -name "*desc-undistortedJac.nii*" 2>/dev/null | wc -l || echo "0")
        if [[ $existing_files -gt 0 ]]; then
            echo "INFO: Found $existing_files existing output files in $target_output_dir. Skipping."
            ((skipped_sessions++))
            ((job_counter++))
            continue
        fi
    else
        echo "Error: Could not extract subject/session from path: $anat_path"
        echo "This SLURM script is designed to work with a BIDS structure (sub-*/ses-*/anat/)."
        echo "If you want to apply the correction to another session, you can run the runGNLC_re_im.sh script directly."
        exit 1
    fi
    
    # Build command arguments
    CMD_ARGS=""
    if [[ -n "$output_dir" ]]; then
        CMD_ARGS="$CMD_ARGS -o \"$target_output_dir\""
    fi
    if [[ "$use_workingdir" == "true" ]]; then
        CMD_ARGS="$CMD_ARGS -w \"$session_workdir\""
    fi
    if [[ "$delete_workdir" == "true" ]]; then
        CMD_ARGS="$CMD_ARGS -d"
    fi
    if [[ -n "$pattern" ]]; then
        CMD_ARGS="$CMD_ARGS -p \"$pattern\""
    fi
    
    # Prepare SLURM command
    slurm_cmd="sbatch -p short,group_servers,gr_weiskopf \"$slurm_script\" $CMD_ARGS \"$scanner_name\" \"$anat_path\""                

    # echo "Command: $slurm_cmd"
    
    if [[ "$dry_run" == "false" ]]; then
        # Submit the job
        out=$(eval $slurm_cmd)
        echo "$out"
        
        # Add delay between submissions (except for the last job)
        if [[ $job_counter -lt ${#anat_dirs[@]} ]]; then
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
echo "Total anat directories found: ${#anat_dirs[@]}"
echo "Sessions skipped (output already exists): $skipped_sessions"
echo "Sessions submitted: $((${#anat_dirs[@]} - skipped_sessions))"
if [[ "$dry_run" == "false" ]]; then
    echo "Check job status with: squeue -u \$USER"
    echo "Monitor logs in: $script_dir/logs/"
else
    echo "This was a dry run - no jobs were actually submitted"
fi
echo "=========================================="