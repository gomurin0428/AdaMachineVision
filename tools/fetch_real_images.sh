#!/bin/sh
# Downloads the images listed in the manifests tests/real_images/*.txt
# (images.txt: open images; visa.txt: VisA;
# bbbc006.txt: BBBC006; bbbc039.txt: BBBC039; see each header) into build/real-images/raw, checks
# their SHA-256 and converts each to BMP in build/real-images (AMV reads
# PNM and BMP only). Files that are already there with the right checksum
# are not downloaded again.
#
# A manifest line is: file name, SHA-256, URL, and for some a fourth field.
# "#bytes=START-END" after the URL fetches that byte range (one member of
# a tar archive). "#zip=START-END" fetches the local file entry of one
# member of a zip archive; the member, a 16-bit TIFF, is then written as a
# 16-bit PGM whose maxval is the fourth field (tools/zip_tiff_to_pgm.py,
# which needs python3), instead of a BMP, or, when the fourth field is
# "labels", a colour mask PNG is written as a 16-bit label image
# (tools/zip_png_labels.py).
#
# The conversion to BMP uses ImageMagick (magick or convert) when it is
# installed, otherwise sips (macOS). Run from the repository root.

set -eu

out=build/real-images

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | cut -d ' ' -f 1
    else
        shasum -a 256 "$1" | cut -d ' ' -f 1
    fi
}

to_bmp() {
    # 24-bit BMP, transparency flattened on white.
    if command -v magick > /dev/null 2>&1; then
        magick "$1" -background white -alpha remove -type TrueColor "BMP3:$2"
    elif command -v convert > /dev/null 2>&1; then
        convert "$1" -background white -alpha remove -type TrueColor "BMP3:$2"
    elif command -v sips > /dev/null 2>&1; then
        sips -s format bmp "$1" --out "$2" > /dev/null
    else
        echo "fetch_real_images: need ImageMagick (magick or convert) or sips" >&2
        exit 1
    fi
}

mkdir -p "$out/raw"
cat tests/real_images/*.txt | grep -v '^#' | grep -v '^[[:space:]]*$' |
while read -r name sum url option; do
    case "$url" in
        *'#zip='*) raw="$out/raw/${name%.*}.zipentry" ;;
        *) raw="$out/raw/$name" ;;
    esac
    if [ ! -f "$raw" ] || [ "$(sha256_of "$raw")" != "$sum" ]; then
        case "$url" in
            *'#bytes='*)
                curl -fsSL --retry 5 --retry-all-errors -r "${url##*#bytes=}" -o "$raw.part" \
                    "${url%%#*}" ;;
            *'#zip='*)
                curl -fsSL --retry 5 --retry-all-errors -r "${url##*#zip=}" -o "$raw.part" \
                    "${url%%#*}" ;;
            *)
                curl -fsSL --retry 5 --retry-all-errors -o "$raw.part" "$url" ;;
        esac
        mv "$raw.part" "$raw"
    fi
    actual=$(sha256_of "$raw")
    if [ "$actual" != "$sum" ]; then
        echo "fetch_real_images: checksum mismatch for $name ($actual)" >&2
        rm -f "$raw"
        exit 1
    fi
    case "$url" in
        *'#zip='*)
            if [ ! -f "$out/$name" ] || [ "$raw" -nt "$out/$name" ]; then
                if [ "$option" = labels ]; then
                    python3 -I -B tools/zip_png_labels.py "$raw" "$out/$name" \
                        > /dev/null
                else
                    python3 -I -B tools/zip_tiff_to_pgm.py "$raw" "$out/$name" \
                        "$option"
                fi
            fi ;;
        *)
            bmp="$out/${name%.*}.bmp"
            if [ ! -f "$bmp" ] || [ "$raw" -nt "$bmp" ]; then
                to_bmp "$raw" "$bmp"
            fi ;;
    esac
done
echo "fetch_real_images: images ready in $out"
