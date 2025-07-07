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

- For LORAKS: call with the following command: `runGNLC_re_im.sh -p *loraksRsos*_MPM.nii <parent_dir>`
- example: 
    ```
    ./runGNLC_re_im.sh -p "*loraksRsos*_MPM.nii" -w /data/pt_02262/data/TH_bids/test_GNC_comparison/sub-004/ses-04/LORAKS/anat/wd_re_im /data/pt_02262/data/TH_bids/test_GNC_comparison/sub-004/ses-04/LORAKS/anat/
    ```

#### file description in RealImag directory:
- `call_slurm_batch.sh` = loop through multiple input paths and call slurm jobs
- `slurm_gnlc_proc.sh` = submitted slurm script
- `runGNLC_re_im.sh` = main script
- `MagPhase_to_ReIm.sh` = conversion to real and imaginary parts
- `gnlc_jac_MagPhase` = run GNLC, do jacobian correction, conversion back to Mag and Phase


### How to submit correction as SLURM jobs

```
./call_slurm_batch.sh -w -p "*loraksRsos*_MPM.nii" -o /data/pt_02262/data/TH_bids/testdata_Taechang/LORAKS/derivatives/LCPCA_distCorr/ /data/pt_02262/data/TH_bids/testdata_Taechang/LORAKS/derivatives/LCPCA/
```