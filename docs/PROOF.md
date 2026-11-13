# Proof status

This file lists what `make prove` proves, what is trusted without proof,
and the known limits. Update it with every kernel. The rules behind it are
in `docs/DESIGN.md` section 9 and `docs/handoff/SPARK_PLAN.md`.

## How to run

```
make prove                 # gnatprove -P amv.gpr, every check must be proved
make prove PROVE_JOBS=2    # fewer prover processes on a shared machine
```

Toolchain: gnatprove 16.1 (GNAT FSF builds, with Alt-Ergo 2.6.1, cvc5
1.3.2 and Z3 4.15.4). On macOS the gnatprove binary directory must be on
`PATH`; Alt-Ergo needs Homebrew's `gmp`. A full run from scratch takes
about eleven minutes with two prover processes on a busy machine for the
units before `AMV.Kernels.Image_File` (the image kernel takes most of it;
its slowest check needs under a second); the image file kernel alone
takes about nine minutes with four prover processes on a busy machine
(its slowest checks, postconditions of the PNM rasters, need about 1 to
3 seconds there). The shape kernel alone takes about three minutes with
three prover processes on a busy machine (its slowest check, an overflow
check of the ellipse map, about 3 seconds), the real image kernel about
seventeen and the geometry kernel about ten. The region kernel alone
takes about seven minutes with three prover processes on a heavily
loaded machine (its slowest check, a loop invariant of the scan, about 3
seconds); with the mask entry point and the shared builder it took four
minutes with two on a lightly loaded one. Every kernel together took
eighteen minutes with three.

The blob kernel (`AMV.Kernels.Blob` and its four private children) takes
about twenty minutes with two prover processes on a heavily loaded machine
(no check among the ten slowest of the project); every kernel together,
the blob kernel included, took an hour with two. With the fifth child,
`Extrema` (the extrema-angle measures, the boxes at an angle and the
medians), the kernel has 2480 checks (302 by flow analysis, 2178 by the
provers; 428 in `Extrema`) and proved from scratch in about forty-five
minutes with two prover processes on a heavily loaded machine (load
about 12: the CI and another proof run shared it). No check of
`Extrema` needed more than a second there; the slowest of the kernel
were the precondition of `Find_Features` in `Execute` (18 seconds; two
assertions that give the sides of the segmentation matrix now take it
below the four slowest) and, in unchanged code of `Measures`, the
postcondition of `Central_Moments` (7 seconds) and two overflow checks
of the centroid (4 and 6 seconds).

Soft segmentation (SoftFixedThreshold and SoftRelativeThreshold) changed
`Segmentation` (the level rule `Soft_Level`, the Gold postcondition of
`Segment_Soft`, `Soft_Band`, the morphology on the levels), `Measures`
(the weighted sums of `Weight_Pass` and `Weighted_Central_Moments`) and
the parent unit (the five setters of the segmentation parameters, the
checks of the new fields, the soft path of `ks_blob_execute`). With
`Tree`, the kernel now has 3036 checks: 312 in `Segmentation` (131
before), 555 in `Measures` (452 before), 667 in the parent unit (616
before) and, unchanged, 683 in `Labelling`, 428 in `Extrema`, 133 in
`Ordering` and 258 in `Tree`. Each unit proved on its own with two
prover processes while the CI runner proved another branch on
the same machine (load 6 to 9): the parent unit in about four and a half
minutes, `Labelling` in six, `Extrema` in two and a half, `Tree` in one
and a half, `Measures` in about one and `Ordering` and `Segmentation` in
less. No check of the kernel needs more than 2 seconds there (the slowest
are the preconditions of the weighted second moments). Written inline,
the weighted second moments and the sums of the weighted centroid had
checks of 6 and 9 seconds; each now sits in a small function with a
range postcondition (`Central_Term`, `Centroid_Of`, `Per_Level`), as the
lessons below advise. The precondition of `Find_Features` in
`Execute`, which needed 18 seconds on a machine at load 12, is no longer
among the slowest.

The IP one-image kernel (`AMV.Kernels.IP_One_Image` and its seven private
children) takes about twenty-five minutes with two prover processes on a
heavily loaded machine (its slowest checks, loop invariants of the
convolution, need about 2 seconds); every kernel together, with it, took
about two hours with two while another proof run shared the machine.

The image processing geometry kernels (`AMV.Kernels.Image_Sampling`,
`Affine_Transform`, `Copy_Region`, `IP_Two_Image`, `Image_Convert`,
`Polar_Unwrap`, 1686 checks) take about fifteen minutes with two prover
processes on a heavily loaded machine, the polar unwrap kernel about half
of it (no check needs more than about 3 seconds).

The dimensioning kernels (`AMV.Kernels.Dimensioning` with its private
children `Planar` and `Ellipses`, and `AMV.Kernels.Dimensioning.Fitting`
with its private child `Fit_Ellipse`) take about ten minutes
together with two prover processes on a busy machine (1491 checks: 184 in
`AMV.Kernels.Dimensioning`, 149 in `Planar`, 231 in `Ellipses`, 498 in
`AMV.Kernels.Dimensioning.Fitting` and 429 in `Fit_Ellipse`; no check
among the ten slowest of the project). Every kernel together, these
included, took two hours with two on a heavily loaded machine (several
other proofs running at the same time).

The fixture and calibration kernels (`AMV.Kernels.Calib_Fix` with its
private children `DOF_Fits` and `Checkerboard`; 2395 checks in
gnatprove's summary, flow checks included, of which the provers prove
2066: 763 in `AMV.Kernels.Calib_Fix`, 243 in `DOF_Fits` and 1060 in
`Checkerboard`) took about four minutes with two prover processes on a
heavily loaded machine before the detector's X-junction test and grid
growth; the detector alone (1191 checks, 1060 by the provers) now takes
about eight minutes with two on a heavily loaded machine, where it took
four and a half before (its slowest check, a precondition of the
bilinear samples of the X-junction test's ring, about 7 seconds; the
others under 3). Every kernel together, these included, took two hours
and fifty minutes with two while several other proofs shared the
machine (before the detector's change).

The nonlinear mode of the checkerboard calibration
(PerspectiveAndRadialWarp) added the private children `Radial` (the
fit), `Warp` (the warp) and `Solver` (the linear systems). Each unit of
the calibration kernel proves on its own from scratch (`-f`) with two
prover processes on a busy machine (load about 2.5): `Solver` in under a
minute, `Radial` and `Warp` in about one and a half minutes each (none of
their checks needs more than 2 seconds), `DOF_Fits` in about one,
`Checkerboard` in about two and a half and `AMV.Kernels.Calib_Fix` in
about seven. gnatprove's summary of the six units: 3241 checks, flow
checks included, of which the provers prove 2756 (485 flow); with
`--report=all` gnatprove reports 1009 checks in `AMV.Kernels.Calib_Fix`,
1149 in `Checkerboard`, 324 in `DOF_Fits`, 411 in `Radial`, 180 in `Warp`
and 48 in `Solver`. The detector's slowest check, the precondition of the
corner distance in `Near_Corner`, needed 29 seconds on this machine
(on main as well, before this change); the bound it needs is now asserted
once before the loop, which needs 3 seconds (no check of the six units
needs more), and the detector proves in two and a half minutes instead
of seven and a half.

The origin adjustment of the calibrations (`Ks_Calibration_Adjustment`,
`Valid_Adjustment` in `Valid_Calibration`, the four `ks_calibration_*`
entry points and `Restore_Adjustment`) changed only the parent unit.
gnatprove's summary of the six units is now 3328 checks, flow checks
included, of which the provers prove 2819 (509 flow); with
`--report=all` gnatprove reports 1096 checks in `AMV.Kernels.Calib_Fix`
(1009 before) and, unchanged, 1149 in `Checkerboard`, 324 in `DOF_Fits`,
411 in `Radial`, 180 in `Warp` and 48 in `Solver`. The six units took
about twelve minutes with two prover processes on a busy machine (load
about 3 to 4); no check of the parent unit needs more than 2 seconds (the
slowest of the six is still the detector's, 7 seconds).

PerspectiveAndRadialWarp for N-point calibrations changed the parent unit
(the N-point fit `Calibrate_N_Point_Warp`, `Fit_Corners`, the entry point
`ks_calibration_n_point_tool_execute`, `Valid_Model` and
`Valid_Calibration`), `Radial` (observed points with real plate
coordinates, the collinearity test `Flat`) and `Warp` (the plate's
normalisation in `Build_Model`). gnatprove's summary of these three units:
2075 checks, flow checks included, all proved: 340 by flow analysis and
1735 by the provers (1088 in `AMV.Kernels.Calib_Fix`, 420 in `Radial`,
227 in `Warp`). They took about forty minutes with two prover processes
while the CI runner proved another branch on the same machine (load 4 to
7); the slowest check needs 4 seconds (the overflow check of the
normalised input pixel in `Warp.Output_From_Input`, unchanged code), no
new check more than 2. `Checkerboard`, `DOF_Fits` and `Solver` did not
change.

The CNL search kernels (`AMV.Kernels.CNL_Search` with its private
children `Levels`, `Correlation` and `Search`, 1999 checks before the
AffineTransform region mode: 1751 proved
by the provers, 838 of them in `AMV.Kernels.CNL_Search`, 336 in
`Levels`, 395 in `Correlation` and 182 in `Search`, and 248 by flow
analysis; 1668, 1462, 727, 314, 239, 182 and 206 before partial matches,
1373, 1199, 623, 235, 159, 182 and 174 before the train image mask) took
about half an hour from cold with two prover processes on a machine
shared with two other proof runs (load about 10 on 10 cores), and nine
minutes again with a prover cache after the last changes; no check needs
more than 4 seconds (with the mask, about eight minutes and 2 seconds on
a less loaded machine; before it, about eleven minutes, no check above
about 3 seconds). Every kernel together (23867 checks before the mask)
took two hours and three quarters with two on a heavily loaded machine
(another proof run sharing it). With the AffineTransform region mode the
parent has 1010 checks (885 proved by the provers, 125 by flow analysis)
and its public child `Region_Modes` 159 (132 and 27); the two took about
eleven and three minutes with two prover processes on a machine loaded
by other work (load 12 to 17), no check above 1 second. The private
children did not change.

The pattern location kernel (`AMV.Kernels.PM_Align` with its private
children `Poses`, `Pyramids`, `Training`, `Search` and `Refinement`,
1770 checks, of which the provers discharge 1490: 394 in
`AMV.Kernels.PM_Align`, 149 in `Poses`, 184 in `Pyramids`, 97 in
`Training`, 316 in `Search` and 350 in `Refinement`; 1745 and 1474
before the search chose the grain at run time, 1653 and 1391 before
training thinned the features by grid cells and the clutter counted
edges by the training rule) takes about forty
minutes with two prover processes on a heavily loaded machine (two other
proof runs shared it; `Search` and `Refinement` about ten to fifteen
minutes each). Every kernel together, this one included, took two and a
half hours with two on that machine.

The shape creation kernel (`AMV.Kernels.Create_Shapes`, 143 checks: 92
discharged by the provers and 51 by flow analysis) takes under a minute
with two prover processes on a busy machine (its slowest check, a
postcondition of `Map_Circle`, about 4 seconds). Every kernel together,
this one included (27515 checks), took about three hours with two on a
heavily loaded machine (other proof runs sharing it).

The tool group kernel (`AMV.Kernels.Tool_Group`, 1126 checks in
gnatprove's summary, of which the provers discharge 974) takes about
forty seconds with two prover processes on a busy machine. Every kernel
together, this one included (28498 checks, before the shape creation
kernel), took three hours with two on
a heavily loaded machine (another proof run sharing it).

`amv.gpr` proves every unit at `--level=2`, except the units its `Prove`
package raises.

## Kernels

| Kernel | Entry points (C) | Proved | Level |
|---|---|---|---|
| `AMV.Kernels` | `ks_abi_version` | absence of run-time errors; `Set_Failure` / `Set_Success` leave a valid status (code in range, length 0 .. 200) | 2 |
| `AMV.Kernels.Numerics` (private) | none (internal helpers) | absence of run-time errors; `Hypot` in [0, 2 max(abs X, abs Y)]; `Reduce_Two_Pi` / `Direction` in (-Pi, Pi], `Reduce_Pi` in (-Pi/2, Pi/2]; bounds of `Mul`, `Mul_Small`, `Times_Unit`, `Times_Small`, `Unit_Ratio`, `Ratio_Within`, and the sign of `Mul`, `Times_Unit` and `Times_Small` for non-negative factors | 2 |
| `AMV.Kernels.Otsu` | none (internal: Otsu's threshold, shared by the Blob tool's HardDynamicThreshold and `ks_histogram_result_minimum_wgv_threshold`) | absence of run-time errors for any counts (the sums bounded by the count limit, the criterion computed with the bounded products of `AMV.Kernels.Numerics`); the threshold is `No_Split` or in 1 .. 255. **Not proved** (tested against a brute-force search of the within-group variance): that it maximises the criterion | 2 |
| `AMV.Kernels.Misc` | `ks_misc_deg_to_rad`, `ks_misc_rad_to_deg`, `ks_misc_norm_angle`, `ks_misc_norm_angle_pi`, `ks_misc_angle_difference`, `ks_misc_hypot` | absence of run-time errors (no overflow for any finite input); every status valid with only the documented failure codes; **`Norm_Angle` and `Angle_Difference` in (-Pi, Pi], `Norm_Angle_Pi` in (-Pi/2, Pi/2]** (Gold); `Hypot` >= 0 | 2 |
| `AMV.Kernels.Transforms` | `ks_transform_2d_linear_*` (decompose, aspect, recompose, recompose_scaling_aspect, set_property, create_similarity, map_point, map_vector, map_angle, invert, compose, matrix_determinant, map_area, get_matrix_element, set_matrix_element, identity, matrix_identity, singular, is_similarity, is_axis_aligned) | absence of run-time errors for every finite input; **every transform, point and area returned is within the bound of 1.0E150** (so it is a valid argument again), scalings within 2.0E150, angles in (-Pi, Pi]; `Create_Similarity` gives A = D and B = -C exactly; `Get_Matrix_Element` returns exactly the element at (Row, Column) and `Set_Matrix_Element` changes exactly that element (Gold); a Row or Column outside 0 .. 1 always fails with Bad_Parameter; only the documented failure codes | 2 |
| `AMV.Kernels.Coordinate_Spaces` | `ks_coordinate_space_tree_*` (init, add_space, change_transform, delete_subtree, clear, space_exists, space_count, space_name, root_name, parent_name, child_names_count, child_name, all_child_names_count, all_child_name, verify_name, parent_from_child_transform, get_transform) | absence of run-time errors for any record a caller passes (the tree is checked first); **every entry point that changes a tree leaves it valid when it succeeds and unchanged when it fails** (Gold): `Valid_Tree` = 1 to 64 entries, the root first, every other name its parent's name plus a valid component (so at most 256 characters), names strictly increasing in lexical order (so every parent before its children, no name twice), every Parent_From_Child transform within 1.0E150; `Change_Transform` keeps the number of spaces, `Delete_Subtree` lowers it; the lexical order is proved transitive and total (ghost lemmas); returned transforms within 1.0E150, returned names within 256 characters (and empty for a negative `Verify_Name`), counts within 0 .. 64; codes and flags checked on entry; only the documented failure codes. Also the Ada-only helpers for the wrapper (`To_Space_Name` for strings with any bounds, `To_String`, `Same_Tree`, the stream checks) | 2 |
| `AMV.Kernels.Images` | `ks_image_8_grey_*` and `ks_image_16_grey_*` (create, destroy, width, height, get_pixel, set_pixel, fill, duplicate, get_row, set_row), `ks_image_24_planar_color_*` (create, get_pixel, set_pixel, set_plane, duplicate), `ks_image_*` (selected_space_name, set_selected_space_name, resolve_space_name, get_transform, selection_for_new_tree, set_pixel_from_root_transform) | absence of run-time errors for any handle that is null or came from create or duplicate, and for any tree record (checked first); **no memory leaks** (SPARK ownership: every handle is owned, destroy frees its pixels and the record, and every failure path frees what it allocated, also when the second or third plane of a colour image cannot be allocated); every handle created is valid (`Valid_Image`: Height rows of Width pixels indexed from 0) and Width * Height <= 2**31 - 1; **pixels (Gold)**: create and fill set every pixel, get_pixel returns exactly the pixel, set_pixel changes exactly that pixel and no other, `Set_Row` changes exactly row Y and `Get_Row` copies it element by element, duplicate and set_plane copy every pixel, `From_Matrix` / `To_Matrix` copy element by element, a failed call changes no pixel and no size, and the lean `Try_*` variants succeed exactly when the entry point does, with the same effect; colour entry points need three planes of one size; set_pixel_from_root_transform stores exactly the transform given and only a bounded, invertible one; Get_Transform results within 1.0E150; names returned fit (256 characters); only the documented failure codes. Also the Ada-only stream helpers: sizes within the limit, counts and name lengths bounded, transforms decoded only from finite bits, the pixel cursor never reads or writes outside the image | 2 |
| `AMV.Kernels.Image_File` | `ks_image_file_decode`, `ks_image_file_count_for_update`, `ks_image_file_contents_*` (destroy, count, kind, image_info, check_read_index, get_8_grey, get_16_grey, get_24_planar_color, get_8_grey_converted), `ks_image_file_format_from_name`, `ks_image_file_choose_encoding`, `ks_image_file_encoded_size`, `ks_image_file_check_append`, `ks_image_file_encode_8_grey` / `_16_grey` / `_24_planar_color`, `ks_image_file_check_open_mode`, `ks_image_file_require_open`, `ks_image_file_require_mode`, `ks_image_file_tool_next_index` | absence of run-time errors for **any byte array** (a malicious or truncated header never makes the decoder read outside the bytes: every field is read after a `Need` or `Raster_Fits` check, and the rows of a BMP or binary PNM raster are shown to lie within the bytes with a monotonicity lemma on 128-bit ghost products) and for any contents handle that is null or came from decode (a handle whose header is inconsistent, or a slot that is not valid, is rejected with Bad_Parameter); **no memory leaks** (every image a failed decode allocated is freed, also when the second or third plane of a colour image cannot be allocated; destroy frees every slot and then the record); **decode**: on success `Valid_Contents` (at least one image, exactly one for BMP, every slot a valid 8-bit, 16-bit or colour image with three planes of one size and a maxval that suits its type) and **no image has more than 8 pixels per byte of input** (`Within_Input`: the pixel data a header announces is checked against the bytes present before anything is allocated, so a header cannot cause a huge allocation); on failure the handle is null; the getters return valid handles (colour: three planes of one size); `Choose_Encoding` / `Encoded_Size` / `Check_Append` / `Tool_Next_Index` results within their codes and ranges (`Index = Next_Index mod Count`, `New_Count = Count + 1`, no separator for BMP); the encoders check the encoding, the image and that the byte array has exactly the encoded size before writing anything, and never write outside it; only the documented failure codes. Also the Ada-only helpers for the wrapper (`Check_File_Size`, `File_Too_Large`, `Check_Whole_Read`) and the stream helpers (`Read_Contents_Header`, `Read_Image_Header`, `Store_*`: counts and codes checked before use, a slot filled once, no sample above its maxval) | 2 |
| `AMV.Kernels.Shapes` | `ks_rectangle_*` (set_xy_width_height, set_center_width_height, get_center_width_height, contains_point, boundary_slack, get_bounding_box, area, perimeter, map, from_bounding_box), `ks_rectangle_affine_*` (set_center_lengths_rotation_skew, set_origin_lengths_rotation_skew, set_origin_corner_x_corner_y, get_corners, get_parent_from_child_transform, contains_point, boundary_slack, get_bounding_box, area, map), `ks_circle_*` (set_center_radius, contains_point, boundary_slack, get_bounding_box, area, map), `ks_ellipse_*` (set_center_xy_radius_xy_rotation, contains_point, boundary_slack, get_bounding_box, area, map), `ks_polygon_*` (create, destroy, duplicate, num_vertices, get_vertex, set_vertex, add_vertex, remove_vertex, clear, contains_point, boundary_slack, get_bounding_box, area, perimeter, map), `ks_circular_annulus_section_*` (set_center_radius_angle_start_angle_span_radial_scale, contains_point, boundary_slack, get_bounding_box, area, map), `ks_line_*` (set_xy_rotation, set_from_start_xy_end_xy, set_from_line_segment, set_distance_rotation, get_distance_rotation, map), `ks_line_segment_*` (set_start_end, set_start_length_rotation, get_start_length_rotation, get_midpoint, map), `ks_point_marker_*` (set_xy_rotation, map), `ks_circular_arc_*` (set_center_radius_angle_start_angle_span, get_start_end, map) | absence of run-time errors for every finite input and for any polygon handle that is null or came from this kernel (an inconsistent record is rejected with Bad_Parameter); **every shape, point and box returned is within its bound** (coordinates and angles 1.0E150, lengths 4.0E150, Radius * Radial_Scale 4.0E150), so it is a valid argument again: a map returns a valid shape of the type its code names, bounding boxes have Min <= Max, angles built from directions are in [-Pi, Pi]; areas in [0, 2**1022], perimeters in [0, 2**522], boundary slacks in [0, 1.0E145]; **the checks (Gold)**: each record check succeeds exactly when the record is valid, and the setters SetXYWidthHeight, SetCenterLengthsRotationSkew, SetCenterRadius, SetCenterXYRadiusXYRotation, SetCenterRadiusAngleStartAngleSpanRadialScale, SetXYRotation, SetStartEnd and SetCenterRadiusAngleStartAngleSpan return exactly the given properties; the rectangle's Contains_Point accepts only points within Boundary_Slack of its Get_Bounding_Box (the covering property AMV.Regions relies on); **polygon handles (Gold)**: no memory leaks (every failure path frees what it allocated, growing frees the old array), get_vertex returns exactly the vertex, set_vertex changes exactly that vertex, add_vertex inserts at the documented position and moves the later vertices up by one (also when the array grows), remove_vertex moves them down by one, duplicate copies every vertex, a failed call changes no vertex and no count; only the documented failure codes. Also the Ada-only helpers for the wrapper (`Same_Vertices` for `"="`, `Check_Stream_Count`) | 2 |
| `AMV.Kernels.Image_Math` | `ks_real_image_*` (create, destroy, width, height, get_pixel, set_pixel, fill, duplicate, from_8_grey, from_8_grey_window, to_8_grey, bilinear, bilinear_8_grey, is_inside, resample, resample_8_grey, gaussian_smooth, box_smooth, sobel, downsample_2, statistics) | absence of run-time errors for any real or 8-bit handle that is null or came from the kernels, any transform record and any finite or non-finite value; **no memory leaks** (every temporary image and table is freed on every path, also when a later allocation fails); **no overflow in any sum**: every pixel value is within ±1.0E100 (`Max_Value`) and the bound is chosen so that the window sums of `Box_Smooth`, the passes of `Gaussian_Smooth` and the sums and squared deviations of `Statistics` stay finite; **every image returned is bounded** (`Bounded_Image`: valid, and every pixel within ±1.0E100, so it is a valid argument again), with the size of the input (filters), `max (1, W / 2) x max (1, H / 2)` (`Downsample_2`) or the size asked for (`Resample`, windows); create and fill set every pixel, get_pixel returns exactly the pixel, set_pixel changes exactly that pixel and no other (Gold), duplicate copies every pixel, a failed call changes no pixel and no size, the lean `Try_*` variants succeed exactly when the entry point does, with the same effect; `Bilinear` results within ±1.0E100; `Is_Inside` 1 only for a point of a non-empty image; **`Statistics`: Minimum <= Mean <= Maximum, all within ±1.0E100, and 0 <= Std_Dev <= Maximum - Minimum**; only the documented failure codes. Also the Ada-only stream helpers (`Start_Read`, `Next_Read_Chunk`, `Store_Bits`, `Finish_Read`: the read state stays valid, the room grows only when every value allocated so far has arrived, values are stored only within it and only when finite and within the bound, the image is built from exactly Width x Height values; `Get_Bits` never reads past the image), and the helpers added to `AMV.Kernels.Numerics` (`Clamp`, `Clamp_Unit`, `Square`, `Mul_Within`, `Square_Within`: results within their stated bounds) | 2 |
| `AMV.Kernels.Geometry` | `ks_geometry_*` (distance, signed_distance, distance_to_line, project, position_along, distance_to_circle, intersect_lines, intersect_line_circle, intersect_circles, angle_between, fit_line, fit_line_robust, fit_circle, fit_circle_robust) | absence of run-time errors for any finite or non-finite argument and any point array (Ada) or C request (checked first); **every coordinate, length and radius returned is within ±1.0E150** (`Max_Coordinate`, so it is a valid argument again; a result beyond it fails with Bad_Parameter), distances, RMS errors and fitted radii >= 0, `Angle_Between` in (-Pi, Pi], the rotation of a fitted line in (-Pi/2, Pi/2], intersection counts in 0 .. 2 and the parallel flag 0 or 1; the fits scale the offsets from the centroid by exact static powers of two (`Exponent_Of`, `Power_Of_Two`, no `'Exponent` or `'Scaling`), and every moment, trial centre, cost, gradient and curvature term of the circle fit stays within a stated bound, so the iterations (Newton, damped Gauss-Newton, saddle escapes) cannot overflow; divisions by determinants are formed only below a bound, beyond which the centre has run off as before; `Check_Points` rejects every point that is not finite or within the bound; the robust fits restore `Used` after each trial and report only the documented failures; only the documented failure codes. Also the helper `Numerics.Quotient_Within` (as `Ratio_Within`, for a dividend up to 2**1022) | 2 |
| `AMV.Kernels.Regions` | `ks_pixel_region_*` (whole_image, destroy, duplicate, is_empty, pixel_count, bounds, contains, rasterize_rectangle, rasterize_rectangle_affine, rasterize_circle, rasterize_ellipse, rasterize_polygon, rasterize_circular_annulus_section, restrict_to_mask, bounding_box) | absence of run-time errors for any image size (up to `Max_Pixels`), any transform (checked against 1.0E150 first) and any region record or polygon handle (checked by the shape kernel first), for any region handle that is null or came from this kernel (an inconsistent record is rejected with Bad_Parameter; `contains` is safe for any record), and for any mask handle that is null or came from the image kernel and any offsets (an inconsistent mask is rejected with Bad_Parameter; the mask is read only at offsets computed in 64 bits and tested against its size); **no memory leaks** (every failure path frees what it allocated; the candidate flags, and the flags of the region's rectangle for a mask, are freed or become the result's before the call returns); every rasterised result lies in the image; **Gold**: every handle returned is `Consistent`: `Count` is the number of pixels `Contains` accepts (Width * Height without flags, otherwise the number of True flags, a recursive ghost count `Count_Of` that the counting loop is proved to compute) and the bounding rectangle is the smallest one (a True flag in its first and last row and column; the search for the rectangle keeps a witness for each, a stream read checks them); both builders, rasterisation and the mask, set one flag per pixel and hand the matrix to one proved procedure (`Build_Region`: for every flag, `Contains` of the result is exactly the flag, and the result's rectangle lies within the flags), which keeps it, shrinks it or frees it; `Contains` (`ks_pixel_region_contains`) is exactly the stored flag inside the rectangle, 1 inside a rectangle without flags, 0 outside; `Rasterize_Box`, which every rasterize entry point calls after its checks and `Candidate_Box`: for every pixel of the candidate box, `Contains` of the result is exactly `Inside` (the pixel centre mapped by the inverse transform as ks_transform_2d_linear_map_point maps it, within 1.0E150, and accepted by the shape's Contains_Point, which the shape kernel proves equal to its entry point), and the result's rectangle lies in the box; `Restrict_To_Mask` (`ks_pixel_region_restrict_to_mask`): for every pixel of the given region's rectangle, `Contains` of the result is exactly `Contains` of the region and `Cared_For` (no mask pixel lies over the pixel, or the one that does is not 0), and the result's rectangle lies in the region's, so the result holds exactly the region's pixels that the mask does not mark "don't care" (null for the empty region, a valid mask required); flags are kept only when not every pixel of the rectangle is included (a ghost lemma shows that a full count means every flag is set); duplicate copies the rectangle, the count and every flag. **Not proved** (tested): that the candidate box holds every pixel `Inside` accepts, a floating-point covering argument (the shape kernel proves "accepted points lie within Boundary_Slack of the bounding box" for the rectangle only, and the half pixel of rounding margin is argued in AMV.Regions). Also the Ada-only helpers for the wrapper and the other kernels (`Check_Rasterize`; `Shift_To_Origin`, Gold: the result has the region's size and count, starts at pixel (0, 0), and `Contains` of the result at (X, Y) is exactly `Contains` of the region at (X_Min + X, Y_Min + Y); and the stream helpers: every header field checked as AMV.Regions documents before anything is allocated for the pixels, a buffer that grows only with the elements read, the elements copied into the flag matrix with a 128-bit index lemma, the count and the smallest rectangle checked on the result) | 2 |
| `AMV.Kernels.Filter_Inputs` (private) | none (the input checks of the four filter kernels below) | absence of run-time errors; a usable image (valid, Width * Height <= Max_Pixels) and a null or valid region on success; only the documented failure codes | 2 |
| `AMV.Kernels.Histogram` | `ks_histogram_run_params_default`, `ks_histogram_execute`, `ks_histogram_result_*` (destroy, statistics, bin, inverse_cumulative_grey_level, minimum_wgv_threshold) | absence of run-time errors for any image or region handle that is null or came from the kernels and any parameters (codes and sizes checked first); **no memory leaks**; **Gold: every bin of a result holds exactly the number of samples whose grey level falls into it** (`Bin_Count`, a recursive ghost count over the pixels the region contains, in every bin mode, and the counts per grey level likewise) and **Num_Samples is the number of pixels of the image the region contains** (`Sample_Count`); every count fits in an Int32 (a 128-bit bound from the image's size); `Bin_Of` lies within the bins (the uniform bin by a nonlinear lemma); **Minimum <= Median, Mode, Mean <= Maximum** within 0 .. 255, Variance in [0, 65025], Standard_Deviation in [0, 255] (`Valid_Result`, which the accessors also check at run time); the accessors return exactly the stored values (the last bin index in 0 .. 65535) and the inverse cumulative grey level lies in [Minimum, Maximum]; only the documented failure codes. The input image mask is applied to the region before the kernel runs, by `ks_pixel_region_restrict_to_mask` (proved in `AMV.Kernels.Regions`), so the Gold counts above are over the pixels the mask cares for | 2 |
| `AMV.Kernels.Histogram.Region_Modes` | `ks_histogram_execute_affine` (and, for Ada, `Check_Region_Mode`) | absence of run-time errors for any image handle that is null or came from the image kernel, any affine rectangle, transform and parameters (checked by `AMV.Kernels.Affine_Transform` and `ks_histogram_execute`); no memory leaks (the resampled image and its whole region are freed on every path); only the documented failure codes; a result is a valid histogram (`Valid_Result`) and the parameters valid when the call succeeds; `Check_Region_Mode` accepts exactly the three codes and, with AffineTransform and a region, only an affine rectangle without a mask. `ks_pixel_region_bounding_box` (in `AMV.Kernels.Regions`): **Gold**: the result is a consistent region without flags over exactly the bounding rectangle of the region (every pixel of it), null for the empty region | 2 |
| `AMV.Kernels.Pixel_Map` | `ks_pixel_map_run_params_default`, `ks_pixel_map_execute` | absence of run-time errors for any handles; no memory leaks; the output has the size of the input and **(Gold) every output pixel the region contains is Map (input pixel), every other one the input pixel**; only the documented failure codes | 2 |
| `AMV.Kernels.Sobel_Edge` | `ks_sobel_edge_run_params_default`, `ks_sobel_edge_execute` | absence of run-time errors for any handles and parameters (a non-finite MagnitudeScale is rejected); **no memory leaks** (the floating-point images and the work stack are freed on every path, the three output images when a later one cannot be allocated); the three images have the size of the input and **every pixel outside the region is 0 in all three**; with None the final image equals the magnitude image, with PeakDetect every final pixel is 0 or the magnitude pixel, with HysteresisThreshold every final pixel of the region is the survivor or the non-survivor value; only the documented failure codes. **Not proved** (tested): that the hysteresis survivors are exactly the pixels connected to a seed, and the values of the magnitude and angle pixels (their ranges follow from their type) | 2 |
| `AMV.Kernels.Sobel_Edge.Region_Modes` | `ks_sobel_edge_execute_in_box`, `ks_sobel_edge_execute_affine` (and, for Ada, `Check_Affine_Region`) | absence of run-time errors for any image or region handle that is null or came from the kernels and any parameters (the checks of `ks_sobel_edge_execute` first, then the region mode); **no memory leaks** (the box, the resampled rectangle and the work regions are freed on every path); only the documented failure codes; **Gold**: the three images have exactly the size of the region's bounding box (`execute_in_box`) or of the rectangle resampled by `AMV.Kernels.Affine_Transform` with its default run parameters (`execute_affine`), `Output_From_Input` is exactly the shift by the box's corner, and with PostProcessMode None the final image equals the magnitude image. The pixels come from the proved entry points it calls (`ks_copy_region_execute`, `ks_sobel_edge_execute`, `ks_affine_transform_execute`). **Not proved** (tested against running the tool on the box as an image of its own and on the affine transform tool's output): the pixel values of the composition | 2 |
| `AMV.Kernels.Image_Sharpness` | `ks_image_sharpness_run_params_default`, `ks_image_sharpness_execute` | absence of run-time errors for any handles and parameters (every Long_Float parameter checked for finiteness and range); no memory leaks; **the score is finite and >= 0**, at most 32512.5 (GradientEnergy) or 255 (AbsDiff), and 0 when the call fails; only the documented failure codes | 2 |
| `AMV.Kernels.Blob` (with the private children `Segmentation`, `Labelling`, `Measures`, `Extrema`, `Ordering`) | `ks_blob_run_params_default`, `ks_blob_segmentation_params_set_hard_fixed_threshold`, `_set_hard_relative_threshold`, `_set_hard_dynamic_threshold`, `_set_soft_fixed_threshold`, `_set_soft_relative_threshold`, `ks_blob_measure_collection_add`, `ks_blob_morphology_collection_add`, `ks_blob_execute`, `ks_blob_results_*` (destroy, count, item, get_blob_by_id, get_parent, get_boundary, get_bounding_box_at_angle, get_median_x, get_median_y, create_blob_id_image, create_blob_image, create_segmented_image), `ks_blob_result_get_measure`, `ks_blob_result_get_bounding_box` | absence of run-time errors for any image handle that is null or came from the image kernel, any region handle that is null or came from the region kernel (an inconsistent one, or one that does not lie in the image, is rejected with Bad_Parameter), any run parameters (every code, count, threshold and filter range checked first, NaN included; ExtremaAngle finite and within 1.0E6), any angle of `get_bounding_box_at_angle` (the same bound) and any axis code, any transform (entries within 2**64 and a translation within 1.0E140 checked first) and any results handle that is null or came from execute (its structure, `Valid_Results`, is checked by every accessor; table entries are read through range tests); **no memory leaks** (every table is freed on every path, also when a later allocation fails); every handle returned is `Valid_Results`; the union-find searches end on any table (they follow parents only while they decrease, at most Label steps); every sum of the measures is bounded (see the guards below), so every position, box and length is finite and within the bounds of `AMV.Kernels.Shapes`; only the documented failure codes. **Gold**: (a) segmentation (`Segmentation.Segment`): every pixel of the region's bounding rectangle is classified exactly by `Expected_Segment`, that is by the threshold rule `Is_Foreground` (grey value >= T for light blobs, < T for dark blobs) with the threshold `Compute_Threshold` of the run parameters (HardFixedThreshold exactly for the fixed mode, 1 for None), outside for a pixel not in the region; (a') soft segmentation (`Segmentation.Segment_Soft`, SoftFixedThreshold and SoftRelativeThreshold): every pixel of the region's bounding rectangle gets exactly the level `Expected_Level`, that is AMV's level rule `Soft_Level` (0 .. Softness + 1 by the band [Low, High) and the polarity; its postcondition also proves the levels inside the band lie in 1 .. Softness), and the class `Expected_Soft_Segment` that follows from it (foreground when the level is above 0); the band of the fixed mode is exactly SoftFixedThresholdLow and High, and Low <= High in both modes (`Soft_Band`); the setters (`Set_Hard_Fixed_Threshold` .. `Set_Soft_Relative_Threshold`) succeed exactly when their arguments are valid, and then change Mode and the fields they name and nothing else (a delta aggregate in the postcondition), and otherwise leave the parameters unchanged; (b) counting (`Labelling.Find_Features`, the step that numbers the features and counts their pixels): every feature has at least one pixel, and the areas of the blobs add up to `Blob_Pixel_Count`, the number of pixels the feature map gives to blobs (the foreground after the cleanup), a recursive ghost count over the map as in `AMV.Kernels.Regions`; (c) sorting (`ks_blob_execute`): with SortEnabled the filtered collection is in the order of SortMeasure (`Sorted`: ascending or descending, for every adjacent pair of `Order`), from a stable merge sort proved with conditional postconditions on its two runs; (d) extrema angle (`Extrema`): the extents of a feature along an axis (`Feature_Extent`, from which `get_bounding_box_at_angle` builds its box) contain the coordinate of every pixel centre the feature map gives to the feature (a quantified postcondition over the map), so the box, which widens them by half a mapped pixel square, contains every mapped pixel centre; a median lies within the least and greatest of the values it is selected from (`Select_Median`; the selection loop ends: each three-way partition removes at least its pivot from the window, a loop variant); and for every result, `Extrema_Angle_Min_X <= Median_Extrema_Angle_X <= Extrema_Angle_Max_X` and likewise in y (`Finish_Item`, from a subtype predicate on the per-feature statistics); (e) images of the results: the saved segmented image before masking holds the level of every pixel of the region's bounding rectangle by the threshold rule or `Soft_Level`, whether the pixel lies in the region or not (`Segmentation.Segment_Box_Hard`, `Segment_Box_Soft`), and the hard stages hold 1 exactly for foreground (`Segmentation.To_Levels`); every pixel of the image of `create_blob_image` is `Blob_Image_Value` (background 128 or Background where no painted feature owns the pixel, 0 for a hole, the label or the level of a blob, viewable levels within 192 .. 255 and 255 at full weight, `Viewable_Level`) and every pixel of the image of `create_segmented_image` is `Segmented_Value` (the saved value, 0 outside the rectangle, or value * 255 / Full when stretched), a quantified postcondition over the whole image; a stage that was not saved gives null. **Not proved** (tested): that the merge sort permutes the IDs, that the labels follow the 8- and 4-connectivity, the hole tree, the accuracy of the measures, that the selection gives the middle value (tested against sorting, with even and odd counts), that every pixel of a feature reaches the selection of `ks_blob_execute` (its tables are read through range tests that never fail), the grey morphology on the levels of a soft segmentation and the weighted measures (tested against brute-force sums of the levels) | 2 |
| `AMV.Kernels.Blob.Tree` | `ks_blob_results_related_count`, `ks_blob_results_related_id`, `ks_blob_results_get_blob_measure` (and, for Ada, `Related_IDs`, `Blob_Measures`, `ID_At`, `Collection_Count`, `Collection_Item`) | absence of run-time errors for any results handle that is null or came from execute (`Valid_Results` and every ID of the filtered collection, `Valid_Order`, checked first), any relation, flag, ID, index and measure code, and lists of any bounds; only the documented failure codes. **Gold**: the list of a query (`Related_IDs`) holds exactly the related features of its collection in the collection's order: its length is their number, and the related feature at position P of the collection is at index `Matches_Before (P)` of the list, the number of related features before it (a recursive ghost count); `Related_Count` is that number and `Related_ID` the feature at an index; the measures are `Measure_Value` of each feature's result | 2 |
| `AMV.Kernels.Caliper` | `ks_caliper_*` (run_params_default, scorer_default, scorer_set_xy_parameters, scorer_get_kind, scorer_get_enabled, scorers_add, scorers_remove_at, scorers_count, check_run_params, execute, results_destroy, results_duplicate, results_count, results_item, results_profile_length, results_projection_value, results_filtered_value) | absence of run-time errors for any image handle that is null or came from the image kernel, any region, transform and run parameter record (non-finite values rejected with Bad_Parameter naming the property) and any results handle that is null or came from this kernel; **no memory leaks** (the profiles, the items and the record are freed on every failure path); the sample grid is bounded before anything is allocated (at most 32768 samples per side, 2**24 in all, every step at most 2 pixels, every sample point finite); grey values, profile values and contrasts within [-255, 255]; **Gold, of every results handle `ks_caliper_execute` returns** (`Gold_Results`): at most MaxResults results, **sorted by score (highest first)**, every score in [0, 1], every edge position and every result position within half the search length of the region's centre (`Half_Length`, itself within 1.0E150), every width in [0, the search length], every result point within 1.0E150, both profiles Nx values long; the bounded insertion that keeps the best candidates is proved to keep its buffer sorted and every candidate's edges inside the profile; `results_item` returns exactly the stored item; `scorers_add` / `scorers_remove_at` / `scorer_set_xy_parameters` change exactly what they document and nothing on failure; `scorers_count`, `scorer_get_kind` and `scorer_get_enabled` return exactly the field when it is valid (a count in 0 .. 8, a kind code, 0 or 1) and fail with Bad_Parameter otherwise, so the Ada API converts only checked values; only the documented failure codes. Also the Ada-only helpers `Check_Nested_Run_Params` and `Get_Profile` | 2 |
| `AMV.Kernels.Find_Line` | `ks_find_line_*` (run_params_default, caliper_region, execute, results_destroy, results_count, results_item, results_caliper_results, results_line, results_fit) | absence of run-time errors for any argument (the run parameters, the caliper parameters they hold and the transforms checked first, non-finite values rejected) and any results handle that is null or came from this kernel; **no memory leaks** (the results are built in place and every failure path destroys them with every caliper's results they hold); **Gold, of every results handle `ks_find_line_execute` returns**: one item and one caliper results handle per caliper (Count = NumCalipers), Used only for a found item, **NumPointsFound and NumPointsUsed exactly the numbers of found and used items** (recursive ghost counts), so NumPointsUsed <= NumPointsFound <= NumCalipers; the line and the segment valid shapes (within 1.0E150), distances and the RMS error in [0, 1.0E150]; `results_item` returns Found and Used 0 or 1; the caliper regions valid rectangles; only the documented failure codes | 2 |
| `AMV.Kernels.Find_Circle` | `ks_find_circle_*` (run_params_default, caliper_region, execute, results_destroy, results_count, results_item, results_caliper_results, results_circle, results_fit) | as for `AMV.Kernels.Find_Line` (no leaks; `results_item` returns Found and Used 0 or 1; **Gold**: one item and one caliper results handle per caliper, Used only for a found item, NumPointsFound and NumPointsUsed exactly the found and used items, NumPointsUsed <= NumPointsFound <= NumCalipers); the circle and the arc valid shapes, distances and the RMS error in [0, 1.0E150]; the fixed-radius fit (our own alternating minimisation) free of overflow for any points, radius and start within the bounds, its sums and costs within stated limits; the curvature correction (`Sag_Of`, `Shift`) moves every point by at most the radius over 6 and keeps it within ±1.0E150; only the documented failure codes. **Not proved** (tested): the accuracy of the correction | 2 |
| `AMV.Kernels.IP_One_Image` (with the private children `Common`, `Pointwise`, `Morphology`, `Median`, `Smoothing`, `Convolution`, `Flip_Rotate`, `Sampling`) | `ks_ip_one_image_*` (operators_default, operator_default, operator_get_kind, operator_get_enabled, operators_count, operators_item, operators_set_item, operators_add, operators_insert, operators_remove_at, operators_move, convolve_nxm_get_kernel_value, convolve_nxm_set_kernel_value, convolve_3x3_get_kernel_value, convolve_3x3_set_kernel_value, sigma, check_operators, execute, execute_masked) | absence of run-time errors for any image or region handle that is null or came from the kernels and any operator list (the count, every code, size and real of the operators checked first, NaN included; the convolution kernels read through a limit); **no memory leaks** (every intermediate image and work line is freed on every path, the image of the pipeline when a later operator fails); no trusted code of its own (every buffer is an image of `AMV.Kernels.Images`, the work lines of the running extrema one-row images); the list entry points change exactly what they document and nothing on failure (`Add` and `Insert` keep the other items in place or moved up by one, `Remove_At` moves the later ones down, `Set_Item` changes one item, `Move` puts the item where it is asked); `operators_count`, `operator_get_kind` and `operator_get_enabled` return exactly the field when it is valid (a count in 0 .. 16, a kind code, 0 or 1) and fail with Bad_Parameter otherwise; **Gold**: (a) `ks_ip_one_image_execute`: the output's Width and Height are those `Size_After` (a recursive function over the list, also used to reject an image of more than 2**31 - 1 pixels before any pixel is computed) computes from the input's: swapped by a quarter turn, divided rounding up by the sampling of SubSampler and GaussSampler, multiplied by Expand; for a list that does not change the pixel grid, **every output pixel outside the region equals the input pixel** and `Output_From_Input` is the identity (a loop invariant over the list, each operator proved to copy the pixels it does not select); (b) per operator (the postconditions of the private children): Threshold gives exactly HighValue or LowValue by its rule, AddSubtractConstant and MultiplyConstant give their value limited to 0 .. 255 (Bounded) or modulo 256 (Wrap), Quantize and PixelMap their exact tables, the convolutions the window sum rounded and limited to 0 .. 255 (`To_Grey (Convolution_Sum (..))`), erosion never above and dilation never below the input pixel, FlipRotate every pixel exactly where its table puts it, Expand and SubSampler without the mean every pixel exactly from where their definitions take it, PelSet PelValue exactly in the selected pixels its mask and Operation select (`Sets_Pixel`) and the input elsewhere; every enabled PelSet has a valid mask (`Check_Masks`). **Not proved** (tested against brute force): that the running extrema are the window extrema, that the running histogram gives the median, the binomial and box sums, the equalisation table, the block means of SubSampler, the HighPassFilter values, `Output_From_Input` of the sampling and the expansion (computed in floating point; tested to 1e-9 px) | 2 |
| `AMV.Kernels.IP_One_Image.Region_Modes` | `ks_ip_one_image_execute_in_box`, `ks_ip_one_image_execute_affine` (and, for Ada, `Affine_Region`) | absence of run-time errors for any image or region handle that is null or came from the kernels, any region mode code and any operator list (checked by `Check_Operators` first); **no memory leaks** (the box, the intermediate image of the Adjust_Mask mode, the resampled rectangle and the work regions are freed on every path); only the documented failure codes; **Gold**: for a list that keeps the pixel grid, `execute_in_box` returns an image of exactly the region's bounding box and `Output_From_Input` is exactly the shift by the box's corner, and `execute_affine` an image of exactly the size `AMV.Kernels.Affine_Transform` gives the rectangle with its default run parameters. The pixels come from the proved entry points it calls (`ks_copy_region_execute` for the box, `ks_ip_one_image_execute_masked` for the operators, `ks_affine_transform_execute` for the rectangle). **Not proved** (tested against running the operators on the box as an image of its own and on the affine transform tool's output): the pixel values of the composition | 2 |
| `AMV.Kernels.Image_Sampling` (private) | none (the input checks, the mapping of output pixels and the sampling of the five image processing geometry kernels below) | absence of run-time errors; a usable image on success of `Check_Image`; mapped points within 2**1022 (`Map_X`, `Map_Y`, for a transform within 1.0E150 and coordinates within `Numerics.Mul_Limit`); `Nearest_Index` within the image; `Bilinear_Sample` is the fill value for a point outside the image and indexes the image only for a point inside it; only the documented failure codes | 2 |
| `AMV.Kernels.Affine_Transform` | `ks_affine_transform_run_params_default`, `ks_affine_transform_execute` | absence of run-time errors for any image handle that is null or came from the image kernel and any region, transform and parameter values (non-finite ones rejected with Bad_Parameter naming the property); a sample point becomes an index only when it lies in the input image; no memory leaks (the output is freed when the mask cannot be allocated and when ClipMode Error fails the run); the output's pixel-from-root transform within 1.0E150 and invertible within it; **Gold**: the output is exactly round (ScalingX * L_X) by round (ScalingY * L_Y) pixels (`Output_Width`, `Output_Height`, the side lengths in pixels from `Pixel_Side_Length`), within 1 .. 32767; with NearestNeighbor every output pixel is exactly the input pixel nearest to its sample point or the fill value (`Nearest_Sample` at the mapped centre, proved in `Resample`; the entry point states "the fill value or an input pixel", derived per pixel by a ghost lemma); the mask is 0 or 255, and exactly 255 where the sample point lies in the input (`Fill_Mask`); only the documented failure codes | 2 |
| `AMV.Kernels.Copy_Region` | `ks_copy_region_run_params_default`, `ks_copy_region_execute` | absence of run-time errors for any image or region handle that is null or came from the kernels (a region that does not lie in the image is rejected) and any parameter values; no memory leaks; the output's pixel-from-root transform within 1.0E150 and invertible within it; **Gold**: the output has the size of the region's bounding box and every output pixel is exactly `Copied_Pixel`: the input pixel at its place, FillRegionValue for a pixel of the region when FillRegion is set, FillBoundingBoxValue for any other pixel of the box when FillBoundingBox is set; only the documented failure codes | 2 |
| `AMV.Kernels.IP_Two_Image` | `ks_ip_two_image_add_*`, `ks_ip_two_image_subtract_*`, `ks_ip_two_image_min_max_*` (run_params_default, execute) | absence of run-time errors for any image handles that are null or came from the image kernel and any codes; no memory leaks; **Gold**: the two inputs have one size, the output has it too, and every output pixel is exactly the formula of the tool applied to the two input pixels at its place (`Add_Pixel`: bounded, wrapped or halved sum; `Subtract_Pixel`: bounded, wrapped, offset-halved or absolute difference; `Min_Max_Pixel`), as AMV.Kernels.Images proves its fills; only the documented failure codes | 2 |
| `AMV.Kernels.Image_Convert` | `ks_image_convert_run_params_default`, `ks_image_convert_execute` | absence of run-time errors for any image handles that are null or came from the image kernel (exactly one kind of input, colour planes of one size) and any parameter values, non-finite ones included; no memory leaks; **Gold**: the output has the size of the input and every output pixel is exactly the formula of the mode: the input pixel (8-bit Intensity), its high byte (16-bit Intensity), `Intensity_Of` = (299 R + 587 G + 114 B + 500) / 1000 in integers (colour Intensity: round (0.299 R + 0.587 G + 0.114 B), halves up, within 0 .. 255), the plane (Plane0 .. Plane2), or `Weighted_Intensity` (the weighted sum rounded and limited to 0 .. 255); only the documented failure codes | 2 |
| `AMV.Kernels.Polar_Unwrap` | `ks_polar_unwrap_run_params_default`, `ks_polar_unwrap_execute`, `ks_polar_unwrap_get_input_point_from_output_point`, `ks_polar_unwrap_get_output_point_from_input_point` | absence of run-time errors for any image handle that is null or came from the image kernel and any section, transform, parameter, point and revolution values (non-finite ones rejected); the sample points (cosines and sines of angles within 2.0E150, radii within 8.0E150, mapped by a transform within 1.0E150) become indices only inside the input image; no memory leaks (the output is freed when a sample is clipped); **Gold**: the output is exactly `Output_Width` by `Output_Height` pixels (the middle arc and the radial extent in pixels times the scalings, rounded), within 1 .. 32767; with NearestNeighbor every output pixel is an input pixel (exactly the one nearest to its sample point; a clipped sample fails the run); the points the two mappings return lie within 1.0E150; only the documented failure codes | 2 |
| `AMV.Kernels.Dimensioning` (with the private children `Planar` and `Ellipses`) | `ks_distance_point_point_execute`, `ks_angle_point_point_execute`, `ks_angle_line_line_execute`, `ks_distance_*_execute` (point_line, point_segment, point_circle, point_ellipse, segment_segment, segment_line, line_circle, segment_circle, circle_circle, line_ellipse, segment_ellipse), `ks_intersect_*_execute` (line_line, segment_line, segment_segment, line_circle, segment_circle, circle_circle, line_ellipse, segment_ellipse) | absence of run-time errors for any argument, NaN and infinities included (every coordinate, radius and transform checked first, every shape mapped by the shape kernel's map entry points); only the documented failure codes; **Gold, of every result record (`Valid_Result`)**: distances in [0, 4.0E150] where VisionPro documents them unsigned, in [-4.0E150, 4.0E150] where it does not (and never below -Radius for a point and a circle), every point within 1.0E150, angles in (-Pi, Pi], NumPoints in -1 .. 1, 0 .. 2 or -1 .. 2 as documented, Intersects = (NumPoints /= 0), the points not reported 0, the points of a distance of 0 between two shapes 0, and every value of a failed call 0. **Not proved** (tested): the accuracy of the distances and points, in particular of the bisection of the nearest point of an ellipse | 2 |
| `AMV.Kernels.Dimensioning.Fitting` (with the private child `Fit_Ellipse`) | `ks_fit_points_*` (num_points, set_num_points, add_point, delete_point, get_point, set_point, set_x, set_y, clear, duplicate, destroy), `ks_fit_line_run_params_default`, `ks_fit_circle_run_params_default`, `ks_fit_ellipse_run_params_default`, `ks_fit_line_execute`, `ks_fit_circle_execute`, `ks_fit_ellipse_execute`, `ks_fit_result_*` (destroy, kind, num_points, num_points_used, rms_error, get_xy_used_distance, get_line, get_circle, get_ellipse) | absence of run-time errors for any argument and any points or result handle that is null or came from these kernels (an inconsistent one is rejected with Bad_Parameter); **no memory leaks** (the result is built in place and destroyed on every failure path); the point list entry points change what they document (the polygon kernel's proved operations) and nothing on failure; **Gold, of every result an execute entry point returns (`Gold_Result`)**: one point, flag and distance per point given (Count = NumPoints), **NumPointsUsed exactly the number of used flags** (a recursive ghost count) **and at least the fewest points the fit needs** (2, 3, 4; 5 for an ellipse without the rotation constraint), every distance in [0, 4.0E150], the RMS error in [0, 4.0E150], a valid shape within the bounds (radii in (0, 1.0E150] for the ellipse), the radius exactly RadiusConstraint and the rotation exactly RotationConstraint when they are enabled; the ellipse fit (Halir-Flusser: moments, the inverse of the scatter, the reduced 3 x 3 matrix, the bisection of its characteristic polynomial, the eigenvector, the conic's centre, axes and angle, the closed form of the 2 x 2 problem) free of run-time errors for any points within the bounds, every intermediate quantity within a stated bound. **Not proved** (tested): the accuracy of the fits and that the greedy removal finds the outliers | 2 |
| `AMV.Kernels.Create_Shapes` | `ks_create_circle_execute`, `ks_create_ellipse_execute`, `ks_create_line_execute`, `ks_create_segment_execute`, `ks_create_line_bisect_points_execute`, `ks_create_line_parallel_execute`, `ks_create_line_perpendicular_execute`, `ks_create_segment_avg_segs_execute` | absence of run-time errors for any argument, NaN and infinities included (every coordinate, shape and transform checked first, every shape mapped by the shape kernel's map entry points); only the documented failure codes; every created shape valid and within the bounds (`Valid_Created_*`: coordinates within 1.0E150, a circle's radius in [0, 1.0E150], an ellipse's radii in (0, 1.0E150], rotations in (-Pi, Pi]), also the default shape a failed call returns; **Gold, the constructions themselves**: the circle, ellipse, line and segment tools return exactly the input mapped into the selected space (`Map_Circle`, `Map_Ellipse`, `Map_Line`, `Map_Segment`: the shape kernel's map entry point plus the checks, as functions so that the postconditions can name them) with exactly its status; the parallel line is exactly (X, Y, R) and the perpendicular exactly (X, Y, `Quarter_Turn` (R)), R the mapped line's rotation, so both pass through the given point; the bisector passes exactly through the midpoint ((StartX + EndX) / 2, (StartY + EndY) / 2) with the rotation `Quarter_Turn` of the direction from the start to the end point, and succeeds only when that direction is not the zero vector; the average segment is exactly `Average` of the two mapped segments (the midpoints of their start points and of their end points). `Quarter_Turn` (R) = `Normalize` (R + Pi/2), proved to lie in (-Pi, Pi] and to equal R + Pi/2 whenever that is at most Pi (beyond Pi it is computed as the IEEE remainder by 2 Pi, R + Pi/2 - 2 Pi; only its range is proved there). **Not proved** (tested): that two different points always give a non-zero difference (true in IEEE arithmetic with subnormals), the accuracy of the mapped ellipse | 2 |
| `AMV.Kernels.Calib_Fix` (with the private children `DOF_Fits`, `Checkerboard`, and for the nonlinear mode `Radial`, `Warp` and `Solver`) | `ks_point_pairs_*` (num_points, add_point_pair, delete_point_pair, get_point, set_point, clear, duplicate, destroy), `ks_n_point_to_n_point_compute`, `ks_fixture_run_params_default`, `ks_fixture_execute`, `ks_fixture_n_point_to_n_point_run_params_default`, `ks_fixture_n_point_to_n_point_execute`, `ks_calibration_*` (create, destroy, duplicate, kind, num_points, get_point, add_point_pair, delete_point_pair, set_point, dofs_to_compute, set_dofs_to_compute, physical_tile_size, set_physical_tile_size, calibrate, calibrated, uncalibrate, computed_fit, get_corner, corner_image_size, adjustment_default, get_adjustment, set_adjustment, computed_uncalibrated_from_calibrated_transform, run_params_default, tool_execute, computation_mode, set_computation_mode, computed_warp_model, map_output_pixel, map_input_pixel, checkerboard_run_params_default, checkerboard_tool_execute, n_point_tool_execute) | absence of run-time errors for any argument, NaN and infinities included (every coordinate, tile size, transform, code and space name checked first), any point pair list or calibration handle that is null or came from this kernel (an inconsistent one, `Valid_Pairs` / `Valid_Calibration`, is rejected with Bad_Parameter) and any 8-bit image handle; **no memory leaks** (every list, array, map and floating-point image is freed on every path, also when a later allocation fails); the point pair entry points change what they document and nothing on failure; a calibration whose input is changed is uncalibrated (the origin adjustment is not an input); **Gold**: (a) the minimum point count of each DOF (`Min_Points`: 0, 1, 1, 1, 2, 2, 3, 3) is checked before fitting: fewer pairs always give Bad_Parameter, and every successful fit had at least that many; (b) every fit returned or stored (`Gold_Fit` = `Valid_Fit` and `Has_DOF_Structure`): a transform within 1.0E150 whose determinant (`Det_Of`) is not zero and that `ks_transform_2d_linear_invert` inverts within the bound, with exactly the structure of its DOF (the unit matrix, and a zero translation along the other axis, for the translation DOFs; A = Cos (R), C = Sin (R), B = -C, D = A for RotationAndTranslation; A = D, B = -C, a positive scaling for ScalingRotationAndTranslation; the columns Sx (Cos R, Sin R) and Sy (-Sin R, Cos R) with Sx > 0 for ScalingAspectRotationAndTranslation), the RMS error in [0, 4.0E150], scalings within 2.0E150 and angles in (-Pi, Pi]; a stored fit read from a stream is checked against the same property at run time; (c) a checkerboard calibration keeps between 9 and 65536 corners (`Corners_Inside`), each inside the image it was found in, with grid indices within 65536; the detector (`Checkerboard.Detect`) returns its corners in strictly increasing row-major order of their grid indices (`Row_Major_Less`), so it never gives one grid index twice; the fixture and calibration tools leave a valid tree and a selection that fits; (d) the nonlinear mode (PerspectiveAndRadialWarp, both kinds): every model stored, returned or read from a stream is `Valid_Model` (the eight homography entries, K1 and K2 finite and within their bounds 1024, 16 and 4, the centre and normaliser within 2**24, the plate's normalisation within 1.0E150 and a half extent of at least 1.0E-150, the valid radius in [0, 16], the RMS error in [0, 4.0E150], the output transform within 1.0E150, the warp's map within 2**16 and 2**56, the image size within 2**24, at most 50 iterations) and belongs to the calibration image (the corners' image of a checkerboard; for both kinds `ks_calibration_calibrate` states that the model has the size of the image it was given), and the calibration's fit is a `Valid_Fit` of it; a calibration in that mode has at least `Min_Warp_Points` (8) point pairs, and an N-point calibration with fewer always gets Bad_Parameter from `ks_calibration_calibrate` (checked before anything else); a model read from a stream has the centre, normaliser and valid radius the fit computes; the linear-mode tool entry point refuses a warping calibration; (e) the warped output image of `ks_calibration_checkerboard_tool_execute` and `ks_calibration_n_point_tool_execute` has exactly the input's size (null in the linear mode, and on every failure), and every sample of the input is taken through `Image_Sampling.Bilinear_Sample`, so the warp never indexes outside the input; the linear solver never divides by a zero pivot and every value stays within its bound (2**100, 2**210); (f) the origin adjustment: every calibration handle holds a valid one (`Valid_Adjustment`: the origin within 1.0E150, the rotation in (-Pi, Pi], the codes in range; part of `Valid_Calibration`), setting it keeps the calibrated state, the stored fit and the points, and changes nothing when it fails; the transform of the calibrated space (`ks_calibration_computed_uncalibrated_from_calibrated_transform`, and the one the tools add) is within 1.0E150 with a non-zero determinant, is exactly the stored fit for the default adjustment (`Is_Identity_Adjustment`, which never fails), and exists in PerspectiveAndRadialWarp mode only for an adjustment in raw calibrated space (`In_Raw_Calibrated_Space`; the warp tool's postcondition states it too); an adjustment read from a stream is `Valid_Adjustment`; (g) `ks_calibration_map_input_pixel` (`Warp.Output_From_Input`): the bisection stays within [0, the valid radius], the two linear equations are solved only for a determinant of at least 1.0E-12, and an output pixel is returned only within 2**32 (0, 0 and Inside = 0 otherwise). **Not proved** (tested): that the input map inverts the output map (to 1.0E-6 pixel on the synthetic boards, and the real corners on a grid to 0.24 pixel), that the fits are least squares optima (the nonlinear fit's optimality and accuracy included: an N-point calibration recovers a known model to 1.0E-13 pixel without noise, and a checkerboard's corners given as N-point pairs give the checkerboard's model bit for bit), the accuracy of the checkerboard detector, that its grid is the board's (every corner an inner corner of the board, with the board's indices), and the geometry of the adjusted transform (the origin and the x axis where they are asked to be) | 2 |
| `AMV.Kernels.CNL_Search` (with the private children `Levels`, `Correlation`, `Search`) | `ks_cnl_search_*` (train_params_default, pattern_create, pattern_destroy, pattern_duplicate, pattern_get_train_params, pattern_set_train_params, pattern_train, pattern_train_masked, pattern_trained, pattern_untrain, pattern_trained_size, pattern_trained_origin, pattern_get_trained_pattern_image, run_params_default, execute, results_destroy, results_count, results_item) | absence of run-time errors for any image or region handle that is null or came from the kernels (the train image mask included, at any offsets), any pattern or results handle that is null or came from this kernel (an inconsistent one is rejected with Bad_Parameter: `Valid_Pattern` checks every trained level against the stacked pixels, and the care flags of a pattern trained with a mask against their size, `Valid_Care`), any training and run parameters (codes, flags, NaN and infinities checked first) and any transform; **no memory leaks** (the stacked levels and care flags, the integral images, the candidates, the score rows and the matches are freed on every path, a pattern's pixels and care flags when it is untrained, trained again or destroyed); every pattern handle an entry point leaves is `Valid_Pattern`, trained exactly when its training succeeded, and keeps its parameters when a setter fails; every trained level has at least Min_Cared_Pixels (64) cared-for pixels; the sums of the correlation are exact 64-bit integers with proved bounds (a cross sum below 65025 * 2**20, also over the cared-for pixels only, the products N Sum (p w), Sum p Sum w and N Sum w**2 below 65025 * 2**40), the integral images within the bounds of their component subtypes; **Gold, of every results handle `ks_cnl_search_execute` returns** (`Gold_Results` and the postcondition): every score in [0, 1] and at least AcceptThreshold, at most MaxResults results, **sorted by score (highest first)**, ID = index, Accepted 1, contrasts in [0, 2**28], **every window (before mapping) at a scored position: in the search area extended by the partial match limits, the limits those of the run and each at most half the pattern's side (`Margins_OK`), the search area in the image (`Area_In_Image`) and in the region's bounding box (`Area_In_Region`)**, **EdgeHit exactly the sides of the search area the reported window crosses (`Placed`, with `Edge_Hit_Within`), so None for every result when the limits are 0**, every location within 1.0E150; a partial window's clipped part lies in the pattern level and in the image level (its index arithmetic is proved like the rest), and its sums have the bounds of a whole window's; **a null or untrained pattern never yields results** (the status is a failure); only the documented failure codes. **Not proved** (tested): the accuracy of the scores (of partial windows too: `tests/test_cnl_search.adb` compares every local maximum with a brute-force clipped correlation), of the sub-pixel positions and of the contrasts, that the pyramid finds what the exhaustive search finds, that the default limits give the results of before (tested against values recorded before the change), and that the candidate and match buffers are sorted (the order of the results comes from the tests in `Search.Choose`, listed below); the train region mode Adjust_Mask clears the care flags of the pixels of the box outside the train region (`Restrict_Care`, absence of run-time errors for any region handle), and the region modes (AffineTransform included, which `pattern_train` and `pattern_train_masked` reject: it is trained by `Region_Modes`) and stream codes are checked like the other training parameters. For `Region_Modes`, `pattern_untrain` leaves a valid untrained pattern also when it rejects an inconsistent one, and `Restore_Trained` (Ada only) trains exactly the size of the image it is given, with the origin given and no care flags without them | 2 |
| `AMV.Kernels.CNL_Search.Region_Modes` | `ks_cnl_search_pattern_train_affine`, `ks_cnl_search_execute_affine` (and, for Ada, `Check_Affine_Train_Region`) | absence of run-time errors for any image, mask and pattern handle that is null or came from the kernels and any rectangle, transform, offset and parameter values (non-finite ones included, checked before the resampling); **no memory leaks** (the resampled pattern and search images, the resampling's output image mask, the resampled train image mask and the work region are freed on every path); a pattern handle `train_affine` leaves is `Valid_Pattern` (when not null) and trained exactly when it succeeded; only the documented failure codes; **Gold**: a pattern trained by `train_affine` has exactly the size `AMV.Kernels.Affine_Transform` gives the rectangle with its default run parameters (`Resampled_Width`, `Resampled_Height`), and no care flags without a mask; every results handle of `execute_affine` has the proved facts of `ks_cnl_search_execute` (`Gold_Results`: scores in [0, 1] and at least AcceptThreshold, at most MaxResults, sorted, IDs, EdgeHit; the margins those of the run, EdgeHit None with the limits 0), with every window inside the resampled rectangle of that size extended by the limits (`Area_In_Image`); a null or untrained pattern never yields results. The pixels, the care flags and the search come from the proved entry points it calls (`ks_affine_transform_execute`, `Restore_Trained`, `ks_cnl_search_execute`). **Not proved** (tested against the pixel aligned modes with upright rectangles on whole pixels, which resample exactly, and against turned scenes with known ground truth): the resampled pixels and care flags, and the origin and the locations carried through the resampling | 2 |
| `AMV.Kernels.PM_Align` (with the private children `Poses`, `Pyramids`, `Masks`, `Training`, `Search`, `Refinement`, `Overlaps`) | `ks_pm_align_train_params_default`, `ks_pm_align_run_params_default`, `ks_pm_align_check_run_params`, `ks_pm_align_pattern_*` (create, destroy, duplicate, get_train_params, set_train_params, train, train_masked, trained, untrain, levels, feature_count, feature), `ks_pm_align_execute`, `ks_pm_align_results_*` (destroy, count, item), `ks_pm_align_result_get_pose` | absence of run-time errors for any image or region handle that is null or came from the kernels, any pattern or results handle that is null or came from this kernel (null patterns and untrained ones included), any transform and any parameter values, non-finite ones included (rejected with Bad_Parameter naming the property); **no memory leaks** (every image of the two pyramids comes from the proved entry points of the image and real image kernels and is freed on every path, the work images of a pyramid, the score buffer, the clutter mask and the train image mask's summed-area table included; the results are destroyed on every failure path); the stream helpers accept only finite features and ignored points within the bounds and complete levels (Image_File otherwise); the train image mask's summed-area table (`Masks`, counts of pixels read through a limit of 2**31 that never acts) and its ignored points (the clutter marks them within a margin of at most 482 pixels) stay within bounds; the overlap of two results' footprints (`Overlaps`, polygon clipping and shoelace areas on coordinates within 2**40, every clipped point and sum through a limit that never acts) is in [0, 1]; **Gold: an untrained (or null) pattern never yields results** (Execute succeeds only for a trained pattern, and returns null otherwise), and of every results handle Execute returns (`Gold_Results`): **at most ApproximateNumberToFind results, sorted by score (highest first), every Score in [AcceptThreshold, 1], Coverage, Clutter and OutsideRegionFeatureProportion in [0, 1], FitError and Contrast >= 0, the rotation and the scaling in their zones** (exactly Nominal for a Nominal zone, within [Low, High] for a LowHigh one) **and the translation within 1.0E150**, so that every value of the pose is a valid argument of `AMV.Kernels.Transforms` again. **Not proved** (tested): that the search finds every instance, the accuracy of the refinement, the measures' meaning | 2 |
| `AMV.Kernels.Tool_Group` | `ks_tool_group_*` (create, destroy, duplicate, own_key, set_own_key, count, item, index_of, add, insert, remove_at, remove, move, clear, disabled, set_disabled, set_name, name, index_of_name, item_by_name, abort_run_on_tool_failure, set_abort_run_on_tool_failure, run_begin, run_next, run_report, run_end, run_tool_begin, run_tool_end), `ks_tool_block_terminals_*` (create, destroy, duplicate, count, clear, add, add_real, add_integer, add_boolean, add_string, add_object, insert, remove_at, remove, move, index_of, name, value_type, has_value, set_real, get_real, set_integer, get_integer, set_boolean, get_boolean, set_string, get_string, set_object, get_object) | absence of run-time errors for any group or terminal collection handle that is null or came from the kernel, any cursor record (checked against the group's run in progress and for consistency first), any text (lengths beyond the limit or negative included) and any codes, indices and values, non-finite reals included (rejected); **no memory leaks**; every failure leaves the group or the collection unchanged (a failed run_next or run_report marks only the cursor, run_end only ends the run); **Gold: no key is a member twice and no member has the group's own key, and no two terminals of a collection have the same name** (`Distinct_Members`, `Distinct_Names`: every entry point keeps them, a new handle has them), the counts within Max_Members and Max_Terminals; a member's name moves with it, setting a name changes nothing else (not even the change counter, so a run in progress goes on), and a lookup by name returns the first member with that name (none before it has it) or none at all; **of a run, as relations between each call and the cursor it gets: members are offered in order and each at most once, only enabled ones, every member skipped is disabled, every member after the last offered is disabled when none is left and the run has not stopped, nothing is offered after the run stopped (the script's run_tools = 0, or a member's Error with AbortRunOnToolFailure set), the worst result is the worst of the script's and the reported ones and the first failure the first member whose report was not Accept, and run_end returns both; a set of a scalar terminal value stores exactly the value given in the terminal of that name and changes nothing else, a get returns exactly the value it holds, a failed set changes nothing**. **Not proved** (tested): the text of the messages; RunTool (`run_tool_begin`, `run_tool_end`), **Gold**: a tool runs exactly when it is not a disabled member of the group, the result becomes the worse of the two (`Worse`), the message is replaced exactly when the tool's result is strictly worse, and the run aborts exactly when the tool reported Error and the group has AbortRunOnToolFailure | 2 |

`AMV.Kernels.Regions` added Ada-only functions to `AMV.Kernels.Shapes`:
`Rectangle_Contains`, `Rectangle_Affine_Contains`, `Circle_Contains`,
`Ellipse_Contains`, `Polygon_Contains` and `Section_Contains` hold the
test of each `ks_*_contains_point`, whose postconditions now say that the
entry point returns exactly that function's result once its arguments
pass; the `ks_*_boundary_slack` postconditions say that the region is
valid when they succeed.

Total on `main` (2026-11-12): 34514 checks (33720 before the last four
additions: the region modes of the IP one-image tool added 296, the
soft segmentation of the blob tool 335, the region modes of the
Sobel edge tool 129, and the train region mode of the CNL search
tool 34) (`make prove`
prints the total; the summary per unit is in
`build/obj/gnatprove/gnatprove.out`), all proved,
no `pragma Assume`, no justified checks. The only bodies gnatprove skips
are the trusted ones listed below (and the runtime's
`Unchecked_Deallocation` and `Unchecked_Conversion` instances).

## Trusted (not proved)

* The Ada API (`SPARK_Mode` off): by design it only passes values to the
  entry points and turns statuses into exceptions (`AMV.Checks`).
  `make check` runs `tools/shell_check` to keep it that way.
* Packages that have not moved into a kernel yet
  (`tools/shell_check_legacy.txt`; none since the core and `AMV.Tools`
  moved) would not be proved at all.
* The reference counting of pixel handles in `AMV.Images` (atomic
  counters in boxes owned by the controlled image types,
  `docs/DESIGN.md` 9.1 and 9.3), and of the read-only handles kept in
  the generic `AMV.Shared_Handles` (the results of tool runs). The
  kernels never share a handle.
* `SPARK_Mode => Off` bodies in `AMV.Kernels.Images` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate` (8-bit and 16-bit): allocates the pixel
    matrix and then the handle record; `Storage_Error` gives null (the
    entry point reports `Failure_Out_Of_Memory`), and the matrix is freed
    when the record cannot be allocated. Postcondition: a non-null result
    is a valid handle of the requested size. The pixel values are left
    unspecified, which is safe because every bit pattern of
    `Unsigned_8` / `Unsigned_16` is a valid value; every caller overwrites
    them.
  * **C memory**, the bodies of `ks_image_8_grey_get_row`,
    `ks_image_8_grey_set_row`, `ks_image_16_grey_get_row` and
    `ks_image_16_grey_set_row`: after the proved check
    `Check_Row_Request` (the handle, the row index, `length = width`, a
    non-null address) they view the `length` elements at the C address
    as an Ada array (an `Import` object with an `Address` clause) and call
    the proved Ada-only `Get_Row` / `Set_Row`. Trusted: that C provides
    `length` valid elements there.
  * **Stream decoding**, `To_Long_Float`: the unchecked conversion of
    64 bits to a `Long_Float`, which SPARK forbids because some bit
    patterns are not finite numbers. Its precondition (also checked at
    run time) excludes exactly those patterns (exponent bits all ones);
    the conversion in the other direction (`To_Bits`) is SPARK.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Image_File` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Contents`: allocates a contents record of
    Count empty slots (`new` with the record's default values, so every
    handle is null and every image type 0); `Storage_Error` gives null
    (the caller reports `Failure_Out_Of_Memory`). Postcondition: a
    non-null result has Count slots, all empty. The images themselves are
    allocated by the proved entry points of `AMV.Kernels.Images`.
  * **C memory**, the bodies of `ks_image_file_decode`,
    `ks_image_file_count_for_update`, `ks_image_file_encode_8_grey`,
    `ks_image_file_encode_16_grey`, `ks_image_file_encode_24_planar_color`
    and `ks_image_file_format_from_name`: after the proved check
    `Check_Bytes_Request` (length in 0 .. `Max_Length`, a non-null
    address when the length is positive; for a name, a length that is not
    negative and a non-null address) they view the `length` bytes or
    characters at the C address as an Ada array (an `Import` object with
    an `Address` clause; a constant empty array for length 0) and call
    the proved Ada-only procedure of the same name. Trusted: that C
    provides `length` valid bytes there, and that they do not change
    during the call (decode reads them in two passes).

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Shapes` (the specs are SPARK,
  with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Polygon` and `Allocate_Vertices`: a new
    polygon record without vertices (`new` with the record's defaults:
    count 0, no array), and a new vertex array of the requested capacity
    indexed from 0 (every vertex (0, 0), the default of the record);
    `Storage_Error` gives null (the entry point reports
    `Failure_Out_Of_Memory`). Postconditions: a non-null result is a
    record without vertices, or an array with the requested bounds.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Regions` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Region`, `Allocate_Flags`,
    `Allocate_Reader` and `Allocate_Buffer`: a new region record or
    stream reader with the record's defaults (no flags, no buffer), a new
    flag matrix with the requested bounds, or a new stream buffer of the
    requested length indexed from 0 (flags and elements are False, the
    default component value of their array types); `Storage_Error` gives
    null (the caller reports `Failure_Out_Of_Memory`).

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Image_Math` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate` (a real image: the pixel matrix, then the
    handle record; the matrix is freed when the record cannot be
    allocated) and `Allocate_Values` (a one-dimensional array of values,
    for the Gaussian tables, the running sums of the box filter and the
    values of a stream being read): `Storage_Error` gives null (the
    caller reports `Failure_Out_Of_Memory`). Postcondition: a non-null
    result has the requested size. The values are left unspecified; the
    proved callers write every value before reading it (the
    postconditions of the operations that return an image state a bound
    for every pixel, which an unwritten pixel would not satisfy).
  * **`Exp`**, `Exp_Of_Non_Positive`: `Ada.Numerics...Exp` of an argument
    that is not positive (the Gaussian weights). gnatprove checks every
    call of `Exp` for overflow and the runtime's contract gives no bound
    on its result, so that check cannot be proved; for an argument <= 0
    the result lies in [0, 1] and cannot overflow. The function has no
    postcondition: the caller limits the result to [0, 1] itself.
  * **Stream decoding**, `To_Long_Float`, as in `AMV.Kernels.Images`.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Geometry`:
  * **C memory**, the bodies of `ks_geometry_fit_line`,
    `ks_geometry_fit_circle`, `ks_geometry_fit_line_robust` and
    `ks_geometry_fit_circle_robust`: after the proved check
    `Check_Points_Request` (count not negative, the pointers not null when
    it is positive) they view the `count` points (and, for the robust
    fits, the `count` int32_t flags) at the C addresses as Ada arrays and
    call the proved Ada-only fits; the robust ones allocate the Boolean
    flags the Ada-only fit fills on the heap (`Storage_Error` gives
    `Failure_Out_Of_Memory`), copy them into the C flags with the proved
    `Store_Flags` and free them. Trusted: that C provides `count` valid
    elements at each address.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Histogram` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Result` (the bins, every count 0, then the
    result record with its default values; the bins are freed when the
    record cannot be allocated) and `Allocate_Counts` (the 64-bit
    counting array of one bin mode, every count 0): `Storage_Error` gives
    null (the caller reports `Failure_Out_Of_Memory`). Postconditions: a
    non-null result has the requested bounds and the record's defaults.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Sobel_Edge`:
  * **Allocation**, `Allocate_Stack`: the work stack of the hysteresis
    (Width * Height positions; written before they are read);
    `Storage_Error` gives null (the entry point reports
    `Failure_Out_Of_Memory`). Postcondition: a non-null stack has the
    requested bounds.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Blob` (the specs are SPARK,
  with the contracts the proved code relies on):
  * **Allocation**, `Allocate_U8_Matrix`, `Allocate_Int32_Matrix`,
    `Allocate_Int32_Array`, `Allocate_Int64_Array`, `Allocate_Results`,
    `Allocate_Result_Array`, `Allocate_Real_Array` (in the body of
    `AMV.Kernels.Blob`), `Allocate_Accumulators` (in the body of
    `AMV.Kernels.Blob.Measures`) and `Allocate_Coordinates`,
    `Allocate_Stats` (in the body of `AMV.Kernels.Blob.Extrema`):
    a new matrix, table, results record or table of per-feature sums with
    the requested bounds and the default values of their types (zeros,
    null handles, the record defaults of the sums); `Storage_Error` gives
    null (the caller reports `Failure_Out_Of_Memory`). Postconditions: a
    non-null result has the requested bounds (and, for the integer
    tables, all zeros, which the default component value gives).

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Caliper` (the specs are SPARK,
  with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Values` (a profile of the requested length,
    indexed from 0; its values are unspecified and the proved callers write
    every one before reading), `Allocate_Items` (an array of results of the
    requested length, with the record's default values) and
    `Allocate_Results` (a results record with its defaults: no items, no
    profiles): `Storage_Error` gives null (the caller reports
    `Failure_Out_Of_Memory`).

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Find_Line` and
  `AMV.Kernels.Find_Circle`:
  * **Allocation**, `Allocate_Items` (items with the record's default
    values), `Allocate_Calipers` (an array of null caliper results handles)
    and `Allocate_Results` (a results record without items or calipers):
    `Storage_Error` gives null (the caller reports
    `Failure_Out_Of_Memory`).

* The image processing geometry kernels (`AMV.Kernels.Image_Sampling`,
  `Affine_Transform`, `Copy_Region`, `IP_Two_Image`, `Image_Convert` and
  `Polar_Unwrap`) have no `SPARK_Mode => Off` bodies: every image they
  return is allocated by the proved entry points ks_image_8_grey_create and
  ks_image_8_grey_duplicate of `AMV.Kernels.Images`.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Dimensioning.Fitting` (the
  specs are SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Points` (a copy of the points: an array of
    the requested length indexed from 0, every point (0, 0)),
    `Allocate_Flags` (the used flags, all False), `Allocate_Values` (the
    distances, all 0) and `Allocate_Result` (a result record with its
    defaults: no arrays): `Storage_Error` gives null (the caller reports
    `Failure_Out_Of_Memory`). `AMV.Kernels.Dimensioning` and its other
    children have no such body.

* `AMV.Kernels.Create_Shapes` has no `SPARK_Mode => Off` body: it
  allocates nothing.

* `SPARK_Mode => Off` bodies in `AMV.Kernels.Calib_Fix` and its private
  children `Checkerboard` and `Radial` (the specs are SPARK, with the
  contracts the proved code relies on):
  * **Allocation**, `Allocate_Pairs` (a pair list record with its defaults:
    no pairs, no array), `Allocate_Pair_Array` (an array of pairs of the
    requested length indexed from 0, every coordinate 0),
    `Allocate_Corners` (in the parent and in `Checkerboard`: an array of
    corners of the requested length indexed from 0, the record's
    defaults), `Allocate_Calibration` (a calibration record with its
    defaults), `Checkerboard.Allocate_Map` (the corner map, the grid table
    and the queue of the grid's growth: Height rows of Width zeros, the
    array type's Default_Component_Value) and
    `Checkerboard.Allocate_Candidates` (an array of candidate corners of
    the requested length indexed from 0, the record's defaults),
    `Allocate_Observations` (in the parent: an array of the observed
    points of the nonlinear fit, of the requested length indexed from 0,
    the record's defaults), `Radial.Allocate_Samples` (an array of
    normalised points of the requested length indexed from 0, the
    record's defaults):
    `Storage_Error` gives null (the caller reports
    `Failure_Out_Of_Memory`). Postconditions: a non-null result has the
    requested bounds (and the record's defaults). The private children
    `DOF_Fits`, `Warp` and `Solver` have no such body (the warped image
    comes from `ks_image_8_grey_create`).
* `SPARK_Mode => Off` bodies in `AMV.Kernels.CNL_Search` and its private
  children (the specs are SPARK, with the contracts the proved code
  relies on):
  * **Allocation**, `Allocate_Pattern` (a pattern record with its
    defaults: the default training parameters, untrained, no pixels),
    `Allocate_Results` (a results record without items) and
    `Allocate_Found` (an array of result items) in the body of
    `AMV.Kernels.CNL_Search`; `Allocate_Sums` (an integral image of zero
    pairs) in `Levels`; `Allocate_Candidates`, `Allocate_Score_Rows`
    (three rows of scores, all 0) and `Allocate_Matches` in `Search`:
    `Storage_Error` gives null (the caller reports
    `Failure_Out_Of_Memory`). Postconditions: a non-null result has the
    requested bounds (and, for the records, their defaults; a new
    pattern has no pixels and no care flags). The stacked pyramid
    levels of the pattern and of the search box, and the stacked care
    flags of a pattern trained with a mask, are images allocated by the
    proved `ks_image_8_grey_create`.
* `SPARK_Mode => Off` bodies in `AMV.Kernels.PM_Align` (the specs are SPARK,
  with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Pattern` (a pattern record with its default
    values: untrained, the default train parameters, every level empty) and
    `Allocate_Results` (a results record without results):
    `Storage_Error` gives null (the entry point reports
    `Failure_Out_Of_Memory`). The images of the pyramids, the score buffer
    of the coarse search and the clutter mask are allocated by the proved
    entry points of `AMV.Kernels.Images` and `AMV.Kernels.Image_Math`; the
    private children have no such body.
* `SPARK_Mode => Off` bodies in `AMV.Kernels.Tool_Group` (the specs are
  SPARK, with the contracts the proved code relies on):
  * **Allocation**, `Allocate_Group` (a group record with its defaults:
    no members, own key 0, AbortRunOnToolFailure off, no run) and
    `Allocate_Terminals` (a collection record without terminals):
    `Storage_Error` gives null (the entry point reports
    `Failure_Out_Of_Memory`). Both records hold fixed arrays and no
    pointers, so these are the kernel's only allocations.

## Run-time guards that stand in for missing contracts

The runtime's `Sqrt` contract gives no upper bound, and products or
quotients of bounded floating-point values are slow for the provers. A
few internal helpers therefore end with a test that clamps the result to
a bound that always holds mathematically (and after IEEE rounding), so the
bound becomes provable without assuming anything. At run time these tests
are never true; they are listed so that a reviewer can check each claim:

* `Numerics.Hypot`: the root is at most `2 * SB`, and the length at most
  `2 * Big` (the true value is at most Sqrt (2) times the larger argument).
* `Numerics.Times_Unit`: `abs (X * U) <= abs X` for `abs U <= 1`.
* `Numerics.Unit_Ratio`: `abs (X / Y) <= 1` for `abs X <= Y`.
* `Numerics.Times_Small`: `abs (X * S) <= 4 abs X` for `abs S <= 4`.
* `Shapes.Add_Term` (the shoelace sum of a polygon's area): after k terms
  of at most 2**1003 each the sum is at most k * 2**1003, a representable
  bound, so rounding keeps it. The provers did not prove the loop
  invariant `abs Sum <= Long_Float (I) * 2**1003` across the rounded
  addition; the helper states it per step.
* `Shapes.Add_Length` (a polygon's perimeter): the same with edges of at
  most 2**502.
* `Regions.Ceiling_Index` / `Floor_Index` (the first and last candidate
  pixel along an axis): for a value X in (0, Last] (resp. [0, Last)) the
  integer nearest to X, moved by one when it lies on the wrong side of X,
  is the ceiling (floor) of X, within [0, Last]; the result is clamped to
  [0, Last] anyway, so that the bound needs no proof about the rounding
  of the conversion.
* `Numerics.Reduce_Two_Pi` / `Reduce_Pi`: the IEEE remainder by P lies in
  [-P/2, P/2]; the test that folds -P/2 to +P/2 also maps any value outside
  that range (which cannot occur) to P/2. `'Remainder` is wrapped in a
  function without a postcondition, `IEEE_Remainder`, because the provers'
  model of it made otherwise trivial proofs time out.
* `Numerics.Mul_Within` and `Square_Within`: `abs (X * Y)` after rounding
  is at most `Limit_X * Limit_Y` after rounding when `abs X <= Limit_X`
  and `abs Y <= Limit_Y` (rounding is monotonic); `X * X` is never
  negative. Callers pass constant limits, so they get a constant bound
  for a product of two variables, which the provers cannot derive
  quickly themselves.

`AMV.Kernels.Image_Math` keeps its proofs free of quantified facts about
the pixels of its arguments by clamping, with `Numerics.Clamp`, what it
reads, and states its sums with clamps at bounds far above their true
values:

* Every value read from a real image handle is limited to ±1.0E100
  (`Clamped`): the kernel only ever stores values within that bound
  (create, set_pixel and fill check them, the stream reader checks them,
  every computed value is clamped), so for a handle the kernel made the
  limit never changes a value.
* Running sums of pixel values and the window sums of the box filter
  (`Sum_Clamped`, `Accumulate`, `Add`) are limited to ±1.0E150; their true
  magnitude is at most about 1.8E119 ((2 * 2**31 + 1)**2 values of at
  most 1.0E100). The compensation term of `Add` is a sum of rounding
  errors, far smaller.
* `Statistics`: the sum of squared deviations is limited to 2**1000 (at
  most 2**31 * (2.0E100)**2, about 8.6E209), and the standard deviation
  to Maximum - Minimum (it is at most half of that).
* `Gaussian_Smooth`: weights and tail masses are limited to [0, 1] (each
  weight is an exponential of a value <= 0 divided by a total of at least
  1; the tail masses stay below 1/2), the sums of weights to 2**40 (at
  most 3_000_002). The ratio of the radius offset to Sigma is formed only
  below 38 (`Ratio_Within`; the test before it keeps it at most 37).
* `Locate`: the fraction `C - floor (C)` is limited to [0, 1].

Clamps that can act, by rounding at the very edge of the bound only, and
so belong to the documented behaviour: every computed pixel value
(smoothed values, bilinear samples, 2 x 2 means, Sobel derivatives) is
limited to ±1.0E100, and the mean of `Statistics` to [Minimum, Maximum]
(the mean of equal values can otherwise come out an ulp away from them).

`AMV.Kernels.Geometry` reads every point of an array through a clamp to
±1.0E150 (`Point_At`; the entry points have checked every point first,
so it never acts) and states the bounds of the scaled quantities of the
fits with clamps that never act (each is far above the true value; the
body lists them next to their constants):

* the sums of offsets from the first point (at most 2**31 * 2.0E150,
  limited to 2**560) and the largest offset (at most 2.0E150);
* a scaled offset is at most 1 in magnitude (the offset is at most the
  largest one, whose exponent is the scaling exponent); before the second
  factor of the scaling below 2**(-500), the offset is at most 2**(-500);
  the scaled largest coordinate is below 2**60 once the exponent gap has
  been checked;
* the exponent of a value in (0, 2**500] lies in -1073 .. 501, and the
  static product of powers of two in `Power_Of_Two` is at most 2**510;
* second moments of scaled offsets (at most 2**31) are limited to 2**40,
  the RMS spread and the RMS residual of a line to 2 (they are at most
  Sqrt (2)), the scaled scale over the spread (below 1.0E12) to 2**41,
  Sqrt (N) to 2**16;
* the circle fit: frame moments (each term at most 16) to 2**40, the RMS
  of T to 2 (Limit at most 2.0E9), the sum of distances to 2**70 and
  their mean to 2**40 (a distance is at most about 2 Limit + 3, so also
  below 2**34, its own limit), the mean unit vectors to 1, the squared
  residuals, gradient and curvature sums to 2**120, 2**80 and 2**100;
  the Newton step is at most twice Limit once it has passed the test
  against the bound, so it fits in 2**35; the RMS residual to 2**60;
* a unit vector component over its length (`Unit_Quotient`) is at most 1
  in magnitude (Hypot is never shorter than a component); the half chord
  of an intersection is at most the radius (limited to 2.0E150, or
  2**506 for two circles), the quotient of an intersection of lines at
  most 4.0E162 and the distance A to the radical line at most about
  2 R1 (both formed only below a larger bound);
* `Rescaled_Cost`: removing a point at most doubles the largest offset
  from the centroid, so the exponent difference is at most 1 (limited to
  2).

Clamps that can act, by rounding at the very edge of the bound only: the
centroid of points within ±1.0E150 is limited to that bound. A point so
close to a trial centre that Res / Dist exceeds 2**60 adds nothing to the
curvature terms (formerly the division could overflow for a distance near
the smallest subnormal).

The image processing filter kernels state these bounds with clamps that
never act:

* `Histogram.Compute_Statistics`: the sum of squared differences from the
  mean (at most 255**2 * 2**31, below 2**47) is kept in [0, 2**60]; the
  mean (Sum / Total of grey levels) is formed with `Ratio_Within` below
  256 and kept within [Minimum, Maximum] (the rounded quotient of equal
  values may leave it by an ulp, so this clamp can act at the very edge);
  the variance is formed below 65025 (it is at most 127.5**2) and the
  standard deviation, a `Sqrt` without an upper bound in the runtime's
  contract, kept at most 255.
* `Sobel_Edge`: the derivatives of ks_real_image_sobel are read through a
  clamp to +/-127.5 (4 * 255 / 8, the largest for grey levels), the
  magnitude kept at most 361 (it is at most 255 * Sqrt (2)), the scaled
  magnitude kept >= 0 (`Mul_Within` gives no sign) and the angle code in
  [0, 256]. The hysteresis pushes a pixel onto its stack of Width *
  Height entries only when it marks it a survivor, which it is not yet,
  so the stack never fills; the push is guarded by a test on the stack's
  length (`Top <= Stack'Last`) that therefore never fails.
* `Image_Sharpness`: derivatives through the same clamp to +/-127.5, the
  sums of the scores kept below 2**60 (at most 2**31 terms of at most
  32512.5, below 2**47), the means formed with `Ratio_Within` below their
  limit (each term is at most the limit). The sum of absolute differences
  is an integer below 2**39, so its Long_Float sum is exact.

`AMV.Kernels.Blob` keeps its loops free of quantified invariants over its
tables (except where a Gold property needs one) by reading every table
entry through a range test or a clamp, and by guards that never act:

* the histogram bins, the component areas and the boundary segment counts
  stop at 2**31, 2**31 and 2**40 (a region has at most 2**31 - 3
  pixels, a pixel adds at most four segments);
* a provisional label, a class number or a target read from a table is
  used only when it lies in the range it always lies in (otherwise the
  pixel counts as outside the region, or the feature as having no
  parent); a new label is refused when the tables are full (they have
  room for one label per pixel and two more); the numbering of the
  features stops when every class has a number;
* the sums of a feature are read and written through clamps at 2**63
  (offsets, true bound 2**62) and 2**94 (squared offsets, true bound
  2**93); offsets from the first pixel, mean offsets and centroids are
  limited to 2**32, 2**32 and 2**33 (they are below 2**31 + 1, 2**31 and
  2**32); the central moments to [0, 2**96]; the mapped moments, the
  principal moments and the lengths are non-negative and limited to their
  stated bounds (`Non_Negative`), which the true values satisfy; the
  extents of the projections to 2**101 (true bound 2**100); the pixel
  bounding box of a feature to coordinates >= 0;
* a pixel count is converted to Int32 through a clamp at Int32'Last;
* the weighted sums of a soft segmentation (`Measures.Weight_Pass`): a
  pixel's level is read through a range test (`Pixel_Weight`: a level in
  1 .. Softness + 1 is used as it is, 0, a hole filled into the blob,
  counts as Softness + 1, and a level above that, which cannot occur,
  too); the level sum stops at 2**40 (true bound 2**39: at most 2**31
  pixels of at most 255), the sums of weighted offsets and squared
  offsets are read and written through clamps at 2**71 and 2**103 (at
  most 2**31 pixels, each adding at most 255 times an offset below 2**32
  or its square), and `Weighted_Central_Moments` limits the area to 2**31
  pixels (it is at most the pixel count);
* the extrema-angle work tables (`Extrema.Compute_Extrema`): the running
  total of the pixel counts stops at 2**31 - 3, a coordinate is written
  only while its feature's fill count is below its pixel count and its
  slot lies in the table, a feature's slice is selected only when it lies
  in the table; the stored centres of mass are read through clamps at
  2**33 (pixel space, true bound 2**31) and 1.0E140 + 2**98 (selected
  space, the bound of `Map_Coordinate`).

Clamps that can act and so belong to the documented behaviour: a ratio
(Elongation, Acircularity, an Aspect) whose divisor is 0 or whose value
would exceed 1.0E150 is reported as 0 (`Quotient`, `Extrema.Aspect`); the
corners of a boundary are limited to 2**33 before they are mapped (they
lie within the image); the mean of the two middle values of an even
count is limited to the least and greatest value (`Select_Median`),
which acts only when halving a subnormal value loses its last bit.

`AMV.Kernels.Caliper` reads the values of its heap arrays (profiles) and
the bilinear samples of the image through limits to [0, 255] (`Read_Grey`)
and [-255, 255] (`Read_Signed`), which never act: every sample of an 8-bit
image interpolates between grey values, and the kernel stores only means
of such values and differences of two means. Its other clamps never act
either:

* the sum of a column of samples (at most 32768 values of at most 255) is
  limited to 2**23, the sum of a filter window (at most 1000 values) to
  2**18, and the centroid sums of the edge refinement (at most 2001
  differences of at most 255, weighted by at most 1000) to 2**19 and 2**29;
* the number of samples along a side, the length rounded, is limited to the
  side's limit (the length is below the limit plus one half), and the step
  between samples (the length over the count, at most 1.5 pixels) to 2;
* the refined edge position is limited to [0, Nx] (the centroid lies within
  the filter's half size of the extremum, which can reach an end only by
  that bound), and the midpoint of a pair to the interval between its edges.

The Gold bounds of the positions come from `Numerics.Mul_Within` (whose own
clamp is listed above): a position is (T - C) K with abs (T - C) <= C, so it
is within C K, the half length the results store.

`AMV.Kernels.Find_Line` and `AMV.Kernels.Find_Circle` read the points
they keep (the positions of caliper results, within 1.0E150 by the
caliper's proved postcondition) through a limit to 1.0E150 (`Read`),
which never acts, and limit the centre of a caliper on the expected
segment (a convex combination of its end points) to 1.0E150, which can act
only by rounding at the very bound. The fixed-radius circle fit limits its
sums of at most 1000 terms of at most 2.0E150 to 2**520, its cost (at most
1000 squared residuals of at most 4.0E150) to 2**1013, the distance of a
point from the centre to 4.0E150 and the root of the mean squared residual
(the runtime's `Sqrt` has no upper bound in its contract) to 4.0E150; none
of these acts. The mean of the centre estimates is limited to 1.0E150,
which acts only when the best centre lies beyond the bound (then the
centre is reported at the bound). The sum of the angle steps of the arc
(at most 1000 steps of at most Pi) is limited to 4000, which never acts.

`AMV.Kernels.IP_One_Image` reads only grey levels and its own bounded
tables, and states its bounds with guards that never act:

* erosion and dilation: the column pass limits each result to the input
  pixel (the minimum, or the maximum, with it), which never acts because
  the rectangle contains the pixel itself; this states the Gold fact
  per pixel instead of through the block structure of the running
  extrema (`Columns_Pass`). The differences Close - Original and
  Original - Open are limited to >= 0 (a closing never lowers and an
  opening never raises a pixel; Dilate - Erode >= 0 is proved);
* the median: a histogram count stays in 0 .. KernelWidth x KernelHeight
  and the count below the median in 0 .. that area (a count is lowered
  only when positive, raised only below the area); the window always
  holds that many values, so neither test acts;
* equalisation: a bin stops at 2**40 (a region has fewer than 2**31
  pixels), and an entry of the table is limited to 0 .. 255 (the
  cumulative count never exceeds the total);
* the binomial weights of order at most 48 are limited to 2**48 (their
  sum), the normalising power of two likewise, each rounded pass to 255
  (the weights sum to the divisor); the running sums of the box filter
  to [0, 255 K] and their means to 255;
* the convolutions read the kernel values through a limit to +/-1.0E6
  (the checks of the operator list have accepted only such values; cells
  outside the kernel's size are never read) and keep the sum of at most
  225 products of at most 2.55E8 within 2**36 (`Numerics.Clamp`);
* MultiplyConstant limits the product of a grey level and the constant
  (`Numerics.Mul_Within`) to >= 0.

The limits of the results to 0 .. 255 (convolutions, UnsharpMask,
MultiplyConstant and AddSubtractConstant in Bounded mode) act and are the
documented behaviour.

The image processing geometry kernels (`AMV.Kernels.Image_Sampling`,
`Affine_Transform`, `Copy_Region`, `IP_Two_Image`, `Image_Convert`,
`Polar_Unwrap`) state these bounds with clamps that never act:

* `Image_Sampling.Nearest_Index`: for a point within the image, Floor
  (P + 0.5) is a whole number in 0 .. Size after the tests before it; its
  conversion to an integer is limited to 0 .. Size - 1 once more, which
  spares the prover the rounding of the conversion (the last pixel for a
  point on the far border is documented behaviour).
* `Image_Sampling.Locate` limits the fraction between two pixel centres
  to [0, 1] (as `Image_Math.Locate` does), and the bilinear interpolation
  reads its intermediate values through a limit to [0, 255]
  (`Read_Grey`), within which every interpolation of grey levels lies.
* `Polar_Unwrap.Pixel_Scale`: the root of a determinant of at most
  2**1021 is below 2**511 (the runtime's `Sqrt` has no upper bound in its
  contract); `Pixel_Fraction` and `Point_Fraction` limit (X + 0.5) / Size
  and T / Size, which lie in [0, 1], to [0, 1].

Limits that can act and so belong to the documented behaviour: an output
length beyond 4.0E7 pixels reads as Max_Output_Side + 1 (too large) in
`Output_Length`; `Polar_Unwrap.Saturating_Product` reports a product
beyond 2**500 of two factors above 1 as 2**1000, which only ever means
"more than 32767 output pixels"; `Image_Convert.Weighted_Intensity`
limits the weighted sum to 0 .. 255 (the documented clamp of that mode).

The dimensioning kernels carry the bounds of their values in subtypes
(`Coordinate`, `Length`, `Signed_Length`, `Unit` of
`AMV.Kernels.Dimensioning.Planar`; the moment sums and every matrix of the
ellipse fit), and state the rest with these limits:

* never acting: the components of a unit vector over its length (as in
  `AMV.Kernels.Geometry`); the direction of a line in an ellipse's frame
  (a rotation of a unit vector) to [-1, 1]; a length measured on an
  ellipse (`World_Length`: at most the distance between two points within
  the bound plus a radius, about 3.9E150) and the radial distance of the
  ellipse fit to 4.0E150; the square root of the discriminant of a line
  and an ellipse (at most Sqrt (10)) to 4; the sums of coordinates, of
  the moments (at most 2**20 terms of at most 1) and of the squared
  distances (at most 2**20 terms of at most 1.6E301) of the fits to
  2**521, 2**21 and 2**1021; a mean moment to [-1, 1]; the RMS errors
  (Sqrt has no upper bound in its contract) to 4.0E150; the square roots
  of the 2 x 2 ellipse problem (of values within 2**94) to 2**47 and the
  radii of the scaled ellipse to 2**30; the coordinates read from the
  points of a fit (a polygon handle's vertices lie within 1.0E150) to
  1.0E150; the sums and the cost of the fixed-radius circle fit, as in
  `AMV.Kernels.Find_Circle`, with limits for 2**20 points (2**522 and
  2**1021);
* acting only through rounding: a point between two end points
  (`Planar.Between`) kept between them; the quotients that place the
  nearest point of an ellipse after the bisection (taken as 1 when the
  rounded denominator next to the pole is not positive); the parameters of
  the points where a line meets an ellipse (at most 2 in magnitude,
  limited to 8 when the quadratic's leading coefficient is tiny); the
  centroid of a fit at the bound;
* the guards that stand for facts the called contracts do not state: a
  fit reports Failure_Other when fewer points were used than it needs
  (`ks_geometry_fit_line_robust` and `ks_geometry_fit_circle_robust` do
  not state how many points they mark), which never happens;
  `ks_fit_points_add_point` turns an Index_Out_Of_Range of the polygon
  kernel's append (whose index is always valid) into Bad_Parameter;
  quotients
  that would exceed their limit (an entry of the inverse scatter beyond
  2**90, the conic's centre or a radius beyond 2**30 times the extent of
  the points) are reported as degenerate input with Bad_Parameter, the
  documented behaviour.

`AMV.Kernels.Create_Shapes` has one guard that never acts: `Map_Line`
passes the rotation of the mapped line through `Normalize`, which returns
it unchanged when it lies in (-Pi, Pi]. ks_line_map takes it from
ks_transform_2d_linear_map_angle, whose postcondition puts it there, but
ks_line_map's own postcondition states only that the line is within the
bounds.

`AMV.Kernels.Calib_Fix` and its private children state these bounds with
limits that never act:

* the fits (`DOF_Fits`): the running sums of coordinates (at most 2**19
  terms within 1.0E150) are limited to 2**520 and their means to 1.0E150
  (a mean lies between the values; the limit can act only by rounding at
  the very bound); a scaled coordinate (X - C) / S is taken as 1 or -1
  when |X - C| reaches S, the largest such magnitude, which spares the
  prover the quotient there; the sums of products of scaled coordinates
  (at most 2**19 terms in [-1, 1]) are limited to 2**20; the sum of the
  squared scaled B coordinates is at least 1 when the B points do not
  coincide (the coordinate that defines the spread contributes 1), so the
  guards on it (below 1/2), on the scatter's determinant (below 2.0E-11)
  and on its diagonal entries (below 1.0E-11), which the collinearity
  test implies, never act; the quotients formed by `Ratio`
  (`Numerics.Ratio_Within`, saturated at its limit) stay below their
  limits (at most 2**23, 2**58 and 2**77 where they are formed); the
  products of a bounded scaling and a cosine or a sine are checked against
  1.0E150 (`KT.Bounded`), which they cannot exceed; the length of a
  non-zero vector (`Numerics.Hypot`) is checked to be positive; the sum of
  squared distances (at most 2**19 terms of at most 1.6E301) is limited to
  2**1022 and the RMS (the runtime's `Sqrt` has no upper bound in its
  contract) to 4.0E150;
* the detector (`Checkerboard`): smoothed grey levels, and their bilinear
  samples, are read through a limit to [0, 255] (a weighted mean of grey
  levels; the limit acts only by rounding at its ends), stored responses
  through a limit to 2**19 (every stored value is a response or 0), the
  gradient sums of a window are limited to 2**22 and 2**26 (true bounds
  about 2.0E6 and 2.0E7), corner offsets are saturated at 2**60 before
  they are tested against the window; the position of a sample between
  two pixels is limited to [0, 1]; the sum of the differences of a ring's
  opposite samples is limited to 8 * 255 (eight differences of at most
  255 each); the points where a ring crosses its mid level (on a chord of
  the unit circle) are limited to [-1, 1]; the length of a vector that is
  normalised is taken as at least the magnitude of each of its components
  (which it is); the pixel index nearest to a coordinate inside the image
  is limited to the image, and so is every corner copied into the result
  (each was found inside the image); the entries of the corner map, the
  grid table and the growth's queue are range-tested before they are used
  as indices, and the result is checked to hold one corner per entry of
  the grid table (it always does);
* the nonlinear mode (`Radial`, `Warp`, `Solver`): the normaliser (half
  the image diagonal, `Numerics.Hypot`) is taken as at least 0.5 and half
  of each side, and at most 2**24 (which it is); every observed point (a
  corner, or an N-point pair's uncalibrated point mapped to pixel space,
  which the parent tests to lie on the image) is tested to lie within the
  normaliser of the image centre and within the plate's half extent of
  the plate's centre before it is scaled into [-1, 1] (it always does:
  the points lie in the image and the extent is that of their bounding
  box); the plate points are tested to span at least 2 Min_Plate_Scale
  (1.0E-150: equal raw calibrated points of an N-point calibration give
  Bad_Parameter; a checkerboard's corners span at least one grid step),
  and their half extent is limited to [1.0E-150, 1.0E150] (where it
  lies); the collinearity test's running sums of normalised coordinates
  (at most 2**16 terms in [-1, 1]) are limited to 2**17, their means
  (`Ratio_Within`, saturated at 1) to [-1, 1], and its sums of products
  of centred coordinates (at most 2**16 terms of at most 4) to 2**19;
  the transform from normalised plate points to calibrated coordinates (a
  tile size times the plate's centre or half extent, up to 1.0E140 times
  1.0E150) is checked against 1.0E150 by `Transforms.Compose` (a plate
  beyond it gives Bad_Parameter); the sums
  of the DLT's normal equations (at most 2**17) are limited to 2**20,
  those of the Gauss-Newton steps (at most 2**59 for J**T J and 2**52
  for J**T e) and the sum of squared distances (at most 2**45) to 2**62;
  the root of the mean squared distance is limited to 2**31 (the mean is
  at most 2**62; the runtime's `Sqrt` has no upper bound in its
  contract), the RMS (a product of two bounded values) to at least 0,
  and the root of the determinant at the plate's centre (at most 2**51)
  to 2**26; a tile aspect whose quotient or root falls outside its
  bound, a quotient of the warp's scale that exceeds its limit, and a
  first axis of the plate's image that is the zero vector give
  Bad_Parameter, but the tile sizes are tested to be within 1024 of each
  other and the determinant to be at least 2**(-30) before, so none of
  these happens; the solver forms a multiplier only when the pivot is
  not smaller than the entry below it, and divides by a pivot only when
  it is not zero (both always hold after its pivot search);
* guards for facts that the called contracts do not state:
  `ks_image_set_selected_space_name` of a space that
  `ks_coordinate_space_tree_add_space` has just added reports
  Failure_Other if it fails, which it cannot.

Limits that act and belong to the documented behaviour: a residual
component or a distance beyond 4.0E150 counts as 4.0E150 in the RMS
error; candidates beyond Max_Corners are not considered; a grid stops
Max_Span (255) steps from its seed, a prediction is searched at most 65
pixels along each axis, and at most Max_Seeds (512) seeds are tried.

`AMV.Kernels.CNL_Search` keeps its sums in integers and states the
remaining bounds with guards that never act:

* the entries of an integral image (`Levels.Add_Sum`, `Add_Square`) are
  limited to 255 * 2**24 and 65025 * 2**24 (a search box has at most
  Max_Search_Pixels = 2**24 pixels), and the sums over a window
  (`Levels.Window_Sums`, four entries each) to [0, 255 * 2**20] and
  [0, 65025 * 2**20] (a window has at most 2**20 pixels); the sums over
  the cared-for pixels of a pattern trained with a mask
  (`Levels.Masked_Statistics`, `Correlation.Masked_Sums`,
  `Masked_Window_Sums`) are added row by row and need no guard;
* the score (`Correlation.Squared_Ratio`): a denominator below 1 gives 0
  (both spreads are at least 1), and the squared correlation is limited
  to [0, 1] (it lies there by the Cauchy-Schwarz inequality; the limit can
  act only by rounding at 1);
* the contrast (`Correlation.Contrast_At`): a ratio of spreads that does
  not fit below 2**56 gives 2**28 (the pattern's spread is at least 1),
  and the root (the runtime's `Sqrt` has no upper bound in its contract)
  is limited to 2**28;
* the quadratic fit (`Correlation.Grid_Peak`): the weighted sums of at
  most 16 scores are limited to 64 (they are at most 36) and the
  coefficients to 16 (they are at most 2);
* `Search.Overlap_Along` limits a ratio within [0, 1] to [0, 1];
* `Search.Choose` takes a match only when its score is at least
  AcceptThreshold and at most the score of the match taken before it,
  which always holds (the matches are kept best first and score at least
  AcceptThreshold); these tests state the proved order and threshold of
  the results;
* `Find` limits a chosen position to the last position of level 0 and
  `Window_Coordinate` a window coordinate to the scored positions (the
  search area extended by the partial match limits): the refined
  positions are positions of level 0 (`Search.Refine`), and an offset
  along an axis is found only when the neighbours along it are positions
  too;
* `Correlation.Partial_Score` multiplies by N_in / N for
  PartialMatchReduceScore only when the clipped count N_in is below the
  pattern level's count N (otherwise the factor is 1 and changes nothing;
  the plan does not relate the clipped count to N, so the test states the
  bound the ratio needs).

`AMV.Kernels.PM_Align` keeps its proofs linear by carrying bounds in
subtypes (pattern coordinates within 1.0E9, unit vectors, offsets within
2**20 pixels, positions within 2**33, scales and zone angles, the
quantised features as integers) and forming products through
`AMV.Kernels.Numerics`; the grid search sums products of integers only.
Its limits that never act:

* every gradient value read from a pyramid is limited to +/-256 (a Sobel
  derivative divided by 8 of grey levels, smoothed or averaged, is at most
  127.5), and a bilinear sample, a convex combination of four of them, to
  the same bound; the score buffer is read through a limit to [-1, 1] (it
  holds scores in [0, 1] and -1);
* the square roots of the largest singular value (`Largest_Stretch`:
  Sqrt has no upper bound in its contract) to 4 and 2; the sums of the
  centroid (at most 2048 terms of at most 1.0E9) to 2**42; the sums of the
  normal equations of the refinement (at most 2048 terms of at most 16) to
  2**24; the root of the mean squared distance of the matched features (at
  most 1) to 1; a gradient magnitude to 1024 (at most 256 Sqrt (2)); the
  contrast to 1024; Coverage, the outside fraction and the ratios of counts
  (`Fraction_Of`, a `Ratio_Within` below 1) to [0, 1]; the pixel indices of
  positions to 2**40, grid positions to 2**32 and positions to 2**33
  (within an image they are below 2**31); a grid score's sum (at most 2048
  products of at most 127 * 128 twice, below 2**27) to 2**27 before it is
  divided (`Score_Of`); a step of the refinement over the radius
  (`Over_Radius`, at most 2 over at least 1) to 2;
* a feature's edge is looked for only when its mapped position lies
  within 2**32 (beyond, it lies outside every image anyway);
* the early stop of the grid score assumes that no feature adds more than
  16384 (two quantised unit vectors are at most 127.71 long, so their
  product is at most 16310): it never drops a position that would reach
  the threshold;
* `Check_Params` repeats the test of `Valid_Run_Params` after the checks
  of `Check_Run_Params`, which are that test; `Build_Results` appends a
  result only when its score is at most the last one, which the sorted
  finals always satisfy: both state facts for the proof.

Limits that can act and so belong to the documented behaviour: a mapped
feature's offset is limited to 2**20 pixels (a pattern mapped that far lies
outside every image) and the model's radius in pixels to [1, 2**20]; a
vector shorter than 1.0E-9 has no direction (its feature is skipped); a
component of a unit vector is limited to +/-1 (rounding); a grid score is
limited to [0, 1] (rounded unit vectors are up to 0.6 percent longer than
127); the vertex of a parabola to half a sample from the middle one; a
step of the refinement to 2 (pixels, or pixels at the model's radius); a
column of the normal equations to +/-4 (only a selected space far from a
similarity reaches it); the rotation and the scale of a pose are brought
into their zones (wrapped for a zone of a whole circle, limited otherwise);
the centroid of the model is limited to 1.0E9 (rounding).

## Proof notes

Lessons from `AMV.Kernels.Coordinate_Spaces`, the first kernel with a
quantified data invariant (details in `docs/handoff/SPARK_PLAN.md` 6.1):

* `Valid_Tree` states its quantified part on the array entries
  (`Tree.Spaces (I)`, ...) rather than through a function of the whole
  tree. gnatprove proves a goal that is an expression function call by
  proving the conjuncts of its body, which removes the term a quantifier
  over that function would be instantiated with; and after one entry of a
  tree changes, the tree is a different term, which such a quantifier no
  longer matches. Entry reads match in both cases.
* Functions called directly in that quantifier have no precondition (the
  lexical order `Less` is total); with one, the provers could not use the
  quantifier at all.
* Internal subprograms that need a valid tree take it as the body's
  subtype `Valid_Tree_Type`, whose `Dynamic_Predicate` is `Valid_Tree`:
  gnatprove proves the predicate at every call and assumes it inside, and
  the assertion policy keeps it out of the executable code, so no
  quantified precondition is evaluated at run time (`docs/DESIGN.md` 9.2).
* Loop invariants avoid nested indexing such as
  `R.Spaces (R.Spaces (I).Parent)`, whose preservation across an update
  was not provable at level 2; a ghost lemma with a proof loop derives
  such facts once the tree being built no longer changes
  (`Lemma_Moved_Links`).
* Level 2 limits each prover by wall-clock time (5 seconds), so a proof
  that needs 3 to 5 seconds on a quiet machine fails under load (and on
  slower CI machines). Keep every check well below that: when the tree
  API was aligned with VisionPro, two loop invariants of `Delete_Subtree`
  and one of `Add_Space` that had been close to the limit started to fail
  under load. They now prove in about 1 to 2.5 seconds because
  `Delete_Subtree` states the untouched part of `Keep` explicitly
  (`for all J in I + 1 .. Space_Index'Last => not Keep (J)`) and asserts
  the new entry's link before it is written, and `Add_Space` states its
  "moved up by one" invariant field by field instead of as one
  conjunction. Run `gnatprove -f --report=statistics` and look at the
  slowest checks after changing a kernel.

Lessons from `AMV.Kernels.Images`, the first kernel with owned handles:

* SPARK forbids `=` on two access values (and `'Address`), so an entry
  point cannot tell that a C caller passed the same handle twice. The
  entry points that take several handles only read or write pixel
  values, never a size or a pixel array, so aliasing cannot cause an
  invalid access; their functional postconditions assume distinct
  handles, as for the other C pointers (see below).
* An `in` parameter of a named access-to-variable type lets the callee
  change the designated object; postconditions state what stays (the
  ghost `Size_Of`, `Valid_Image`) or callers lose it. Pixels on entry
  are compared through the total ghost function `Pixels_Of` with
  `pragma Unevaluated_Use_Of_Old (Allow)`, so that `'Old` may appear
  under a condition.
* A two-dimensional array assignment with sliding (`Matrix :=
  Image.Pixels.all` with other bounds) followed by `Matrix = ...` timed
  out; the copies with other bounds are element-wise loops with
  quantified invariants (assignments with equal bounds, as in
  `Duplicate`, prove at once).
* An array indexed by `Natural` may have 2**31 elements, one more than
  `Integer'Last`, so `'Length` is converted to `Int64` before any
  arithmetic.
* The provers know no bound on the length of `'Image`; the messages use
  `Image_Of`, which builds the digits itself and proves its length.

Lessons from `AMV.Kernels.Image_File`, the first kernel that parses
untrusted bytes:

* Index bounds such as `Row = Start + Y * Row_Length <= Last` are
  nonlinear. They are proved with a ghost lemma, `Lemma_Mul_Le (A, B, K)`
  (`0 <= A <= B` and `K >= 0` give `A * K <= B * K`), whose statement uses
  a 128-bit ghost integer type, so that the lemma cannot overflow
  whatever its arguments; the provers carry the facts back to the Int64
  arithmetic of the code. Products of a header's fields (a BMP stride
  times the height) are bounded the same way from `Width * Height <=
  Max_Pixels` (`Lemma_Stride`). Keep the factors constant per branch
  (a `case` on the bit depth, `3 * X` rather than `X * Bytes_Per_Pixel`):
  a product of two variables in a loop needs a lemma call of its own.
* Every read of a header field comes after a `Need` (the file has at
  least that many bytes) or the `Raster_Fits` check of a PNM header, and
  both are made before anything is allocated; that is what also proves
  the bound of 8 pixels per input byte (`Within_Input`).
* A subtype whose predicate refers to ghost code (the checked BMP header)
  uses `Ghost_Predicate`; `Dynamic_Predicate` must not.
* The postcondition of a long procedure with many failure paths
  (`Read_BMP_Header`) timed out until the facts it needs were gathered in
  a `pragma Assert_And_Cut` just before the result is built, with the
  arithmetic moved into a procedure (`Row_Layout`) and a lemma
  (`Lemma_Pixels_Per_Byte`) of their own.
* Flow analysis warns about a local handle released just before a
  `return` ("statement has no effect"). Allocate into the out or in out
  parameter that receives the image (the slot) instead, and release that.
* Concatenations that start with a `String` parameter need its lower
  bound; such parameters have a subtype with `'First = 1` and a bounded
  length (`Operation_Name`, `Field_Name`).
* An owned array that grows is hard to prove; decoding counts the images
  in a first pass and allocates exactly that many slots for the second.

Lessons from `AMV.Kernels.Shapes`, the first float kernel with a
variable-size structure:

* The polygon's vertices are of a constrained subtype (`Coordinate`,
  within +/-1.0E150), so the provers know the bound of every vertex from
  its type, without a quantified invariant over the vertex array; the
  opaque handle cannot be changed by C except through the entry points.
  Only the cheap structural part (count, array bounds) is checked at run
  time (`Valid_Polygon`).
* A loop that adds rounded floating-point terms (the shoelace sum, the
  perimeter) needs a per-step bound; `abs Sum <= Long_Float (I) * Step`
  was not proved across the rounded addition, so a small helper with a
  never-triggering clamp states it (listed above). Use powers of two for
  such bounds: a postcondition that compared a power-of-two bound with the
  decimal 1.0E157 was simply false (2**522 is about 1.4E157), and the
  prover was right.
* Facts of rounding monotonicity that a quotient needs (`Y - A.Y <=
  B.Y - A.Y` from `Y <= B.Y`) time out; telling the cases apart before
  dividing (`Num <= 0`, `Num >= Den`, otherwise `Unit_Ratio`) computes the
  same quotient and proves at once.
* Long procedures with several float paths (the ellipse map, the annulus
  section's box) were slow (6 to 8 seconds per check) until their parts
  moved into small functions whose postconditions carry the ranges
  (`Axis_Angle`, `Nearest_Quarter`, `Quarter_Turn`, `Full_Box`,
  `Section_Box`, `Include_Radii`); every check now proves in at most a
  few seconds.

Lessons from `AMV.Kernels.Regions`, the first kernel with a counting
(Gold) property over a variable-size array:

* The flags are a two-dimensional matrix indexed by the pixel
  coordinates themselves (`Flags (Y, X)`, bounds `Y_Min .. Y_Max` by
  `X_Min .. X_Max`), so `Contains`, the fills, the search for the
  rectangle, the shrinking copy and the duplicate need no index
  arithmetic at all; only the stream reader, which
  fills the matrix from a flat buffer, needs a 128-bit lemma for its
  running index.
* The count is a recursive ghost expression function over the matrix
  (`Row_Count`, `Rows_Count`, with `Subprogram_Variant`), whose
  postconditions carry the bounds needed against overflow (a linear bound
  with 2**31, and the exact product in 128-bit integers). The counting
  loop runs over a matrix that no longer changes, so it needs no frame
  lemma; two recursive ghost lemmas give "count = Width * Height implies
  every flag is set" and "one set flag implies count >= 1".
* gnatprove proves a goal that is a call of a Boolean expression function
  by proving the conjuncts of its body, which removes the term that the
  quantified facts mention (as for `Valid_Tree` above). `Inside`, the
  definition of rasterisation, is therefore a function whose
  postcondition states the definition rather than an expression
  function; the facts of the fill stay matched.
* Facts that must outlive a freed matrix (the candidate flags) are first
  stated on a ghost copy of it taken on entry (`Old_Flags` in
  `Build_Region`, a `pragma Assert` before `Free`), and facts of a matrix
  moved or copied are asserted in each branch before the branches join.
* A procedure that takes a flag matrix over (`Build_Region`, an `in out`
  owning access that is null on return) states its result against
  `Flags.all'Old`, the matrix on entry; the callers combine that with the
  postcondition of their fill. Flow analysis reports a local handed to
  such a procedure as "set by ... but not used after the call"; a
  `pragma Assert (Flags = null)` after the call (the matrix was taken
  over) reads it and keeps `--warnings=error` quiet.

Lessons from `AMV.Kernels.Image_Math`, the first floating-point image
kernel:

* Facts about the values of heap data (the pixels of an argument, a
  table of weights, a vector of running sums) would need quantified
  invariants through every loop that touches them. Reading them through a
  clamp to their bound instead (see above) keeps every loop invariant
  scalar, except the one that states the bound of the image being
  written, which follows the pattern of `Fill_All`.
* A loop that writes two images at once (Sobel's Gx and Gy) did not
  prove, the same loop writing one image did: the derivative is computed
  in a function of its own and each image filled by its own pass.
* Flow analysis takes a call of `Release` on a local handle just before
  the end of its scope for a statement without effect; the deallocations
  written in place (`Free (Temp.Pixels); Free (Temp)`) are accepted.
* `'Loop_Entry` needs an object as its prefix (`Acc'Last'Loop_Entry` is
  illegal); keep the value in a constant before the loop, or state the
  bound through another array that does not change.
* gnatprove checks every call of `Exp` for overflow, and the runtime's
  contract gives no bound on its result (see the trusted parts).

Lessons from `AMV.Kernels.Geometry`:

* A product of two variables is slow for the provers even with constant
  bounds on both; `Numerics.Mul_Within (X, Y, LX, LY)` with constant
  limits gives the caller the constant bound `LX * LY` at once.
* gnatprove 16 rejects the non-static `'Exponent` and `'Scaling`; the
  exponent is found by comparisons with static powers of two and the
  scaling done as a product with an exactly computed power of two (one
  multiplication, so it rounds as `'Scaling` does), in two exact steps
  below 2**(-500) where the power itself would overflow.
* Division by a determinant that may be tiny (Kasa, Newton, damped
  Gauss-Newton) is formed only when the quotient is below twice the
  runaway limit (`Ratio_Within`); a larger quotient puts the centre
  beyond the limit, which the iteration treats as a runaway centre as it
  did after the (possibly infinite) division before.

Lessons from the image processing filter kernels (`AMV.Kernels.Histogram`,
`Pixel_Map`, `Sobel_Edge`, `Image_Sharpness`):

* The recursive ghost count of `AMV.Kernels.Regions` carries over to a
  count per bin: the loop invariant `for all B in Counts'Range =>
  Counts (B) = Rows_Count (.., B, Y) + Row_Count (.., B, Y, X + 1)` is
  proved as it stands, for a bin function (`Bin_Of`) that is an ordinary
  function with a complete postcondition. Counting into Int64 keeps the
  bound of each step linear (a row adds at most 2**31); only the final
  conversion to Int32 needs the 128-bit product bound of the image size
  (`Lemma_Total_Bound`). Two counts of different parameters (the Auto
  bins of a run whose Num_Bins is not 256, and the counts per grey level)
  are not equal for the provers without an induction, so the kernel
  simply counts each.
* gnatprove 16 rejects a composite local declared inside a loop before
  its loop invariant ("non-scalar object declared before loop-invariant is
  not yet supported"); scalar constants for its components work.
* A whole-image property that a flood fill must keep (`Two_Valued`, every
  region pixel holds one of two values) is stated once as a ghost
  expression function. Written inline in the fill's loops, the
  invariant after the step that changes one pixel took up to 24 seconds
  under load. The step is now a procedure of its own (`Visit`) whose
  postcondition says that the property holds afterwards when it held on
  entry (`Two_Valued (..)'Old`), so the loop invariants follow at once
  (a ghost function cannot appear in a checked precondition, so the
  implication stands in for one); every check of the kernel now proves
  in about a second.
* `X'Length` of an array behind an access component timed out in a
  postcondition where `X'Last + 1` (with `X'First = 0` known) proved.

Lessons from `AMV.Kernels.Blob`:

* A tool kernel has many tables whose entries index each other (labels,
  classes, targets, feature numbers). Proving range invariants for all of
  them would put a quantified invariant into every loop; reading each
  entry through a range test that never fails at run time keeps the
  Silver proofs scalar, and leaves the quantified invariants to the
  three Gold properties.
* A ghost copy of an array (`Old : constant ... := Area with Ghost`) must
  not be declared in a loop body before the loop invariant ("not yet
  supported"); the update and its lemma moved into a small procedure
  (`Increment_Area`) whose postcondition states the effect on the sum.
* Internal subprograms must not have quantified preconditions (they are
  checked at run time). The merge of the sort therefore states
  sortedness as a conditional postcondition ("if both runs were sorted on
  entry, the merged range is sorted"), which needs no precondition at
  all, and the counting of the areas zeroes its table itself (with a
  ghost lemma for the sum of zeros) instead of requiring zeros.
* Otsu's threshold is computed from integer counts and sums with the
  bounded products of `AMV.Kernels.Numerics` (`Mul_Within`,
  `Square_Within`, `Ratio_Within`); the floating-point measures follow the
  same pattern (small functions such as `Quadratic`, `Bilinear` and
  `Principal` whose postconditions carry the bounds). Written as one
  procedure with every quantity in its declarative part, the moments had
  checks that timed out under load; split into those functions, every
  check proves within seconds.
* An array whose `'First` is 0 may still be empty with a `'Last` far below
  -1 (the bounds of a null range need not belong to the index subtype),
  so a count bounded by `'Last + 1` needs `'Last >= 0` in the
  precondition, and an expression `Lo - 1` needs `Lo >= 0`, not only
  `Lo >= A'First`.
* A procedure whose postcondition bounds a counter it advances (the next
  free label) must also say that the counter does not go back
  (`Next >= Next'Old`), or a loop invariant relating another variable to
  the counter is lost at every call.

Lessons from `AMV.Kernels.Blob.Extrema` (the extrema-angle measures and
the medians):

* A range invariant over an array that a loop permutes ("every value of
  V (First .. Last) lies within [Lo, Hi]") was slow to prove with the
  exchanges written inline (one preservation needed about 30 seconds); a
  `Swap` whose postcondition states the exchange and, conditionally, that
  the range is kept (`if In_Bounds (V'Old, ..) then In_Bounds (V, ..)`,
  so no quantified precondition), and a partition step with the same
  conditional postcondition, keep each check to a few seconds.
* A pseudo-random index from a 64-bit modular generator
  (`(Seed / 2**32) mod Span` on `Unsigned_64`) took 70 seconds for its
  range check (bit-vector division); Park and Miller's generator in
  `Int64` (`Seed * 48271 mod (2**31 - 1)`) needs no such reasoning.
* Floating-point checks written straight into the fields of the result
  record carried the whole record into every proof obligation (some above
  10 seconds, some unproved); computing the values in small procedures on
  ranged subtypes (`Extent`, `Position`, `Mass`) and copying them at the
  end leaves the record assignments trivial, and the monotonicity of
  rounding (`Origin + Lo <= Origin + Median` when `Lo <= Median`) proves
  in a procedure of three statements (`Place`).
* The quantified postcondition over the whole feature map (every pixel of
  the feature lies within the extents) is proved row by row: `Row_Extent`
  has one quantifier over a row, and the loop over the rows only widens
  the extents.

Lessons from `AMV.Kernels.Caliper`, the first tool kernel:

* The first proof run left fourteen checks unproved, nearly all of them
  products or sums whose bounds needed several facts from a long procedure.
  Each went away when the computation moved into a small subprogram with a
  range postcondition: `Times (C, K)` (an expression function, so callers
  still see the exact product), `Centroid`, `Midpoint`, `Finish_Geometry`;
  a message built from many concatenated literals and a computed name
  (`Check_Scorer`) proved at once when the checks only chose a fault code
  and one call built the message.
* `B'Length` of an array indexed by `Natural` may be 2**31, beyond
  `Integer`; preconditions state `Count - 1 <= B'Last` instead.
* Candidates carry their bounds in their component subtypes (positions in
  [0, 32768], contrasts in [-255, 255], keys in [0, 255]), so the sorted
  buffer needs only one quantified invariant for the facts that depend on
  the run (edges inside the profile, keys at most 1 for scores).

Lessons from `AMV.Kernels.Find_Line` and `AMV.Kernels.Find_Circle`:

* A local owning pointer freed just before a `return` makes flow analysis
  warn that the call has no effect. Building the results in the `out`
  parameter from the start, and destroying them through the entry point
  `Results_Destroy` on every failure path, removes the warnings and the
  separate cleanup of the arrays.
* Moving an owned handle into an array of handles leaves the source
  "moved"; a loop that does this must give it a value again (`null`)
  before the next iteration.
* NumPointsFound and NumPointsUsed are proved to count the found and used
  items by a final loop over the finished items whose invariants are the
  recursive ghost counts (as for the pixel count of a region), rather than
  by tracking the indices of the fitted points through the fit.

Lessons from `AMV.Kernels.IP_One_Image`:

* Every operator whose output pixel depends on the input pixel alone
  (Threshold, Quantize, AddSubtractConstant, MultiplyConstant, PixelMap)
  builds a table of 256 entries with an iterated aggregate
  (`[for V in Grey_8 => Threshold_Value (V, P)]`) and applies it with one
  procedure (`Map_Pixels`) whose loop invariant states the table lookup;
  the Gold fact of each operator then follows without any lemma, the
  provers reading the table's entries from the aggregate.
* A kernel needs no trusted allocation helper of its own when every
  buffer is an image of `AMV.Kernels.Images`: the work lines of the
  running extrema are one-row images.
* Facts that must survive the step of a pipeline (pixels outside the
  region keep their input values) are asserted on the new image before
  the previous one is freed; the loop invariant over the operator list
  then needs only the new image and the input. The output size follows a
  recursive function over the list (`Size_After`, first `Swaps` for the
  quarter turns alone), unfolded once per step; the same function, run
  once before any pixel is computed, rejects a list whose images would
  exceed the size limit, so each step's precondition (the next image
  fits) comes from one quantified fact.
* `Release` (a procedure freeing an `in out` handle) called on a local
  just before the end of its scope draws the flow warning "statement has
  no effect", as noted for the earlier kernels; the deallocations written
  in place (`Free (X.Pixels); Free (X)`) do not.

Lessons from the image processing geometry kernels
(`AMV.Kernels.Affine_Transform`, `Copy_Region`, `IP_Two_Image`,
`Image_Convert`, `Polar_Unwrap` and the private `Image_Sampling`):

* A Gold property of every output pixel whose value comes from a
  floating-point mapping (nearest-neighbour sampling) is stated through
  functions of the pixel indices (`Nearest_At`, `Sample_X`) that the loop
  calls itself, so the loop invariants are those of the fills of
  AMV.Kernels.Images. The existential form at the entry point ("the fill
  value or some input pixel") follows from a ghost lemma per pixel that
  asserts the witness (the pixel at the two `Nearest_Index` values) and a
  ghost loop over the image; written as an expression function, the
  nearest sample (`if Inside_Area ... then Image.Pixels (...) else Fill`)
  already carries the witness.
* The sample point functions of the polar unwrap were expression functions
  at first: their bodies (cosines, sines, the transform) were inlined into
  every quantified fact, and the provers then failed on the precondition
  `Long_Float (X) + 0.5 <= Long_Float (Width)` and on an assertion that
  only restated a quantified hypothesis. As ordinary functions with range
  postconditions, with the pixel index turned into a fraction in [0, 1]
  by a function with a clamp (`Pixel_Fraction`), the same facts prove at
  once.
* A product with generous constant bounds on both factors (a quotient of
  at most 1.0E140 times an output size) still timed out as a plain
  multiplication; `Numerics.Mul_Within` gives the bound directly.
* The fill of the two-image tools had a loop invariant that took 6 to 10
  seconds under load while the same loop of `AMV.Kernels.Pixel_Map` is
  fast: its terms read two images and select a formula. An ordinary
  function per output pixel (`Combined_At (Op, Mode, A, B, X, Y)`, whose
  postcondition gives the formula) leaves one call per pixel in the
  invariants, and every check of the kernel now proves within a second or
  two; turning only the formula into an ordinary function made it slower.
  The same Execute with a long postcondition (the polar unwrap's, 14
  seconds) proves at once when the steps after the checks move into a
  procedure of their own (`Unwrap`) whose postcondition is the part that
  needs them.
* Output sizes computed from floating-point lengths are Gold when the
  entry point's postcondition names the very functions the body calls
  (`Output_Width (Region, Pixel_From_Region, Params)`), each with a range
  postcondition; a length that could overflow a product is saturated
  first (`Saturating_Product`), which keeps every bound linear.

Lessons from `AMV.Kernels.Dimensioning`:

* Many entry points with the same input checks: each check is a helper
  with an `in out` status that does nothing after a failure, whose
  postcondition says that the status is kept or becomes the one failure
  the helper can report (a ghost `Kept_Or`); the entry points then call
  the helpers in a row and test the status once, and their postconditions
  list exactly the failures of the helpers they call.
* Bounds in subtypes instead of loop invariants: the moment sums of the
  ellipse fit are record components of a subtype with the bound, and each
  addition goes through a clamp, so the moment loop needs no invariant;
  the matrices of the reduced problem are arrays of subtypes whose bounds
  follow from one step to the next (`T_Entry`, `M_Entry`, `Coefficient`
  are expression functions that return such a subtype), so a whole chain
  of products of bounded values proves without any invariant.
* gnatprove 16 stopped with "cannot untangle node N_IF_EXPRESSION" on an
  if-expression inside an aggregate that read variables a nested
  procedure had changed; computing the values first (or zeroing them
  where they are not reported) avoids it.
* A matrix filled by loops after an initial zero fill gave flow warnings
  ("unused assignment") for the fill; iterated component associations
  (`[for K in 1 .. 3 => [for J in 1 .. 3 => ...]]`) build it at once.
* Ranking the trial fits of the greedy removal by the Sampson distance
  (value over gradient of the conic) failed for an outlier at the
  ellipse's centre, where the gradient vanishes and that distance is
  unbounded; it masked a second outlier. The fit now ranks by the radial
  distance (along the ray from the centre), exact on the ellipse and
  finite at the centre, and reports the exact distances to the nearest
  points.

Lessons from `AMV.Kernels.Calib_Fix`:

* The exact structure of a fitted transform (a rotation matrix of Cos and
  Sin of the fitted angle, A = D and B = -C, orthogonal columns) is Gold
  only when the entries are computed as the very expressions the
  postcondition states (`Sx * EF.Cos (Theta)`), not through the bounded
  helpers of `Numerics` (whose results are only bounded, not equal to the
  product); the bound of such a product is then a run-time guard
  (`KT.Bounded (T)`, which never fails) instead of a proof. "Unit scale"
  is stated as A = Cos (R) and C = Sin (R) for the fitted R: the runtime's
  contracts give no identity between Cos and Sin, so A**2 + C**2 = 1 could
  not be stated, and it is tested.
* The fits work on points centred on their centroids and divided by the
  largest centred coordinate, so every sum of products is a sum of terms
  in [-1, 1] (`Numerics.Times_Unit`, `Square_Within`) kept in a subtype by
  a clamp that never acts; the only quotients left are by sums known to
  be large enough (checked guards such as `Min_Q`), formed with
  `Ratio_Within`.
* The postcondition of the aspect fit (the columns Sx (cos, sin) and
  Sy (-sin, cos)) timed out at the end of the whole fit; moved into a
  procedure of its own that builds the transform from Sx, Sy and the angle
  (`Aspect_Result`), it proves at once.
* gnatprove unrolls a loop with static bounds and no loop invariant: the
  11 x 11 window of the corner refinement (`Window_Sums`) became one
  formula of 121 copies of the body, which ran for over twenty minutes
  without a result. A `pragma Loop_Invariant (True)` in each loop stops
  the unrolling; the window's sums keep their bounds in the subtypes of
  their record, so the invariant needs nothing else, and the whole
  procedure proves within seconds.
* Preconditions such as `X + Window + 1 <= Last` overflow for an `X` near
  `Natural'Last`; written as `X <= Last - Window - 1` they need no bound
  on `X`.
* The same holds for the 16 points of the X-junction test's ring: the
  loops that read and scan it, without invariants, cost up to 10 seconds
  per check; with `pragma Loop_Invariant (True)` the slowest needs 6.
* A loop invariant that bounds a floating-point running sum by the loop
  index (`Spread <= 255.0 * Long_Float (K)`) did not prove: the provers
  do not relate the rounded `255 * K + 255` to `255 * (K + 1)`. A range
  subtype at the total bound with a limit there (which never acts)
  proves at once.
* "No grid index twice" is stated as an order: the detector emits its
  corners by walking the grid table row by row, so the invariant needs
  only adjacent pairs (`Row_Major_Less (Corners (K - 1), Corners (K))`)
  and the last corner against the walk's position, where pairwise
  distinctness would need a quadratic invariant.
* An array indexed from 0 may be empty with a `'Last` below -1, so
  "`Found <= Cand'Last`" for `Found = -1` needs `Count - 1 <= Cand'Last`
  in the precondition; and a map's `'Last` is a `Natural` only when the
  precondition says it is at least 0.
* The origin adjustment: "the default adjustment gives exactly the fit"
  is proved by returning the fit itself for it (`Is_Identity_Adjustment`)
  instead of composing it with the identity, since the contract of
  `Transforms.Compose` gives only the bound of its result. What a setter
  keeps (the calibrated state, the fit, the points) is stated through
  total functions of the handle (`Is_Calibrated`, `Fit_Of`, `Count_Of`,
  `Adjustment_Of`), so that their `'Old` values exist for a null handle
  too.

Lessons from the nonlinear mode of `AMV.Kernels.Calib_Fix` (`Radial`,
`Warp`, `Solver`):

* The model is evaluated in normalised coordinates (grid points and
  pixels scaled into [-1, 1]) with every parameter in a range subtype, so
  every intermediate value of a point of the model and of its Jacobian
  has a static bound that `Numerics.Mul_Within`, `Times_Unit`,
  `Square_Within` and `Unit_Ratio` carry from step to step (a quotient
  N / w is formed as 4 * Unit_Ratio (N, 4 w) after the test
  |N| <= 4 w). No nonlinear goal is left to the provers; the whole fit
  proves within a minute.
* A loop that tests entries one by one and returns on the first bad one
  (`for I in 1 .. 6 loop if not (abs H (I) <= ...) then return`) leaves
  the provers nothing about the entries after the loop unless its
  invariant says so; one conjunction of the eight tests proves at once.
* The accumulators of the normal equations are arrays of a range subtype
  (`Acc_Value`, the sum limited to its bound by a clamp that never acts),
  so their bound needs no quantified invariant over the 10 x 10 matrix;
  the solver's matrix type has a range subtype for its entries too, and
  every update is tested against it before it is stored.
* A matrix built by an aggregate (`[for I in .. => [for J in .. =>
  ...]]`) instead of a default aggregate overwritten by loops keeps flow
  analysis from reporting the default as an unused assignment (an error
  with `--warnings=error`).
* Generalising the fit from integer grid indices to real plate
  coordinates (for N-point calibrations) kept the checkerboard's results
  bit for bit: the grid indices are passed as reals and the tile sizes
  are still applied after the fit, and the normalisation of integers
  (sums, differences, halving) is exact in floating point. A bound of a
  comparison that a range check needs (a point on the image, X at most
  Width - 0.5) proves faster against a constant of a range subtype
  computed once (`Right : constant Pixel_Value := Long_Float (Width) -
  0.5`) than against the conversion in the loop (4 seconds before).
* A bound that a precondition inside a nested loop needs, derived from
  the loop's context (the corner distance in the detector's `Near_Corner`:
  `abs X <= 2**32` from `X <= Long_Float (Map'Last (2))` and the map's
  size), took up to 30 seconds per check; asserted once before the loop,
  it takes 3 seconds and the checks in the loop under one.

Lessons from `AMV.Kernels.CNL_Search`, the first kernel with a trained
handle:

* The pyramid levels are stacked in one image (one owned handle, the
  levels one under the other) instead of an array of handles, and the
  internal subprograms take the arrays themselves (`Stack.Pixels.all`,
  `Sums.all`) rather than handles, so they have no access parameters and
  the bounds of every array are fixed for the provers.
* The facts that tie the levels of the image, of its integral images and
  of the pattern together are a plan record with a subtype predicate
  (`Valid_Search_Plan`) quantified over the levels. Written as an
  expression function, the per-level fact (`Level_OK`) was taken apart
  into its conjuncts when an assertion named it, and the instance of the
  quantifier was no longer found (the assertion timed out); as an
  ordinary function whose postcondition is the expression function
  (`Level_OK'Result = Level_Facts (..)`) it matches at once, as noted
  above for `Valid_Tree` and `Inside`. Loops that build the plan state
  `Level_Facts`, which survives updates of the other levels.
* A trained pattern is passed to internal subprograms as a subtype of the
  record (`Trained_Data`, predicate `Valid_Data and Trained`), so their
  preconditions need no quantifier over the levels.
* Products of two bounded integers (N Sum (p w), Sum p Sum w) prove in
  small functions with a postcondition giving the bound, after an
  assertion that compares with the product by the constant bound.
* The quadratic fit first kept its five sums in variables with a loop
  invariant on their bounds, and computed its divisors and centres as
  products and quotients of small constants (3 * (2/3), Shift / 2); one
  precondition took 22 to 26 seconds under load. With the sums as record
  components of a bounded subtype (no loop invariant at all), one
  procedure per step (`Add_Sample`, `Solve`) and the divisors and centres
  as case expressions with literal values, every check of the fit
  proves within two seconds.
* A fact of each result written as an expression function of the
  results handle (EdgeHit's `Edge_Hit_Of (Item, Results)`) changes its
  argument whenever an item is stored, so the provers unfolded it, down
  to its floating-point comparisons, in every loop invariant and
  assertion of `Find`: two of them timed out and one took 26 seconds.
  Stated through an ordinary function of the item and of the handle's
  scalar fields (`Placed`, whose postcondition is the expression function
  `Placed_Facts`, as `Level_OK` above), the facts carry over by
  congruence: the loop invariant proves in 2 seconds, and the fact that
  the default limits give EdgeHit None is proved once per item in
  `Make_Item` and passed up through the postconditions.
* The clipped sums of a partial window (`Correlation.Clipped_*_Sums`)
  first multiplied grey levels in the loop, as `Masked_Sums` does, but
  with offsets in the indices; the overflow checks of the sums took 9 to
  12 seconds. With the products in a function whose body the loops do
  not see and whose result subtype is 0 .. 65025 (`Product`), every
  check of these loops takes at most 3 seconds.

Lessons from `AMV.Kernels.PM_Align`, a trained object with a search over
rotation and scale:

* The model is a record without pointers (fixed arrays of features per
  level, each component of a constrained subtype: pattern coordinates
  within 1.0E9, normals within [-1, 1]), so the provers know the bound of
  every feature from its type, the duplicate is one assignment
  (`Copy.all := Pattern.all`, proved equal) and the only allocation is the
  record itself. Derived data (the centroid, the radius) is recomputed
  from the features at every run instead of being stored, so the stream
  reader only checks values and counts.
* The inner loop of the grid search multiplies quantised unit vectors
  (integers in -127 .. 127, the direction images 8-bit images of the image
  kernel): its only loop invariant is the linear bound of the sum, and it
  needs no floating-point fact at all.
* Every image of the pyramids, the score buffer and the clutter mask come
  from the proved entry points of `AMV.Kernels.Images` and
  `AMV.Kernels.Image_Math`, so the kernel's only trusted bodies allocate
  its two records. A pyramid (a record of 26 owned images) that a
  subprogram builds and frees draws the flow warnings "statement has no
  effect" and "set by Release but not used" when it is a local; the work
  that uses it moved into a procedure that takes it `in out` (`Locate`,
  `Build_Model`, whose postconditions say it is released), and the caller's
  object is named `Unused_Pyramid`. Images created and freed inside one
  subprogram are freed in place (`Free (X.Pixels); Free (X)`), and the
  work images of a pyramid live in the pyramid record.
* A nested function that reads constants of the enclosing declarative
  part does not see their bounds (the provers produced a counterexample
  with a coordinate of 1.0E29 for the footprint test of the clutter); as a
  library-level function with the bounds in its precondition
  (`In_Parallelogram`) it proves at once. Loop invariants that compare a
  rounded floating-point sum with a count (`Sum <= Long_Float (Matched)`)
  are not preserved for the provers; a limit on each addition
  (`Long_Float'Min (Sum + Term, Long_Float (Max_Features))`, which never
  acts) bounds the sum instead.
* `2 ** Level` with a variable exponent gave no bound to the provers; a
  case expression over the six levels does.
* The Gold facts of the results (order, threshold, zones, bounds) are
  established where the results are appended, with tests that never fail
  (the finals are sorted before), so that the loop invariant is the Gold
  predicate itself and no fact has to travel through the search, the
  refinement or the measures, which are Silver only.

Lessons from `AMV.Kernels.Create_Shapes`:

* To state in a postcondition what an entry point computes from its
  mapped inputs, the mapping has to be callable in a contract. A
  procedure is not, and two calls of a procedure with the same arguments
  are not known to give the same results; two calls of a function are.
  The kernel therefore wraps each map entry point of
  `AMV.Kernels.Shapes` (and the checks around it) in a function that
  returns the mapped shape with its status (`Map_Line`, ...), calls it
  in the body and names the same call in the postcondition, which then
  proves at once (`Result = (X, Y, Quarter_Turn (Map_Line (Line, T,
  Line_Name).Line.Rotation))`).
* Such functions should take no String argument. The first version
  passed the property name for the messages as a string literal, and
  none of these postconditions proved within the timeout: the literal in
  the postcondition and the one in the body are two array values whose
  equality the provers did not establish. An enumeration of the names
  (`Input_Name`), turned into a string inside the function, made them
  trivial.

Lessons from `AMV.Kernels.Tool_Group`, a kernel of collections and a
run protocol rather than numbers:

* Both handles designate records without pointers (fixed arrays of 256
  members and of 128 terminals), so a duplicate is one assignment, the
  only allocations are the two records, and no invariant ties an array
  to a count. The member array (16 bytes per member) is shifted by
  iterated aggregates (`[for J in Member_Index => (if J < Position then
  .. else Members (J - 1))]`), which prove at once, the distinct keys
  included; the terminal array (about 1.3 KB per terminal) is shifted by
  loops, because an aggregate that reads the array it replaces needs a
  temporary of the whole array on the stack.
* Invariants that a C caller's handle could only show by an O(n**2) test
  (distinct keys, distinct names) are not checked at run time: each
  entry point states them as `(if Valid_Group (Group)'Old then
  Valid_Group (Group))` with ghost predicates, and create gives an empty
  handle, so they hold for every handle the kernel made.
* Names are compared by `Same_Name`, an ordinary function whose
  postcondition states the definition (length and characters). A search
  turns the name asked for into its stored form once (`To_Name`) and an
  add stores that very value, so that "the new name differs from every
  other" carries over by congruence; symmetry and transitivity come from
  a lemma with a null body (`Lemma_Same_Name`), and "the terminal found
  is the only one so named" from a ghost loop (`Lemma_Only_Match`).
* Distinct names after an insertion into a shifted array did not prove
  from the shift's postcondition; a ghost lemma with two nested loops and
  an explicit index map (`Lemma_Distinct_Insert`, `Old_Position`) proves
  it. A move is a removal, whose postcondition keeps the names distinct
  directly, followed by that insertion, after an assertion that the moved
  name differs from the others.
* The failure postcondition of the entry points that create a handle on
  demand (`Group_Of (Group) = Group_Of (Group)'Old`) timed out until the
  helper's postcondition said that a failed creation leaves null a handle
  that was null on entry (`Is_Null (Group)'Old`); every check that can
  fail is made before the handle is created.
* The run's Gold facts are relations between one call and the next,
  stated on the caller's cursor (`Cursor.Worst = Worse (Cursor.Worst'Old,
  Result)`, `Cursor.Next >= Cursor.Next'Old`, ...): the kernel cannot
  remember a whole run, and the checks at every entry point
  (`Cursor_Matches`, `Cursor_Consistent`, the change counter) make the
  relations hold for any record a C caller passes.

## Assumptions and limits

* gnatprove assumes that every `Long_Float` value is finite. At run time
  the kernels are compiled with `pragma Validity_Checks ("F")`, so a NaN or
  an infinity coming from C or from the Ada API reaches the entry point's
  finiteness test (`X >= -Long_Float'Last and X <= Long_Float'Last`, false
  for both) and is rejected with `Failure_Bad_Parameter`. The prover sees
  that test as always true; the tests (`tests/test_kernels.adb`,
  `tests/c/test_c_api.c`) cover it. The Ada API is compiled with the same
  pragma (`docs/DESIGN.md` 9.3), so it passes such a value on instead of
  raising Constraint_Error itself; `tests/test_robustness.adb` sweeps the
  whole Ada API with NaNs, infinities and huge values. Values read from a
  stream by the Ada API (a polygon's vertices) reach the same tests.
* Floating point results are proved to stay within their stated ranges and
  never to overflow; their accuracy (for example that `Hypot` is within an
  ulp of the true length) is shown by tests, not proofs.
* The C side: pointers for results and status are trusted to point to
  valid objects that do not overlap the other arguments (C cannot express
  that, and SPARK sees them as Ada `out` parameters, which never alias
  the inputs). An image handle that is not null is trusted to come from
  create or duplicate and not to have been destroyed (a dangling pointer
  cannot be checked); a record that is inconsistent anyway is rejected
  with `Failure_Bad_Parameter`. Handles passed to one call are assumed to
  be different images for the functional postconditions (see the proof
  notes); absence of run-time errors does not depend on it.
