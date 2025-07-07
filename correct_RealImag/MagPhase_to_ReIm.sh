#!/bin/bash

set -e

usage() {
echo \
"
$(basename $0): Creates a complex image from a magnitude and a phase image, and extracts the real and imaginary components.
This script is intended to be used with MRtrix3 and requires the mrcalc command.

USAGE:
	$(basename $0) [options] -w <working_directory> <magnitude_image.nii> <phase_image.nii>

INPUT:
    Corresponding magnitude and phase images (one each), both in NIfTI format.

OPTIONS:
	-h | --help: print help text and exit

	-w DIRECTORY | --workingdir DIRECTORY: specify a specific working directory DIRECTORY to use. (MANDATORY)

OUTPUT:
	- the contents of the working directory will be retained at the specified location.

REQUIRES:
	- MRtrix3 binaries to be on the search path.
	- that all of the files given as input were acquired at the same orientation and resolution in the same session.

AUTHOR:
	Niklas Kuegler (kuegler@cbs.mpg.de)
"
}

scriptDirectory=$(dirname "$0")

# Give a hint if no arguments are provided
if [ $# -eq 0 ]; then
    echo "error: no arguments provided."                                         >&2
    echo try the \"-h\" option for information on how to use \"$(basename $0)\". >&2
    exit 1
fi

# Read optional command line arguments
# Based on /usr/share/doc/util-linux/examples/getopt-example.bash
TEMP=$(getopt -o 'hc:n:i:w:' --long 'help,workingdir:' -n "$(basename $0)" -- "$@")
if [ $? -ne 0 ]; then
        echo "error: not all input arguments could be processed." >&2
        exit 1
fi

eval set -- "$TEMP"
unset TEMP

while true; do
	case "$1" in
		'-h'|'--help')
			usage
			exit 0
		;;
		'-w'|'--workingdir')
			workingdir="$2"
			mkdir -p "$workingdir"
			shift 2
			continue
		;;
        '--')
            shift
            break
        ;;
		*)
			echo "error parsing optional input arguments" >&2
			exit 1
		;;
	esac
done

# Check if workingdir was provided
if [ -v "$workingdir" ]; then
    echo "error: working directory must be specified with -w or --workingdir." >&2
    echo try the \"-h\" option for information on how to use \"$(basename $0)\". >&2
    exit 1
fi

# Give a hint if mandatory positional arguments are missing
if [ $# -lt 2 ]; then
    echo "error: expected at least 2 positional arguments but got $#."           >&2
    echo try the \"-h\" option for information on how to use \"$(basename $0)\". >&2
    exit 1
fi

magnitude_image="$1"
phase_image="$2"

# Check if input files exist
if [ ! -f "$magnitude_image" ]; then
    echo "Error: Magnitude image '$magnitude_image' does not exist"
    exit 1
fi

if [ ! -f "$phase_image" ]; then
    echo "Error: Phase image '$phase_image' does not exist"
    exit 1
fi

# Extract base name and remove the suffix from magnitude image
base_name=$(basename "${magnitude_image%.nii}")

# Generate output filenames in working directory
complex_image="${workingdir}/${base_name/_part-mag/_part-complex}.nii"
real_image="${workingdir}/${base_name/_part-mag/_part-resReal}.nii"
imag_image="${workingdir}/${base_name/_part-mag/_part-resImag}.nii"

# Create complex image from magnitude and phase
# echo "Creating complex image from magnitude and phase..."
mrcalc "$magnitude_image" "$phase_image" -polar "$complex_image"

# Extract real component
# echo "Extracting real component..."
mrcalc "$complex_image" -real "$real_image"

# Extract imaginary component  
# echo "Extracting imaginary component..."
mrcalc "$complex_image" -imag "$imag_image"

# echo "Processing complete. Output files:"
# echo "  - $complex_image"
# echo "  - $real_image" 
# echo "  - $imag_image"


# echo "created real and imaginary images in $workingdir"
exit 0
