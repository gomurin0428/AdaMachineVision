export const meta = {
  name: 'amv-core-review',
  description: 'Review the AdaMachineVision core packages through two lenses, then verify and fix the findings',
  phases: [
    { title: 'Review', detail: 'numeric correctness lens + Ada safety/API lens' },
    { title: 'Fix', detail: 'apply confirmed findings with regression tests' },
  ],
}

// Extracted from the workflow that built the core. Its Implement and
// Integrate phases already ran; this is the part that was stopped before it
// started. ROOT is the POSIX path of the checkout on the machine that runs it.

const ROOT = '/d/Src/AdaMachineVision'

const COMMON = `You are implementing part of AdaMachineVision (AMV), an Ada 2022 machine vision library in ${ROOT} (Windows host: D:\\Src\\AdaMachineVision; use the Bash tool with POSIX paths). Its public interface mirrors the Cognex VisionPro .NET API mapped to Ada naming; the implementation must be independent. CLEAN ROOM: never copy Cognex code, samples or documentation text; write every comment in your own words.

Read first: docs/DESIGN.md (the contract), src/amv.ads, and the specs named in your task. Toolchain: GNAT 14.2 and gprbuild are on PATH.

Build and test (ALWAYS pass your own --subdirs value so that agents working concurrently in the same tree do not overwrite each other's object files):
  cd ${ROOT}
  gprbuild -p -P amv_tests.gpr --subdirs=SUBDIR test_xxx.adb
  ./build/bin/SUBDIR/test_xxx          # exit status 0 means every check passed
  gprbuild -p -P amv_tests.gpr --subdirs=SUBDIR -c -u src/amv-foo.adb   # compile one unit, no link
amv_tests.gpr compiles src/ and tests/ directly and only the closure of the main you name, so packages other agents are still writing do not break your build unless you depend on them.

Rules:
- Create or modify ONLY the files assigned to you. Other agents are writing other packages in the same directory right now. Do not edit their files; do not run git commands that change state (no add/commit/stash/checkout/reset/clean); do not delete anything outside build/*/SUBDIR.
- The existing .ads specs are the contract. You may change a spec that your task OWNS only to fix a real defect (illegal Ada, contradictory or impossible contract, an operation the body clearly needs). Keep such changes minimal, keep comments accurate, and list every change in your report. Never change a spec you do not own; report the problem instead.
- Code must compile without warnings under the project switches (-gnat2022 -gnatwa -gnatVa; tests also -gnata with pragma Initialize_Scalars). Before finishing, rebuild your test mains with "-cargs:Ada -gnatwe" appended and make sure that passes.
- Large pixel data on the heap only; every heap object owned by a controlled type; no leaks; no whole-image arrays as stack locals.
- Tests: write tests/test_<area>.adb as a parameterless main procedure that uses AMV_Test_Support (read tests/amv_test_support.ads; wrap the body with the Standalone generic exactly as its comment shows). Check results against exact or analytically known ground truth with tight tolerances, cover edge cases, defaults, and error paths (the right exception type is raised; use the Check_Raises generic). All tests must pass before you finish.
- Style: Ada comments use "--  " (two spaces); keep lines within 79 columns where practical; document behaviour in specs in your own words.
- Be thorough and correct. Think about numerical edge cases (zero lengths, singular transforms, angles wrapping at +/-Pi, NaN-free code paths).

Your final answer is structured data: list the files you created or changed, any spec changes (with the reason), whether all your tests pass and the final check counts, open issues you could not resolve, and api_mapping_rows: one entry per public VisionPro-style type/method you implemented, in the form "VisionPro name -> Ada name" (only where the mapping is not the obvious mechanical one, plus every reserved-word rename).`

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    files_changed: { type: 'array', items: { type: 'string' } },
    spec_changes: { type: 'array', items: { type: 'string' } },
    tests_pass: { type: 'boolean' },
    test_summary: { type: 'string' },
    open_issues: { type: 'array', items: { type: 'string' } },
    api_mapping_rows: { type: 'array', items: { type: 'string' } },
  },
  required: ['files_changed', 'spec_changes', 'tests_pass', 'test_summary', 'open_issues', 'api_mapping_rows'],
}

phase('Review')
const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
          title: { type: 'string' },
          failure_scenario: { type: 'string' },
          evidence: { type: 'string' },
          suggested_fix: { type: 'string' },
        },
        required: ['file', 'severity', 'title', 'failure_scenario', 'evidence', 'suggested_fix'],
      },
    },
  },
  required: ['findings'],
}
const REVIEW_COMMON = `You are reviewing the core packages of AdaMachineVision in ${ROOT} (Windows host D:\\Src\\AdaMachineVision; use Bash with POSIX paths). Read docs/DESIGN.md first, then the specs and bodies in src/ and the tests in tests/. The full suite builds with: gprbuild -p -P amv_tests.gpr --subdirs=REVIEWDIR && ./build/bin/REVIEWDIR/test_suite.

Your job is to find REAL defects, not style nits. For every candidate defect, try to prove it: write a small throwaway probe main under build/REVIEWDIR-probes/ (NOT in src/ or tests/; compile it with a temporary project file under build/REVIEWDIR-probes/ that copies amv_tests.gpr and sets Source_Dirs to ("../../src", "../../tests", ".") (gprbuild does not accept -aI on the command line)), run it, and report the observed vs expected behaviour as evidence. Report only findings you confirmed or can argue rigorously from the code (say which). Do NOT modify any file in src/ or tests/; do not run git commands that change state. Delete nothing outside your own build/REVIEWDIR* directories.`

const reviews = await parallel([
  () => agent(REVIEW_COMMON.replaceAll('REVIEWDIR', 'review_numeric') + `

LENS: numeric and geometric correctness against the spec comments. Check: transform decomposition/recomposition and every Set_ property (including reflections, zero scalings, angle wrapping), Invert/Compose order, Map_Angle; coordinate-space Get_Transform direction and composition order for deep trees and the image-level "#"/"." resolution with a non-identity Pixel_From_Root; every shape's Contains_Point / Get_Bounding_Box / Area / Map (affine rectangle with skew, ellipse mapping, annulus sections with negative or > 2 Pi spans, polygon edge cases); region rasterisation (pixel-centre convention, clipping, mapped spaces); Image_Math (Bilinear borders, Resample, Gaussian normalisation and radius, Box_Smooth, Sobel scaling/sign, Downsample_2 with odd sizes, Statistics); geometry fits (degenerate input, convergence, robust variant correctness, rotation normalisation) and intersections; test image generator accuracy. Use brute-force reference computations in your probes.`, { label: 'review numeric', phase: 'Review', schema: FINDINGS_SCHEMA }),
  () => agent(REVIEW_COMMON.replaceAll('REVIEWDIR', 'review_safety') + `

LENS: Ada resource safety, robustness and API/design conformance. Check: reference counting in AMV.Images (Adjust/Finalize pairing, idempotent Finalize, self-assignment, Allocate detaching, Get_Plane sharing, Copy modes, atomic use), Real_Image and Pixel_Region deep copies, leaks (run a probe that creates/copies/destroys many images in a loop and watch memory via repeated runs or GNAT.Debug_Pools if practical), unchecked deallocation of shared data, stack usage with large images (e.g. 4000x3000 images through To_Matrix/From_Matrix, Resample, Gaussian_Smooth, Rasterize) - nothing should overflow the stack; AMV.Image_File robustness: feed truncated, corrupted, huge-dimension (e.g. width 2^31) and zero-size headers and make sure only Ks_Image_File_Exception escapes and no gigantic allocation is attempted without validation; Tools.Run never propagating (including Storage_Error/Program_Error from Execute or Reset_Results); exception types and messages per docs/DESIGN.md section 6; naming and 0-based conventions per sections 3-4; Initialize_Scalars/-gnatVa invalid-value reads; anything that would make the library unsafe to use from several tasks on different images.`, { label: 'review safety', phase: 'Review', schema: FINDINGS_SCHEMA }),
])
const findings = reviews.filter(Boolean).flatMap(r => r.findings)
log(`Review produced ${findings.length} findings`)

phase('Fix')
let fix = null
if (findings.length > 0) {
  fix = await agent(COMMON + `

TASK FIX (SUBDIR=fix). You own every file under src/ and tests/. Two reviewers reported these findings about the core packages:
${JSON.stringify(findings, null, 1)}

For each finding: first verify it independently (reproduce it with a regression test in the relevant tests/test_<area>.adb, or show by reading the code that it is real). If it is real, fix it at the root cause and keep the regression test. If it is not real, explain why in open_issues prefixed with "REJECTED:". Then run the whole suite with -gnatwe (gprbuild -p -P amv.gpr --subdirs=fix -cargs:Ada -gnatwe; gprbuild -p -P amv_tests.gpr --subdirs=fix -cargs:Ada -gnatwe && ./build/bin/fix/test_suite) and make sure everything passes. In test_summary, list each finding title with FIXED or REJECTED and the final suite counts.`, { label: 'fix findings', phase: 'Fix', schema: IMPL_SCHEMA })
}

return { findings, fix }
