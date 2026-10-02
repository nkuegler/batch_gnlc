# batch_gnlc

Batch processing scripts for gradient nonlinearity correction (GNLC) on MRI data using SLURM clusters.

## Installation

1. Clone required repositories:
```bash
git clone --recurse-submodules git@gitlab.gwdg.de:cbs-neurophy/gradient-nonlinearity-correction-scripts.git
# will automatically clone subrepository git@github.com:Washington-University/gradunwarp.git at commit ac8dbe1c

### Alternative: clone gradunwarp from the original repository
git clone git@github.com:Washington-University/gradunwarp.git
```

2. Create conda environment:
```bash
### Option 1: clone from Luke's Gitlab repository
cd gradient-nonlinearity-correction-scripts
conda create -n grad_unwarp python=3.11
conda activate grad_unwarp

# if you cloned the Gitlab repository including the submodule
cd gradunwarp.source
git checkout master # important, as the linked branch does not contain a pyproject.toml
# if you cloned the original gradunwarp repository separately
cd /path/to/gradunwarp

pip install -r requirements.txt
pip install -e . 
cd ..
```

> [!CAUTION] 
> Common mistake: When using the Gitlab version, make sure to check out the `master` branch of the `gradunwarp` repository! The `gradient-nonlinearity-correction-scripts` repository clones a specific commit (`ac8dbe1c`), which is deprecated. This will fail when running `pip install -e .` as the pyproject.toml is missing in this status of the repository.


3. Configure paths in `config.sh` to match your system:
   - `CONFIG_REPO_DIR` - Path to this repository
   - `CONFIG_GRAD_NONL_CORR_SCRIPTS` - Path to gradient-nonlinearity-correction-scripts
   - `CONFIG_MAG_ONLY_SLURM_LOG_DIR` - Log directory for magnitude-only GNLC jobs
   - `CONFIG_REAL_IMAG_SLURM_LOG_DIR` - Log directory for real/imaginary GNLC jobs

4. Ensure required tools are available: FSL, SLURM, MRtrix3, jq 
   *(Container usage is implemented yet) (see [Todo section](#todo))*


## Workflow Selection

Choose the appropriate workflow based on your data type:

- **correct_RealImag** - If both magnitude and phase data is available.
- **correct_MagOnly** - If only magnitude images are available.

## How to Run

### correct_RealImag (Magnitude + Phase)

Main entry point: `correct_RealImag/call_slurm_batch.sh`

> [!NOTE] 
> If you want to process the GNLC locally (not as batch job on the SLURM cluster), `runGNLC_re_im.sh` should work as a stand-alone. Please check the documentation within the script.

**Basic usage:**
```bash
./correct_RealImag/call_slurm_batch.sh <scanner_name> <parent_directory>
```

**Key options:**
- `-o DIRECTORY` - Output directory for results (creates BIDS structure)
- `-p PATTERN` - File pattern to match (default: `*_MPM.nii`)
- `-w` - Use persistent working directories
- `-d` - Delete working directories after processing
- `-sub SUBJECTS` - Comma-separated list of subjects (e.g., `sub-001,sub-002`)
- `-ses SESSIONS` - Comma-separated list of sessions (requires `-sub`)
- `--debug-mode` - Show terminal output immediately
- `--dry-run` - Show commands without submitting jobs

- The flag `-w` specifies that a working directory is created inside each session folder in the output directory. If it is not set, the script creates temporary directories in `/tmp`.
   - If `-w` is set, the working directory will not be deleted at the end of the processing unless the `-d` flag is also set. 
   - The working directory in `/tmp` will always be deleted at the end.

**Example:**
```bash
./correct_RealImag/call_slurm_batch.sh -o /path/to/output -p "*loraksRsos*_MPM.nii" Terra /data/bids_dataset
```

### correct_MagOnly (Magnitude Only)

Main entry point: `correct_MagOnly/call_slurm_batch_magn.sh`

> [!NOTE] 
> If you want to process the GNLC locally (not as batch job on the SLURM cluster), please `gnlc_slurm_mag.sh` should work as a stand-alone. Please check the documentation within the script.

**Basic usage:**
```bash
./correct_MagOnly/call_slurm_batch_magn.sh <scanner_name> <parent_directory> <output_directory>
```

**Key options:**
- `-c CONTRASTS` - Comma-separated list of contrasts (default: `PDw,T1w,MTw`)
- `-p PATTERN` - File pattern suffix to match (default: `mag*_MPM`)
- `--nj` / `--no-jacobian` - Skip jacobian intensity correction (for quantitative maps)
- `--d` / `--delete-workdir` - Delete working directories after processing
- `-sub SUBJECTS` - Comma-separated list of subjects
- `-ses SESSIONS` - Comma-separated list of sessions (requires `-sub`)
- `-dep JOBID` - Submit jobs with dependency on another job
- `--dry-run` - Show commands without submitting jobs

**Example:**
```bash
./correct_MagOnly/call_slurm_batch_magn.sh -c "PDw,T1w" Prisma_fit /data/input /data/output
```

## Data Flow

> [!IMPORTANT] 
> There are important differences between the two workflows. Please check the section [Differences between the workflows](#differences-between-the-two-workflows).

> [!NOTE] 
> Before processing a batch of NIfTI files, each corresponding JSON file is checked. The correction is aborted if `NonlinearGradientCorrection: true` in the corresponding JSON.

### correct_RealImag Workflow

1. **Input Discovery** - Scans for magnitude and phase image pairs matching pattern
2. **Complex Conversion** - Converts magnitude/phase → complex → real/imaginary components
3. **GNLC Processing** - Applies gradient nonlinearity correction to real and imaginary parts
4. **Jacobian Correction** - Applies intensity adjustment using warp jacobian
5. **Reconstruction** - Converts corrected components back to magnitude and phase
6. **Output** - Moves corrected files and updates JSON metadata (BIDS structure in output)

#### File explanation
- `call_slurm_batch.sh` = loop through multiple input paths and submit slurm jobs
- `slurm_gnlc_proc.sh` = submitted slurm script
- `runGNLC_re_im.sh` = main script
- `MagPhase_to_ReIm.sh` = conversion to real and imaginary parts
- `gnlc_jac_MagPhase` = run GNLC, do jacobian correction, conversion back to Mag and Phase

### correct_MagOnly Workflow

1. **BIDS Structure Discovery** - Matches pattern: `parent_dir/sub-*/ses-*/anat/`
2. **Per-Contrast Processing** - Submits SLURM jobs for each contrast
3. **GNLC Processing** - Applies gradient nonlinearity correction to magnitude images
4. **Jacobian Correction** (optional) - Applies intensity adjustment using warp jacobian
5. **File Organization** - Renames files and updates JSON metadata (BIDS structure in output)

#### File explanation
- `call_slurm_batch_magn.sh` - loop trought input directory and submit SLURM jobs for magnitude-only GNLC processing
- `gnlc_slurm_mag.sh` - Applies gradient nonlinearity correction to magnitude images, including Jacobian correction (optional), and updates the JSON files

### Differences between the two workflows

- The two available processing workflows are not structured in the same way due to the more complex processing in the Real/Imag version and different times of development. The command line options are **not** identical. Please check the documentation in `call_slurm_batch.sh` and `call_slurm_batch_magn.sh`. You can also check the help message of the scripts by calling them with the `-h` flag.
- `correct_RealImag` uses pid to parallelize the processes (submit one slurm job that runs three parallel tasks, one for each contrast) (see `runGNLC_re_im.sh`). `correct_MagOnly` submits one SLURM job per contrast. However, to not accidentally deleting the working directories before all the jobs are finished, the specified contrasts run as sequential SLURM jobs (see `call_slurm_batch_magn.sh`). Both approaches are not ideal. The best implementation would be parallel jobs with deletion of the working directory after all three are finished.
- Mag-only workflow contains some additional arguments (mostly to account for specific needs of the R2 processing pipeline): `-dep -job-name -log`

## Configuration

### Required Data Structure

Organize your data in BIDS-like format:
```
parent_directory/
├── sub-001/
│   └── ses-01/
│       └── anat/
│           ├── *part-mag*_MPM.nii
│           └── *part-phase*_MPM.nii
├── sub-002/
│   └── ses-01/
│       └── anat/
```

### Supported Scanner Systems

> [!WARNING] 
> The gradient coefficient files (`{name}.grad`) are not provided within the repository as they should be treated confidentially. Please contact your MR physicist or Scanner vendor!

- Connectom
- Prisma_fit
- Skyra_fit
- Verio
- Magnetom7T
- Terra

## Output

Both workflows produce corrected NIfTI files (unzipped, .nii) with updated JSON metadata:
- Files tagged with `desc-undistortedJac` (if jacobian correction applied)
- JSON files updated with `NonlinearGradientCorrection: true`
- Default output location: `parent_directory/corr_MagPh/` or specified output directory

Output maintains BIDS structure with subject/session organization when using the `-o` flag.



# ToDos
- container usage not implemented yet (does the container include all necessary tools? I guess Mrtrix3 is missing)
- config export system variables which is not the how it should be done -> rather use a json and use jq to extract the variable if necessary

- correct_MagOnly: Move deletion of the undistorted directory in a separate job called after all contrasts are finished (then the jobs for the different contrasts can run in parallel) -> see [Differences between the two workflows](#differences-between-the-two-workflows)
- for GNLC of AFI and SMAP acquisitions, you can use the scripts in the correct_MagOnly directory. However, the script only looks for files in the `anat/` directory. This must be adjusted from anat to fmap when used for sensitivity maps → maybe use a flag in the script or implement in a different way
- container usage needs to be implemented for ReIm correction (container as optional argument and replace `FSL ...` command with just the fsl function calls as in MagOnly)
- implement flag to run for ernst slabs instead of manually changing the runGNLC_re_im.sh script
- harmonize the options of the two workflows (RealImag, Mag-only)
- The implementation of checking the JSON file for the `NonlinearGradientCorrection` key is better in the MagOnly correction. Maybe adjust RealImag in a similar way (would need quite a bit of adjustment of the processing structure).


# Additional Hints

## Containerization does not work at the moment
- commented out for now!
- container path as optional argument (for now only in MagOnly correction) -> if specified, the whole SLURM job runs in the container
    - if not, the script runs on the CBS infrastructure with the usual software environments (`FSL --version VERSION` environment as the singularity wrapper `SCWRAP fsl VERSION` does initialize on the SLURM cluster)
- `grad_unwarp` conda env must be created and initialized correctly in the container
    - instead of activating the `mri_tools_env`, for the GNLC, we need to activate the `grad_unwarp` env, combine them, or create a separate container
    - avoid hard-coded environment name
- additionally, the script path is currently hard-coded in gnlc_slurm_mag.sh as $0 does not work inside the container (not the best way to do this)


## deprecated: Alina (GNLC of qMRI maps)
- the scripts in `deprecated_correct_qMRI_maps` (`batch_gnlc_alina.py`, `gnlc_slurm.sh`, `qform_sform_adjust.sh`) are scripts used for applying GNLC to the data of Alina Studenova. The correction is directly applied to the resulting qMRI maps. The `qform_sform_adjust.sh` is needed to account for the header changes when using sensitivity maps in the hMRI toolbox.

## comments regarding software environments 
- need to use `FSL --version <version>` as `SCWRAP fsl <version>` does not initialize on the SLURM cluster and `sc fsl <version>` does not transfer the activated conda environment when entering the container
- `runCorrection.sh` and `gradunwarp` check if the `FSLDIR` variable is set. As SCWRAP only executes commands in the container when needed, this `FSLDIR` is not set all the time. Therefore, the script crashed. If there is not custom container, we need to use the `FSL` environment or the `sc fsl` container including the conda initialization and activation of the correct environment, every time we enter the container