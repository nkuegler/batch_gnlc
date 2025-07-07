#!/usr/bin/env python3
"""
Batch Gradient Nonlinearity Correction (GNLC) Processing Script
This script automates the batch processing of MRI data for gradient nonlinearity correction (GNLC).
It scans a specified parent directory for subject subdirectories (starting with "sub-"), checks for
the presence of required anatomical files, ADJUSTS THEIR HEADERS to work around a bug in the
hMRI toolbox, and submits jobs to a SLURM cluster for GNLC processing.
Main Steps:
- Ensures the output directory structure exists.
- Iterates over all subject directories and checks for the required files: R2smap, R1map, MTsat, PDmap.
- For each required file, calls an external script to adjust the NIfTI header. 
    WARNING: This script calls another script to adjust the headers of each file to make Gradient nonlinearity correction work. 
    This is due to a bug in the hMRI toolbox and will be adjusted as soon as the bug is fixed.
- If all headers are successfully modified, submits a GNLC job to the SLURM cluster using a specified sbatch script.
Arguments, paths, and required scripts are hardcoded at the top of the script.
Usage:
        Run this script directly. It will process all eligible subject directories in the specified parent directory.
"""

from pathlib import Path
import subprocess

parent_dir = '/data/p_03002/data/bids/derivatives/LORAKS_mpm'
gnlc_script = '/data/u_kuegler_software/git/gradient-nonlinearity-correction-scripts/runCorrection.sh'

output_parent_dir = '/data/p_03002/data/bids/derivatives/LORAKS_mpm_gnlc'

sbatch_script = '/data/u_kuegler_software/git/batch_gnlc/gnlc_slurm.sh'
mod_hdr_script = '/data/u_kuegler_software/git/batch_gnlc/qform_sform_adjust.sh'



print("""
WARNING: 
This script calls another script to adjust the headers of each file to make Gradient nonlinearity correction work.
This is due to a bug in the hMRI toolbox and will be adjusted as soon as the bug is fixed.
""")


# Create the output parent directory if it does not exist
output_parent_path = Path(output_parent_dir)
output_parent_path.mkdir(parents=True, exist_ok=True)

# Get all subdirectories starting with "sub-"
parent_path = Path(parent_dir)
output_parent_path = Path(output_parent_dir)

def sbatch_commands():
    print("directories to be processed:")
    for item in parent_path.iterdir():
        if item.is_dir() and item.name.startswith('sub-'):
            print(item)
    print("-" * 20)

    for item in parent_path.iterdir():
        if item.is_dir() and item.name.startswith('sub-'):
            
            # Check if the directory there is a parent_dir/sub-*/ses-01/anat directory
            input_dir = item / 'ses-01' / 'anat'
            if input_dir.exists():
                # Create corresponding directory structure in output
                output_dir = output_parent_path / item.name / 'ses-01' / 'anat'
                output_dir.mkdir(parents=True, exist_ok=True)
                # Create working_dir in each output_dir
                working_dir = output_dir / 'working_dir'
                working_dir.mkdir(parents=True, exist_ok=True)

                # Check for required files
                required_endings = ['R2smap', 'R1map', 'MTsat', 'PDmap']
                prefix = f"{item.name}_ses-01_"
                
                header_mod_success = True
                for ending in required_endings:
                    expected_file = input_dir / f"{prefix}{ending}.nii"
                    if not expected_file.exists():
                        print(f"WARNING: Missing file {expected_file}")

                    # Adjust the header of each file as there is 
                    # a bug in the hMRI toolbox when using sensitivtiy maps
                    result = subprocess.run([mod_hdr_script, str(expected_file)])
                    if result.returncode != 0:
                        header_mod_success = False
                        break

                # Only submit job if header modifications were successful
                if header_mod_success:
                    # Submit the GNLC script to the slurm cluster

                    cmd = ["sbatch", "-p", "short,group_servers,gr_weiskopf", 
                            str(sbatch_script), str(input_dir / "hdr_mod"), str(working_dir), prefix, str(output_dir)]
                    
                    # print(f"Submitting job with command: {' '.join(cmd)}")
                    result = subprocess.run(cmd)
                else:
                    print(f"ERROR: Header modification failed for subject {item.name}. Skipping job submission.")
                

if __name__ == "__main__":
    sbatch_commands()