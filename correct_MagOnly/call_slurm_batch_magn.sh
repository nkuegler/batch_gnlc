#!/bin/bash

# Script to cycle through a BIDS-like structure and submit SLURM jobs for magnitude-only GNLC processing

# Note: Removed 'set -e' to prevent premature exit during continue statements

usage() {
echo \
"
$(basename $0): Automatically finds and submits SLURM jobs for magnitude-only GNLC processing on all anat directories within a BIDS-like structure.

USAGE:
    $(basename $0) [options] <scanner_name> <parent_directory> <output_directory>

OPTIONS:
    -h | --help: print help text and exit
    -c CONTRASTS | --contrasts CONTRASTS: comma-separated list (no spaces!) of contrasts to process (default: PDw,T1w,MTw)
    -p PATTERN | --pattern PATTERN: file pattern suffix to match (default: mag*_MPM)
    -t SECONDS | --delay SECONDS: delay between job submissions in seconds (default: 1)
    -sub SUBJECTS | --subjects SUBJECTS: comma-separated list (no spaces!) of subjects to process (e.g., sub-001,sub-002)
    -ses SESSIONS | --sessions SESSIONS: comma-separated list (no spaces!) of sessions to process (e.g., ses-01,ses-02)
                                        Note: -ses requires -sub to be specified
    --nj | --no-jacobian: skip jacobian intensity correction (set this flag when correcting quantitative maps)
    --d | --delete-workdir: delete working directories after processing
    --dry-run: show commands that would be executed without actually submitting jobs

ARGUMENTS:
    scanner_name: Scanner/system name (Connectom, Prisma_fit, Skyra_fit, Verio, Magnetom7T, Terra, etc.)
    parent_directory: Parent directory containing BIDS-structured data
    output_directory: Output directory for processed results

DESCRIPTION:
    The script searches for directories matching the pattern: parent_directory/sub-*/ses-*/anat/
    and submits a SLURM job for each contrast in each anat directory found. For each contrast,
    it creates a separate working directory and processes all files matching the pattern.
    
    If -sub is specified, only processes the specified subjects. If -ses is also specified,
    only processes the specified sessions for those subjects. Without these flags, processes
    all subjects and sessions found.

    The script supports multiple contrasts and the jobs for the contrasts for each session run sequentially.
    
    Creates BIDS structure in output directory: output/sub-xxx/ses-xx/anat/

EXAMPLES:
    $(basename $0) Prisma /data/input /data/output
    $(basename $0) -c \"PDw,T1w\" -p \"_magnitude\" Terra /data/input /data/output
    $(basename $0) -sub \"sub-001,sub-002\" Prisma /data/input /data/output
    $(basename $0) -sub \"sub-001\" -ses \"ses-01,ses-02\" Terra /data/input /data/output
    $(basename $0) --dry-run -t 10 Prisma_fit /data/input /data/output

AUTHOR:
    Niklas Kuegler (kuegler@cbs.mpg.de)
"
}

# Default parameters
contrasts="PDw,T1w,MTw"
pattern="mag*_MPM"
delay=1
dry_run=false
no_jacobian=false
delete_workdir=false
scanner_name=""
parent_dir=""
output_dir=""
subjects=""
sessions=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--contrasts)
            contrasts="$2"
            shift 2
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
        --nj|--no-jacobian)
            no_jacobian=true
            shift
            ;;
        --d|--delete-workdir)
            delete_workdir=true
            shift
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
            # Accept scanner_name, parent_directory, then output_directory
            if [[ -z "$scanner_name" ]]; then
                scanner_name="$1"
                shift
            elif [[ -z "$parent_dir" ]]; then
                parent_dir="$1"
                shift
            elif [[ -z "$output_dir" ]]; then
                output_dir="$1"
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

if [[ -z "$output_dir" ]]; then
    echo "Error: Output directory must be specified"
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

# Convert comma-separated contrasts to array
IFS=',' read -ra contrast_array <<< "$contrasts"

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

# Create output directory if it doesn't exist
if [[ ! -d "$output_dir" ]]; then
    echo "Creating output directory: $output_dir"
    if [[ "$dry_run" == "false" ]]; then
        mkdir -p "$output_dir"
    fi
fi

# Get the absolute path of the slurm script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
slurm_script="$script_dir/gnlc_slurm_mag.sh"

if [[ ! -f "$slurm_script" ]]; then
    echo "Error: SLURM script not found at $slurm_script"
    exit 1
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
echo "Contrasts to process: ${contrast_array[*]}"
echo "Pattern: ${pattern}"
echo "Scanner: ${scanner_name}"
echo "Jacobian correction: $(if [[ "$no_jacobian" == "true" ]]; then echo "DISABLED"; else echo "ENABLED"; fi)"
echo "Working directory cleanup: $(if [[ "$delete_workdir" == "true" ]]; then echo "ENABLED"; else echo "DISABLED"; fi)"
if [[ ${#subject_array[@]} -gt 0 ]]; then
    echo "Subjects filter: ${subject_array[*]}"
    if [[ ${#session_array[@]} -gt 0 ]]; then
        echo "Sessions filter: ${session_array[*]}"
    fi
fi

echo "=========================================="
echo "Directories to be processed:"
for anat_path in "${anat_dirs[@]}"; do
    if [[ $anat_path =~ .*(sub-[^/]+)/(ses-[^/]+)/anat.* ]]; then
        subject="${BASH_REMATCH[1]}"
        session="${BASH_REMATCH[2]}"
        echo "${subject}/${session}/anat"
    fi
done
echo "=========================================="

# Counter for job numbering
job_counter=1
total_jobs=0
skipped_jobs=0

# Array to track job dependencies per subject/session
declare -A session_last_job_id

# Calculate total number of jobs
for anat_path in "${anat_dirs[@]}"; do
    total_jobs=$((total_jobs + ${#contrast_array[@]}))
done

# Cycle through each anat directory and submit SLURM jobs
for anat_path in "${anat_dirs[@]}"; do
    echo
    echo "Processing anat directory: $anat_path"
    
    # Extract subject and session from the path
    if [[ $anat_path =~ .*(sub-[^/]+)/(ses-[^/]+)/anat.* ]]; then
        subject="${BASH_REMATCH[1]}"
        session="${BASH_REMATCH[2]}"
        
        # Create corresponding directory structure in output
        target_output_dir="$output_dir/$subject/$session/anat"
        if [[ "$dry_run" == "false" ]]; then
            mkdir -p "$target_output_dir"
        fi
        
        # Process each contrast
        for contrast in "${contrast_array[@]}"; do
            echo "  Processing contrast: $contrast (Job $job_counter/$total_jobs)"
            
            # Build pattern for this contrast
            file_pattern="${contrast}*${pattern}"

            # Check if files matching the pattern exist
            files_found=$(find "$anat_path" -maxdepth 1 -type f -name "*$file_pattern*" 2>/dev/null | wc -l)
            if [[ $files_found -eq 0 ]]; then
                echo "    WARNING: No files containing pattern '$file_pattern' found in $anat_path. Skipping."
                ((skipped_jobs++))
                ((job_counter++))
                continue
            fi

            echo "    Found $files_found files containing pattern '$file_pattern'"

            # Check if output files already exist for this contrast
            existing_output=$(find "$target_output_dir" -maxdepth 1 -type f -name "*${contrast}*" 2>/dev/null | wc -l)
            if [[ $existing_output -gt 0 ]]; then
                echo "    INFO: Output files for contrast '$contrast' already exist in $target_output_dir. Skipping."
                ((skipped_jobs++))
                ((job_counter++))
                continue
            fi

            # Create working directory for each contrast
            working_dir_contrast="$target_output_dir/wd_$contrast"
            if [[ "$dry_run" == "false" ]]; then
                mkdir -p "$working_dir_contrast"
            fi
            
            # Create unique session identifier for dependency tracking
            session_id="${subject}_${session}"
            
            # Prepare SLURM command with dependency if there's a previous job for this session
            dependency_option=""
            if [[ -n "${session_last_job_id[$session_id]}" ]]; then
                dependency_option="--dependency=afterany:${session_last_job_id[$session_id]}"
            fi
            
            slurm_cmd="sbatch -p short,group_servers,gr_weiskopf $dependency_option \"$slurm_script\" \"$anat_path\" \"$working_dir_contrast\" \"$file_pattern\" \"$scanner_name\" \"$target_output_dir\" \"$no_jacobian\" \"$delete_workdir\""


            if [[ "$dry_run" == "false" ]]; then
                # Submit the job and capture job ID
                out=$(eval $slurm_cmd)
                echo "    $out"
                
                # Extract job ID from sbatch output (format: "Submitted batch job JOBID")
                if [[ $out =~ Submitted\ batch\ job\ ([0-9]+) ]]; then
                    job_id="${BASH_REMATCH[1]}"
                    if [[ -n "$dependency_option" ]]; then
                        echo "    Job $job_id submitted with dependency on ${session_last_job_id[$session_id]}"
                    else
                        echo "    Job $job_id submitted (first job for $session_id)"
                    fi
                    # Update the last job ID for this session
                    session_last_job_id[$session_id]="$job_id"
                else
                    echo "    Warning: Could not extract job ID from sbatch output"
                fi
                
                # Add delay between submissions (except for the last job)
                if [[ $job_counter -lt $total_jobs ]]; then
                    echo "    Waiting ${delay}s before next submission..."
                    sleep "$delay"
                fi
            else
                echo "    DRY RUN: Would submit job with command: $slurm_cmd"
                if [[ -n "$dependency_option" ]]; then
                    echo "    DRY RUN: Job would depend on previous job for session $session_id"
                else
                    echo "    DRY RUN: First job for session $session_id (no dependency)"
                fi
                # For dry run, simulate job ID
                session_last_job_id[$session_id]="FAKE_JOB_ID_$job_counter"
            fi
            
            ((job_counter++))
        done
    else
        echo "Warning: Could not extract subject/session from path: $anat_path"
        echo "Skipping this directory..."
        skipped_jobs=$((skipped_jobs + ${#contrast_array[@]}))
        continue
    fi
done

echo
echo "=========================================="
echo "Batch submission completed!"
echo "Total jobs expected: $total_jobs"
echo "Jobs skipped (no matching files or output exists): $skipped_jobs"
echo "Jobs submitted: $((total_jobs - skipped_jobs))"
echo "Job dependencies: Contrasts for each session run sequentially"
if [[ "$dry_run" == "false" ]]; then
    echo "Check job status with: squeue -u \$USER"
    echo "Monitor logs in: $script_dir/logs/"
else
    echo "This was a dry run - no jobs were actually submitted"
fi
echo "=========================================="
