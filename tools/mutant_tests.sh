#!/bin/sh
# The tests that AdaMutant runs for one mutant (adamutant.toml): the
# areas of test_suite that check the unit of the mutated file, the
# quickest first and each in a run of its own, so that a mutant that is
# caught early costs little. A file without areas of its own here gets
# the whole suite, and so does the run without a mutant, which AdaMutant
# makes first to see that the tests pass and how long they take.
#
# AdaMutant gives the mutated file in ADAMUTANT_MUTANT_FILE (a path from
# the root of the repository) and runs this script from the root of a
# copy of the repository in which test_suite is built.
set -eu

two_d="Test_Code_Reader_2D"
dm="Test_Code_Reader_Data_Matrix"
qr="Test_Code_Reader_QR_Code"
qr_finder="Test_Code_Reader_QR_Finder"
qr_patterns="Test_Code_Reader_QR_Patterns"
qr_placing="Test_Code_Reader_QR_Placing"
qr_sampling="Test_Code_Reader_QR_Sampling"
qr_symbol="Test_Code_Reader_QR_Symbol"

case "${ADAMUTANT_MUTANT_FILE:-}" in
  src/amv-kernels-code_reader-qr_code.adb)
    areas="$qr_symbol $qr" ;;
  src/amv-kernels-code_reader-qr_code-finder.adb)
    areas="$qr_patterns $qr_placing $qr_sampling $qr_finder $qr" ;;
  src/amv-kernels-code_reader-views.adb)
    areas="$qr_patterns $qr_placing $qr_sampling $qr_finder $qr $dm" ;;
  src/amv-kernels-code_reader-reed_solomon.adb)
    areas="$two_d $qr_symbol $qr $dm" ;;
  src/amv-kernels-code_reader-dark_areas.adb)
    areas="$two_d $qr_finder $qr $dm" ;;
  src/amv-kernels-code_reader-data_matrix.adb \
  | src/amv-kernels-code_reader-data_matrix-finder.adb)
    areas="$two_d $dm" ;;
  src/amv-kernels-code_reader-linear.adb \
  | src/amv-kernels-code_reader-profiles.adb)
    areas="Test_Code_Reader" ;;
  src/amv-kernels-code_reader.adb | src/amv-code_reader.adb)
    areas="$two_d Test_Robustness Test_Code_Reader $qr $dm" ;;
  *)
    exec ./build/bin/test_suite ;;
esac

for area in $areas; do
  ./build/bin/test_suite "$area"
done
