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
# Mutation testing (adamutant.toml) with AdaMutant
# (https://github.com/gomurin0428/AdaMutant): the files or patterns to
# mutate for make mutation (empty = every body), the revision whose
# changed lines make mutation-diff takes, the number of sandboxes, the
# JSON report of an earlier run whose results are taken again for the
# lines not changed since (empty = none), the file cache of the proofs
# of the mutants (that of make prove where it is given), the prover
# processes of each, and the configuration (tools/mutant_shard.sh
# writes ones with a part of the mutators).
ADAMUTANT ?= adamutant
MUTATE ?=
MUTATION_BASE ?= origin/main
MUTATION_JOBS ?= 2
MUTATION_BASELINE ?=
MUTATION_CACHE ?= $(or $(PROVE_CACHE),build/prove-cache)
MUTATION_PROVE_JOBS ?= 2
MUTATION_CONFIG ?= adamutant.toml
MUTATION_RUN = mkdir -p $(MUTATION_CACHE) && \
  AMV_PROVE_CACHE=$(abspath $(MUTATION_CACHE)) \
  AMV_PROVE_JOBS=$(MUTATION_PROVE_JOBS) \
  AMV_PROVE_UNITS='$(notdir $(wildcard $(MUTATE)))' $(ADAMUTANT) run \
  --config $(MUTATION_CONFIG) --concurrency $(MUTATION_JOBS) \
  $(if $(MUTATION_BASELINE),--baseline $(MUTATION_BASELINE)) \
  $(foreach m,$(MUTATE),--mutate '$(m)')

.PHONY: all build test test-ada test-c examples run-examples fetch-real-images \
	test-real-images run-real-image-examples pictures check shell-check \
	build-aravis test-aravis example-aravis build-live-circularity build-flow test-flow prove prove-aravis mutation mutation-diff clean

all: build

build:
	$(GPRBUILD) -p -P amv.gpr

# Ada tests, then the C API tests.
test: test-ada test-c

# test_suite checks every contract of the library (amv_tests.gpr);
# test_suite_library runs the same tests with the library's policy, the
# timings and the NaNs included (amv_tests_library.gpr).
test-ada:
	$(GPRBUILD) -p -P amv_tests.gpr
	./build/bin/test_suite
	$(GPRBUILD) -p -P amv_tests_library.gpr test_suite.adb
	./build/bin/test_suite_library

test-c:
	$(GPRBUILD) -p -P amv_c_tests.gpr
	./build/bin/test_c_api

ARAVIS_PKG ?= aravis-0.8
ARAVIS_CFLAGS = $(shell pkg-config --cflags $(ARAVIS_PKG) 2>/dev/null)
ARAVIS_LIBS = $(shell pkg-config --libs $(ARAVIS_PKG) 2>/dev/null)

build-aravis:
	@pkg-config --exists $(ARAVIS_PKG) || { \
	  echo "Aravis development files not found (pkg-config $(ARAVIS_PKG))" >&2; \
	  exit 1; }
	$(GPRBUILD) -p -P optional/aravis/amv_gige_vision.gpr \
	  -cargs:C $(ARAVIS_CFLAGS)
	$(GPRBUILD) -p -P optional/aravis/examples/capture_one_image.gpr \
	  -cargs:C $(ARAVIS_CFLAGS) -largs $(ARAVIS_LIBS)

# Both endpoints use the explicit loopback address 127.0.0.1 and never scan
# devices. Linux runs them in a fresh network namespace; Windows runs locally.
test-aravis: build-aravis
	$(GPRBUILD) -p -P optional/aravis/tests/amv_gige_vision_tests.gpr \
	  -cargs:C $(ARAVIS_CFLAGS) -largs $(ARAVIS_LIBS)
ifeq ($(OS),Windows_NT)
	@PATH="$(MINGW_PREFIX)/bin:$$PATH" ./build/bin/test_gige_vision.exe
else
	@set -eu; \
	test_cmd='ip link set lo up && "$(CURDIR)/build/bin/test_gige_vision"'; \
	if unshare --user --map-root-user --net /bin/sh -c ':' 2>/dev/null; then \
	  unshare --user --map-root-user --net /bin/sh -eu -c "$$test_cmd"; \
	elif sudo -n unshare --net /bin/sh -c ':' 2>/dev/null; then \
	  sudo -n unshare --net /bin/sh -eu -c "$$test_cmd"; \
	else \
	  echo "Cannot create an isolated network namespace; refusing to run the fake camera outside one" >&2; \
	  exit 1; \
	fi
endif

# Windows only: the live circularity window (optional/aravis/examples/
# live_circularity).
build-live-circularity: build-aravis
	$(GPRBUILD) -p -P optional/aravis/examples/live_circularity/live_circularity.gpr \
	  -cargs:C $(ARAVIS_CFLAGS) -largs $(ARAVIS_LIBS)

# AMV Flow (optional/flow, docs/FLOW_EDITOR_DESIGN.md): the engine, the
# amv_flow command-line runner and its tests. Needs AMV only.
build-flow:
	$(GPRBUILD) -p -P optional/flow/cli/amv_flow_cli.gpr

test-flow:
	$(GPRBUILD) -p -P optional/flow/tests/amv_flow_tests.gpr
	./build/bin/test_flow

example-aravis: build-aravis
	@test -n "$(CAMERA_ID)" || { \
	  echo "Set CAMERA_ID to an explicit camera IP or device ID" >&2; exit 2; }
	./build/bin/capture_one_image "$(CAMERA_ID)" "$(or $(IMAGE),capture.pgm)"

# Downloads the open images of the manifests tests/real_images/*.txt
# (checked by SHA-256) and converts them to BMP in build/real-images;
# needs curl, python3 and ImageMagick or sips (macOS).
fetch-real-images:
	./tools/fetch_real_images.sh

# The tests on those real images (tests/real_images/README.md).
test-real-images: fetch-real-images
	$(GPRBUILD) -p -P amv_tests_library.gpr test_real_images.adb
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
	  && grep -q "Shape Match found 4 lights$$" candle_rims.txt \
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
	$(GPRBUILD) -p -P amv_tests_library.gpr -cargs:Ada -gnatwe
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

# Proves only the optional GigE specification and its production engine.
ARAVIS_PROVE_UNITS ?= amv-spec-gige_vision.ads amv-kernels-gige_vision.adb
prove-aravis:
	$(GNATPROVE) -P optional/aravis/amv_gige_vision_proof.gpr -j$(PROVE_JOBS) \
	  --checks-as-errors=on --warnings=error --report=fail \
	  $(foreach u,$(ARAVIS_PROVE_UNITS),-u $(u))

# Mutation testing: every small change of a body (a mutant) is run with
# the areas of test_suite that execute its place and, if they pass, the
# proof of its unit (tools/mutant_prove.sh); a mutant that neither
# notices shows a gap in the tests or in the contracts (docs/DESIGN.md
# 8). Run make mutation-diff before a pull request that changes a body,
# and make mutation MUTATE=src/<file>.adb for a whole file.
mutation:
	$(MUTATION_RUN)

mutation-diff:
	$(MUTATION_RUN) --since $(MUTATION_BASE)

clean:
	rm -rf build
