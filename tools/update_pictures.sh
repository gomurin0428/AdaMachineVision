#!/bin/sh
# Converts the result pictures the examples wrote in build/example-run
# (make run-examples, make run-real-image-examples) to PNG in docs/images,
# where the READMEs show them. "make pictures" runs the examples first.
#
# The conversion uses ImageMagick (magick or convert) when it is
# installed, otherwise sips (macOS). Run from the repository root.

set -eu

src=build/example-run
out=docs/images

to_png() {
    if command -v magick > /dev/null 2>&1; then
        magick "$1" -strip "PNG24:$2"
    elif command -v convert > /dev/null 2>&1; then
        convert "$1" -strip "PNG24:$2"
    elif command -v sips > /dev/null 2>&1; then
        sips -s format png "$1" --out "$2" > /dev/null
    else
        echo "update_pictures: needs ImageMagick or sips" >&2
        exit 1
    fi
}

mkdir -p "$out"
for name in \
    blob_result align_result \
    coin_count_steps coin_count_result \
    pcb_gauging_1_train pcb_gauging_2_found pcb_gauging_3_measured \
    pcb_gauging_4_hole pcb_gauging_5_outline pcb_gauging_boards \
    candle_rims_1_train candle_rims_2_found candle_rims_3_measured \
    candle_rims_4_rim \
    nuclei_count_result
do
    if [ ! -f "$src/$name.bmp" ]; then
        echo "update_pictures: no $src/$name.bmp: run make pictures" >&2
        exit 1
    fi
    to_png "$src/$name.bmp" "$out/$name.png"
done
echo "update_pictures: pictures ready in $out"
