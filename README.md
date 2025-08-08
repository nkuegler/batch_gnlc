# batch_gnlc
Scripts to run Gradient Nonlinearity correction on a batch of files using the HCP pipeline or the NoGradWrap SPM module


## Explanation and usage of files

### Alina (GNLC of qMRI maps)
- the scripts in `correct_qMRI_maps` (`batch_gnlc_alina.py`, `gnlc_slurm.sh`, `qform_sform_adjust.sh`) are scripts used for applying GNLC to the data of Alina Studenova
    - there I apply the correction directly to the resulting qMRI maps
    - the qform_sform_adjustment is needed to account for the header changes when using sensitivity maps in the hMRI toolbox


### IronSleep (GNLC of Real and Imaginary parts of weighted images)
- the scripts in `correct_RealImag/` are used to create real and imaginary files from a batch of magnitude and phase images, and then apply gradient nonlinearity correction to each of those. After correction, they are turned back into magnitude and phase. 
- Thereafter, they can be processed further.

- For LORAKS: call with the following command: `runGNLC_re_im.sh -p *loraksRsos*_MPM.nii <scanner_name> <parent_dir>`
- example: 
    ```
    ./runGNLC_re_im.sh -p "*loraksRsos*_MPM.nii" -w /data/pt_02262/data/TH_bids/test_GNC_comparison/sub-004/ses-04/LORAKS/anat/wd_re_im Terra /data/pt_02262/data/TH_bids/test_GNC_comparison/sub-004/ses-04/LORAKS/anat/
    ```

#### file description in RealImag directory:
- `call_slurm_batch.sh` = loop through multiple input paths and call slurm jobs
- `slurm_gnlc_proc.sh` = submitted slurm script
- `runGNLC_re_im.sh` = main script
- `MagPhase_to_ReIm.sh` = conversion to real and imaginary parts
- `gnlc_jac_MagPhase` = run GNLC, do jacobian correction, conversion back to Mag and Phase


#### How to submit correction as SLURM jobs

```
./call_slurm_batch.sh -w -d -p "*loraksRsos*_MPM.nii" -o /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA_distCorr Terra /data/pt_02262/data/TH_bids/bids/derivatives/LORAKS_LCPCA/
```
- The flag `-w` specifies that a working directory is created inside each session folder in the output directory. If it is not set, the script creates temporary directories in `/tmp`.
    - If `-w` is set, the working directory will not be deleted at the end of the processing unless the `-d` flag is also set.
    - The working directory in `/tmp` will always be deleted at the end.


examples:
```
# Basic usage with Terra scanner (use temporary working directory)
./call_slurm_batch.sh Terra /path/to/bids/dataset

# With output directory
./call_slurm_batch.sh -o /tmp/gnlc_results Terra /path/to/bids/dataset

# Use persistent working directory
./call_slurm_batch.sh -w Terra /path/to/bids/dataset

# Specify a custom working directory but delete it after processing
./call_slurm_batch.sh -w -d Terra /path/to/bids/dataset

# With all options
./call_slurm_batch.sh -o /results -w -d -p '*_magnitude.nii' -t 10 Terra /path/to/bids/dataset
```


### Magnitude only (3T)
```
./call_slurm_batch_magn.sh -sub sub-001 -ses ses-05 Prisma_fit /data/pt_02262/data/TH_bids/bids/derivatives/LCPCA/ /data/pt_02262/data/TH_bids/bids/derivatives/LCPCA_distCorr/
# set -p flag if needed

# --d to delete working dir
./call_slurm_batch_magn.sh --d Prisma_fit /data/pt_02262/data/TH_bids/bids/derivatives/LCPCA/ /data/pt_02262/data/TH_bids/bids/derivatives/LCPCA_distCorr/
```
- unzips the jacobian corrected data after the correction (fslmaths outputs .nii.gz files) -> the output files will always be .nii


# TODO:
- correct_MagOnly: Move deletion of the undistorted directory in a separate job called after all contrasts are finished (then the jobs for the different contrasts can run in parallel)



# Hints:
- `correct_RealImag` uses pid to parallelize the processes (submit one slurm job that runs three parallel tasks, one for each contrast) -> in `runGNLC_re_im.sh`
- `correct_MagOnly` submits one slurm job per contrast. However, to not accidentally deleting the working directories before all the jobs are finished, the specified contrasts run as sequential slurm jobs -> in `call_slurm_batch_magn.sh`
- both approaches are not ideal -> best would be parallel slurm jobs with deletion of the working directory after all three are finished 


- before processing each corresponding JSON file is checked. The correction is aborted if the NonlinearGradientCorrection key in the corresponding JSON is true 
    - The implementation of this feature is better in the MagOnly correction. Maybe adjust RealImag in a similar way. (would need quite a bit of adjustment of the file structure)

- each JSON file is updated after the processing to reflect the corrected state of the image

- some more arguments were added for this script (mostly to account for specific needs of the R2 processing workflow): -dep -job-name -log