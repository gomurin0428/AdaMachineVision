GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
# Prover processes for make prove (0 = one per core).
PROVE_JOBS ?= 0
# Directory of a file cache of prover results for make prove (empty = no
# cache). gnatprove keys each result by the proof obligation and the
# prover options, so a cached result is only reused for an identical one.
PROVE_CACHE ?=
PROVE_CACHE_SWITCH = $(if $(PROVE_CACHE),--memcached-server=file:$(abspath $(PROVE_CACHE)))
# Source files to prove (empty = the whole project), for example one proof
# group of the CI: make prove PROVE_UNITS="$$(tools/prove_groups.sh core)".
PROVE_UNITS ?=

.PHONY: all build test test-ada test-c examples run-examples fetch-real-images \
	test-real-images run-real-image-examples pictures check shell-check \
	prove clean

all: build

build:
	$(GPRBUILD) -p -P amv.gpr

# Ada tests, then the C API tests.
test: test-ada test-c

test-ada:
	$(GPRBUILD) -p -P amv_tests.gpr
	./build/bin/test_suite

test-c:
	$(GPRBUILD) -p -P amv_c_tests.gpr
	./build/bin/test_c_api

# Downloads the open images of tests/real_images/images.txt (checked by
# SHA-256) and converts them to BMP in build/real-images; needs curl and
# ImageMagick or sips (macOS).
fetch-real-images:
	./tools/fetch_real_images.sh

# The tests on those real images (tests/real_images/README.md).
test-real-images: fetch-real-images
	$(GPRBUILD) -p -P amv_tests.gpr test_real_images.adb
	./build/bin/test_real_images

examples:
	$(GPRBUILD) -p -P amv_examples.gpr
	$(GPRBUILD) -p -P amv_c_examples.gpr

# Runs the examples in build/example-run (they write images there) and
# checks their reports: the exit status, and the verdicts of the blob
# inspection on its synthetic image.
run-examples: examples
	mkdir -p build/example-run
	cd build/example-run && ../bin/quick_look > quick_look.txt \
	  && cat quick_look.txt \
	  && grep -q "is at 1\.283012701892[0-9]*E+01, 1\.222243186433[0-9]*E+01 " quick_look.txt
	cd build/example-run && ../bin/blob_inspection > blob_inspection.txt \
	  && cat blob_inspection.txt && grep -q "^OK: 4, NG: 2$$" blob_inspection.txt
	cd build/example-run && ../bin/c_blob_inspection > c_blob_inspection.txt \
	  && cat c_blob_inspection.txt && grep -q "^OK: 4, NG: 2$$" c_blob_inspection.txt
	cd build/example-run && ../bin/align_and_measure

# Runs the examples on real images (examples/real_images/README.md) in
# build/example-run and checks the main facts of their reports: the exit
# status and the counts. They write their result pictures there.
REAL_IMAGES = $(CURDIR)/build/real-images
run-real-image-examples: examples fetch-real-images
	mkdir -p build/example-run
	cd build/example-run && AMV_REAL_IMAGES=$(REAL_IMAGES) ../bin/coin_count \
	  > coin_count.txt && cat coin_count.txt \
	  && grep -q "^after the top-hat: 24 coins$$" coin_count.txt
	cd build/example-run && AMV_REAL_IMAGES=$(REAL_IMAGES) ../bin/pcb_gauging \
	  > pcb_gauging.txt && cat pcb_gauging.txt \
	  && test "$$(grep -c '^board [0-9]*: found' pcb_gauging.txt)" = 6 \
	  && test "$$(grep -c '^  width: 9[0-9][0-9]\.' pcb_gauging.txt)" = 6
	cd build/example-run && AMV_REAL_IMAGES=$(REAL_IMAGES) ../bin/candle_rims \
	  > candle_rims.txt && cat candle_rims.txt \
	  && grep -q "PMAlign found 4 lights$$" candle_rims.txt \
	  && test "$$(grep -c 'rim centre' candle_rims.txt)" = 4
	cd build/example-run && AMV_REAL_IMAGES=$(REAL_IMAGES) ../bin/nuclei_count \
	  > nuclei_count.txt && cat nuclei_count.txt \
	  && grep -q "^field eval_07: 98 blobs$$" nuclei_count.txt

# The result pictures the READMEs show (docs/images): runs the examples
# and converts the pictures they wrote to PNG; needs ImageMagick or sips
# (macOS). Run it when an example's picture changes, and commit the result.
pictures: run-examples run-real-image-examples
	./tools/update_pictures.sh

# Everything with warnings as errors, plus the check that the Ada API stays
# a thin layer over the SPARK kernels. Run before every pull request.
check: shell-check
	$(GPRBUILD) -p -P amv.gpr -cargs:Ada -gnatwe
	$(GPRBUILD) -p -P amv_tests.gpr -cargs:Ada -gnatwe
	$(GPRBUILD) -p -P amv_c_tests.gpr -cargs:Ada -gnatwe -cargs:C -Werror
	$(GPRBUILD) -p -P amv_examples.gpr -cargs:Ada -gnatwe
	$(GPRBUILD) -p -P amv_c_examples.gpr -cargs:Ada -gnatwe -cargs:C -Werror

shell-check:
	$(GPRBUILD) -p -P tools/shell_check.gpr -cargs:Ada -gnatwe
	./build/tools/amv_shell_check src tools/shell_check_legacy.txt

# Proves the SPARK kernels (docs/PROOF.md). Unproved checks and warnings
# are errors.
prove:
	$(if $(PROVE_CACHE),mkdir -p $(PROVE_CACHE))
	$(GNATPROVE) -P amv.gpr -j$(PROVE_JOBS) --checks-as-errors=on \
	  --warnings=error --report=fail $(PROVE_CACHE_SWITCH) \
	  $(foreach u,$(PROVE_UNITS),-u $(u))

clean:
	rm -rf build
