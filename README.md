# batch_gnlc
Scripts to run Gradient Nonlinearity correction on a batch of files using the HCP pipeline or the NoGradWrap SPM module


## Explanation and usage of files
- `batch_gnlc_alina.py`, `gnlc_slurm.sh`, `qform_sform_adjust.sh` are scripts used for applying GNLC to the data of Alina Studenova
    - there I apply the correction directly to the resulting qMRI maps
    - the qform_sform_adjustment is needed to account for the header changes when using sensitivity maps in the hMRI toolbox


- the scripts in `RealImag/` are used to create real and imaginary files from a batch of magnitude and phase images, and then apply gradient nonlinearity correction to each of those. After correction, they are turned back into magnitude and phase. 
- Thereafter, they can be processed further.
