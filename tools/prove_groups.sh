#!/bin/sh
# The proof groups of the CI: every kernel source file (src/amv-kernels*)
# belongs to exactly one group, and each group is proved by its own CI job
# (gnatprove -u on its files), so that a cold proof is split over several
# runners instead of exceeding the time limit of one.
#
#   tools/prove_groups.sh GROUP   the group's files, for make PROVE_UNITS
#   tools/prove_groups.sh list    every kernel file with its group
#
# A kernel that matches no pattern below falls into "core", so a new
# kernel is never left unproved. Run from the repository root or anywhere.

set -eu

cd "$(dirname "$0")/.."

group_of() {
    case "$1" in
        amv-kernels-pm_align*) echo pm-align ;;
        amv-kernels-calib_fix* | amv-kernels-cnl_search*) echo calib-cnl ;;
        amv-kernels-ip_* | amv-kernels-histogram* | amv-kernels-pixel_map* \
        | amv-kernels-sobel_edge* | amv-kernels-image_sharpness* \
        | amv-kernels-filter_inputs* | amv-kernels-image_sampling*)
            echo filters ;;
        amv-kernels-affine_transform* | amv-kernels-copy_region* \
        | amv-kernels-polar_unwrap* | amv-kernels-image_convert* \
        | amv-kernels-blob* | amv-kernels-caliper* | amv-kernels-find_line* \
        | amv-kernels-find_circle*)
            echo geometry-measure ;;
        amv-kernels-dimensioning* | amv-kernels-create_shapes* \
        | amv-kernels-tool_group* | amv-kernels-geometry*)
            echo dimensioning-tools ;;
        *) echo core ;;
    esac
}

if [ $# -ne 1 ]; then
    echo "usage: tools/prove_groups.sh GROUP | list" >&2
    exit 2
fi

found=0
for path in src/amv-kernels*.ads src/amv-kernels*.adb; do
    file=$(basename "$path")
    group=$(group_of "$file")
    if [ "$1" = list ]; then
        echo "$group $file"
        found=1
    elif [ "$1" = "$group" ]; then
        printf '%s ' "$file"
        found=1
    fi
done
if [ "$found" -eq 0 ]; then
    echo "prove_groups: no kernel file in group $1" >&2
    exit 1
fi
