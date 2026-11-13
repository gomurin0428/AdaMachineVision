/*
 * AdaMachineVision (AMV) C API.
 *
 * Every function here is an entry point of one of the library's SPARK
 * kernels (package AMV.Kernels and its children), exported with the C
 * calling convention. The kernels are proved free of run-time errors with
 * gnatprove; see docs/DESIGN.md (section 9) and docs/PROOF.md.
 *
 * Conventions:
 *  - Every function reports its outcome in a ks_status. On success,
 *    status->failure is KS_FAILURE_NONE. Otherwise it is one of the
 *    KS_FAILURE_* codes and status->message holds status->length
 *    characters (followed by NUL characters) naming the argument or
 *    property at fault.
 *  - Floating point arguments must be finite; a NaN or an infinity gives
 *    KS_FAILURE_BAD_PARAMETER.
 *  - Pointer arguments for results and status must point to valid
 *    objects that do not overlap the other arguments; they are not
 *    checked.
 *  - The library is written in Ada: call adainit() once before the first
 *    ks_ function and adafinal() after the last one (both are generated
 *    by the Ada binder when the library is linked into the program).
 *
 * This header is written by hand. Its layout and values are pinned on the
 * Ada side by representation clauses and compile-time checks
 * (src/amv-kernels*.ads, tests/test_kernels.adb) and on the C side by the
 * static assertions below and tests/c/test_c_api.c.
 *
 * AMV is not affiliated with or endorsed by Cognex Corporation; "Cognex"
 * and "VisionPro" are trademarks of Cognex Corporation.
 */

#ifndef AMV_H
#define AMV_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version of this C ABI; ks_abi_version() returns the version of the
   library actually linked. AMV 0.1.0 has ABI version 2; CHANGELOG.md
   lists every change of version. */
#define KS_ABI_VERSION 3

/* ------------------------------------------------------------------ */
/* Status                                                              */
/* ------------------------------------------------------------------ */

#define KS_FAILURE_NONE                          0
#define KS_FAILURE_IMAGE_NO_PIXELS               1
#define KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME 2
#define KS_FAILURE_OPERATOR_NOT_TRAINED          3
#define KS_FAILURE_TRANSFORM_SINGULAR            4
#define KS_FAILURE_IMAGE_FILE                    5
#define KS_FAILURE_BAD_PARAMETER                 6
#define KS_FAILURE_OUT_OF_MEMORY                 7
#define KS_FAILURE_OTHER                         8
#define KS_FAILURE_INDEX_OUT_OF_RANGE            9

#define KS_MAX_MESSAGE_LENGTH 200

typedef struct {
    int32_t failure;                          /* KS_FAILURE_* */
    int32_t length;                           /* 0 .. KS_MAX_MESSAGE_LENGTH */
    char    message[KS_MAX_MESSAGE_LENGTH + 1]; /* NUL after length chars */
} ks_status;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_status) == 212, "ks_status must be 212 bytes");
_Static_assert(offsetof(ks_status, length) == 4, "ks_status.length offset");
_Static_assert(offsetof(ks_status, message) == 8, "ks_status.message offset");
#endif

/* The version of the C ABI of the linked library (KS_ABI_VERSION when
   the header and the library match). */
int32_t ks_abi_version(void);

/* ------------------------------------------------------------------ */
/* Misc (CogMisc)                                                      */
/* ------------------------------------------------------------------ */

/* degrees * pi / 180. */
void ks_misc_deg_to_rad(double degrees, double *result, ks_status *status);

/* radians * 180 / pi; KS_FAILURE_BAD_PARAMETER when |radians| > 3.1e306. */
void ks_misc_rad_to_deg(double radians, double *result, ks_status *status);

/* The equivalent angle in (-pi, pi]. */
void ks_misc_norm_angle(double radians, double *result, ks_status *status);

/* The equivalent angle modulo pi, in (-pi/2, pi/2]. */
void ks_misc_norm_angle_pi(double radians, double *result,
                           ks_status *status);

/* norm_angle(a - b), without overflow for any finite a and b. */
void ks_misc_angle_difference(double a, double b, double *result,
                              ks_status *status);

/* sqrt(x*x + y*y) without intermediate overflow or underflow;
   KS_FAILURE_BAD_PARAMETER when the result exceeds DBL_MAX. */
void ks_misc_hypot(double x, double y, double *result, ks_status *status);

/* ------------------------------------------------------------------ */
/* Transforms (CogTransform2DLinear)                                   */
/* ------------------------------------------------------------------ */

/* (x, y) maps to (a x + b y + translation_x, c x + d y + translation_y).
   Every entry, translation, coordinate, area, aspect, angle and tolerance
   must be finite and within +/-KS_TRANSFORM_MAX_VALUE, every scaling
   within +/-KS_TRANSFORM_MAX_SCALING; otherwise, and when a result would
   leave those bounds, the functions fail with KS_FAILURE_BAD_PARAMETER
   (an inverse beyond them: KS_FAILURE_TRANSFORM_SINGULAR). */

#define KS_TRANSFORM_MAX_VALUE   1.0e150
#define KS_TRANSFORM_MAX_SCALING 2.0e150

typedef struct {
    double a, b, c, d, translation_x, translation_y;
} ks_transform_2d_linear;

typedef struct {
    double scaling_x, scaling_y;   /* >= 0 */
    double rotation_x, rotation_y; /* in (-pi, pi] */
    double skew;                   /* rotation_y - rotation_x in (-pi, pi] */
} ks_transform_2d_linear_decomposition;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_transform_2d_linear) == 48,
               "ks_transform_2d_linear must be 48 bytes");
_Static_assert(sizeof(ks_transform_2d_linear_decomposition) == 40,
               "ks_transform_2d_linear_decomposition must be 40 bytes");
#endif

/* Property codes for ks_transform_2d_linear_set_property. */
#define KS_TRANSFORM_PROPERTY_ROTATION   0
#define KS_TRANSFORM_PROPERTY_SKEW       1
#define KS_TRANSFORM_PROPERTY_SCALING    2
#define KS_TRANSFORM_PROPERTY_ASPECT     3
#define KS_TRANSFORM_PROPERTY_SCALING_X  4
#define KS_TRANSFORM_PROPERTY_SCALING_Y  5
#define KS_TRANSFORM_PROPERTY_ROTATION_X 6
#define KS_TRANSFORM_PROPERTY_ROTATION_Y 7

#define KS_TRANSFORM_MAP_ANGLE_ZERO_TOLERANCE 1.0e-14

void ks_transform_2d_linear_decompose(
    const ks_transform_2d_linear *transform,
    ks_transform_2d_linear_decomposition *result, ks_status *status);

/* scaling_y / scaling_x (0 when scaling_x is 0). */
void ks_transform_2d_linear_aspect(const ks_transform_2d_linear *transform,
                                   double *result, ks_status *status);

/* SetScalingsRotationsTranslation. */
void ks_transform_2d_linear_recompose(
    double scaling_x, double scaling_y, double rotation_x,
    double rotation_y, double translation_x, double translation_y,
    ks_transform_2d_linear *result, ks_status *status);

/* SetScalingAspectRotationSkewTranslation. */
void ks_transform_2d_linear_recompose_scaling_aspect(
    double scaling, double aspect, double rotation, double skew,
    double translation_x, double translation_y,
    ks_transform_2d_linear *result, ks_status *status);

/* The transform with one decomposed property changed (SetRotation, ...). */
void ks_transform_2d_linear_set_property(
    const ks_transform_2d_linear *transform, int32_t property, double value,
    ks_transform_2d_linear *result, ks_status *status);

/* Uniform scaling and rotation, then translation (a = d, b = -c exactly). */
void ks_transform_2d_linear_create_similarity(
    double scaling, double rotation, double translation_x,
    double translation_y, ks_transform_2d_linear *result, ks_status *status);

void ks_transform_2d_linear_map_point(
    const ks_transform_2d_linear *transform, double x, double y,
    double *mapped_x, double *mapped_y, ks_status *status);

/* The linear part only. */
void ks_transform_2d_linear_map_vector(
    const ks_transform_2d_linear *transform, double x, double y,
    double *mapped_x, double *mapped_y, ks_status *status);

/* Direction in (-pi, pi] of the mapped unit vector at angle;
   KS_FAILURE_TRANSFORM_SINGULAR when it maps to zero. */
void ks_transform_2d_linear_map_angle(
    const ks_transform_2d_linear *transform, double angle, double *result,
    ks_status *status);

void ks_transform_2d_linear_invert(const ks_transform_2d_linear *transform,
                                   ks_transform_2d_linear *result,
                                   ks_status *status);

/* Applies other first, then transform. */
void ks_transform_2d_linear_compose(const ks_transform_2d_linear *transform,
                                    const ks_transform_2d_linear *other,
                                    ks_transform_2d_linear *result,
                                    ks_status *status);

/* MatrixDeterminant: a d - b c, as written (at most 2e300 in magnitude;
   not a valid argument of the other functions in general). */
void ks_transform_2d_linear_matrix_determinant(
    const ks_transform_2d_linear *transform, double *result,
    ks_status *status);

/* MapArea: fabs(a d - b c) * area; area may be negative. */
void ks_transform_2d_linear_map_area(
    const ks_transform_2d_linear *transform, double area, double *result,
    ks_status *status);

/* GetMatrixElement / SetMatrixElement: row 0 is (a, b), row 1 is (c, d).
   row and column must be 0 or 1, otherwise KS_FAILURE_BAD_PARAMETER
   (checked after the transform). set_matrix_element returns the
   transform with that element replaced by value and the rest kept. */
void ks_transform_2d_linear_get_matrix_element(
    const ks_transform_2d_linear *transform, int32_t row, int32_t column,
    double *result, ks_status *status);
void ks_transform_2d_linear_set_matrix_element(
    const ks_transform_2d_linear *transform, int32_t row, int32_t column,
    double value, ks_transform_2d_linear *result, ks_status *status);

/* Tests: *result is 1 or 0; tolerance must be >= 0.
   identity (Identity): every entry, the translation included, within
   tolerance of the identity's. matrix_identity (MatrixIdentity): a, b, c
   and d within tolerance of 1, 0, 0, 1. singular (Singular):
   fabs(a d - b c) <= tolerance. is_similarity and is_axis_aligned are AMV
   additions with a tolerance relative to the largest matrix entry. */
void ks_transform_2d_linear_identity(
    const ks_transform_2d_linear *transform, double tolerance,
    int32_t *result, ks_status *status);
void ks_transform_2d_linear_matrix_identity(
    const ks_transform_2d_linear *transform, double tolerance,
    int32_t *result, ks_status *status);
void ks_transform_2d_linear_singular(
    const ks_transform_2d_linear *transform, double tolerance,
    int32_t *result, ks_status *status);
void ks_transform_2d_linear_is_similarity(
    const ks_transform_2d_linear *transform, double tolerance,
    int32_t *result, ks_status *status);
void ks_transform_2d_linear_is_axis_aligned(
    const ks_transform_2d_linear *transform, double tolerance,
    int32_t *result, ks_status *status);

/* ------------------------------------------------------------------ */
/* Coordinate space trees (CogCoordinateSpaceTree)                     */
/* ------------------------------------------------------------------ */

/* A tree holds the root space "@" and up to KS_MAX_SPACES - 1 other
   spaces, each with a parent and a parent_from_child transform that maps
   the space's coordinates to its parent's (VisionPro's parentFromNew),
   stored exactly as given. Spaces are named by path from the root with
   components separated by '\' ("@\Fixture\Part"); a component is a
   non-empty string without '\' other than "@", "#" and ".". Name
   arguments are full names.

   The tree is a plain struct: count entries of spaces[] are in use, entry
   0 is the root (name "@", parent -1, identity transform), and the
   entries are sorted by full name in lexical order (byte by byte, a
   prefix first), so every parent comes before its children. Every
   function first checks that its tree satisfies these rules and fails
   with KS_FAILURE_BAD_PARAMETER ("Tree is not a valid coordinate space
   tree") otherwise; a function that changes a tree leaves it valid on
   success and unchanged on failure. Use ks_coordinate_space_tree_init
   rather than filling the struct by hand.

   Names are ks_space_name: length characters in text, not NUL-terminated
   when length is KS_MAX_SPACE_NAME_LENGTH. A name argument with a length
   above KS_MAX_SPACE_NAME_LENGTH names no space; names returned have NUL
   characters after their text. A malformed or unknown name gives
   KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME with a message naming the
   function and the name. Transforms are bounded as above
   (KS_TRANSFORM_MAX_VALUE). Codes (duplicate_handling, pathname_format)
   and flags (children_only, 0 or 1) are checked first and give
   KS_FAILURE_BAD_PARAMETER for any other value. */

#define KS_MAX_SPACES            64
#define KS_MAX_SPACE_NAME_LENGTH 256

/* duplicate_handling of ks_coordinate_space_tree_add_space
   (CogAddSpaceConstants): what to do when the space exists already. */
#define KS_ADD_SPACE_DUPLICATE_IS_ERROR 0 /* fail, KS_FAILURE_BAD_PARAMETER */
#define KS_ADD_SPACE_REPLACE_DUPLICATE  1 /* replace its transform only */
#define KS_ADD_SPACE_IGNORE_DUPLICATE   2 /* change nothing */

/* pathname_format of the functions that return names
   (CogSpaceTreePathnameConstants): NONE gives the last component ("@" for
   the root), FULL the full name, PARTIAL the path relative to the
   function's space_name argument for a space below it ("B\C" for
   "@\A\B\C" below "@\A") and the full name for any other space (the
   space itself, its parent). */
#define KS_SPACE_TREE_PATHNAME_NONE    0
#define KS_SPACE_TREE_PATHNAME_FULL    1
#define KS_SPACE_TREE_PATHNAME_PARTIAL 2

typedef struct {
    int32_t length;
    char    text[KS_MAX_SPACE_NAME_LENGTH];
} ks_space_name;

typedef struct {
    ks_space_name          name;              /* full name */
    int32_t                parent;            /* index of the parent; -1 */
    ks_transform_2d_linear parent_from_child; /* identity for the root */
} ks_coordinate_space;

typedef struct {
    int32_t             count;                /* 1 .. KS_MAX_SPACES */
    ks_coordinate_space spaces[KS_MAX_SPACES];
} ks_coordinate_space_tree;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_space_name) == 260, "ks_space_name must be 260 bytes");
_Static_assert(offsetof(ks_space_name, text) == 4, "ks_space_name.text offset");
_Static_assert(sizeof(ks_coordinate_space) == 312,
               "ks_coordinate_space must be 312 bytes");
_Static_assert(offsetof(ks_coordinate_space, parent) == 260,
               "ks_coordinate_space.parent offset");
_Static_assert(offsetof(ks_coordinate_space, parent_from_child) == 264,
               "ks_coordinate_space.parent_from_child offset");
_Static_assert(sizeof(ks_coordinate_space_tree) == 19976,
               "ks_coordinate_space_tree must be 19976 bytes");
_Static_assert(offsetof(ks_coordinate_space_tree, spaces) == 8,
               "ks_coordinate_space_tree.spaces offset");
#endif

/* The tree that holds only the root. Never fails. */
void ks_coordinate_space_tree_init(ks_coordinate_space_tree *tree,
                                   ks_status *status);

/* AddSpace: adds parent_space_name\new_space_name, whose coordinates
   parent_from_new maps into the parent's. When that space exists,
   duplicate_handling (KS_ADD_SPACE_*) decides. Failures, in the order
   checked: an unknown duplicate_handling code (KS_FAILURE_BAD_PARAMETER);
   an unknown parent or an invalid component
   (KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME); a transform beyond the
   bound (KS_FAILURE_BAD_PARAMETER) or not invertible within it
   (KS_FAILURE_TRANSFORM_SINGULAR); a full name longer than
   KS_MAX_SPACE_NAME_LENGTH, an existing space with
   KS_ADD_SPACE_DUPLICATE_IS_ERROR, a full tree (all
   KS_FAILURE_BAD_PARAMETER). */
void ks_coordinate_space_tree_add_space(
    ks_coordinate_space_tree *tree, const ks_space_name *parent_space_name,
    const ks_space_name *new_space_name,
    const ks_transform_2d_linear *parent_from_new, int32_t duplicate_handling,
    ks_status *status);

/* ChangeTransform: replaces the stored transform of the space
   (KS_FAILURE_BAD_PARAMETER for the root; transform checks as for
   add_space). */
void ks_coordinate_space_tree_change_transform(
    ks_coordinate_space_tree *tree, const ks_space_name *child_space_name,
    const ks_transform_2d_linear *new_parent_from_child, ks_status *status);

/* DeleteSubtree: removes the space and its descendants
   (KS_FAILURE_BAD_PARAMETER for the root). */
void ks_coordinate_space_tree_delete_subtree(
    ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    ks_status *status);

/* Removes every space but the root. */
void ks_coordinate_space_tree_clear(ks_coordinate_space_tree *tree,
                                    ks_status *status);

/* *result is 1 for "@" and every space of the tree, 0 for any other name;
   never fails on a name. */
void ks_coordinate_space_tree_space_exists(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t *result, ks_status *status);

/* The number of spaces, the root included. */
void ks_coordinate_space_tree_space_count(
    const ks_coordinate_space_tree *tree, int32_t *result,
    ks_status *status);

/* The index-th name (0-based) in lexical order; index 0 is "@".
   KS_FAILURE_INDEX_OUT_OF_RANGE unless 0 <= index < count. */
void ks_coordinate_space_tree_space_name(
    const ks_coordinate_space_tree *tree, int32_t index,
    ks_space_name *result, ks_status *status);

/* RootName: "@". */
void ks_coordinate_space_tree_root_name(
    const ks_coordinate_space_tree *tree, ks_space_name *result,
    ks_status *status);

/* ParentName: the parent's name in pathname_format (PARTIAL gives the
   full name); the empty name for the root. */
void ks_coordinate_space_tree_parent_name(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t pathname_format, ks_space_name *result, ks_status *status);

/* ChildNames: the number of children (immediate descendants) of the
   space, and the index-th of them (0-based, in lexical order of the full
   names) in pathname_format. KS_FAILURE_INDEX_OUT_OF_RANGE unless
   0 <= index < count. */
void ks_coordinate_space_tree_child_names_count(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t *result, ks_status *status);
void ks_coordinate_space_tree_child_name(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t pathname_format, int32_t index, ks_space_name *result,
    ks_status *status);

/* AllChildNames: the same for every descendant at any depth, preceded by
   the space itself when children_only is 0. */
void ks_coordinate_space_tree_all_child_names_count(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t children_only, int32_t *result, ks_status *status);
void ks_coordinate_space_tree_all_child_name(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t pathname_format, int32_t children_only, int32_t index,
    ks_space_name *result, ks_status *status);

/* VerifyName: *result is 1 and *found_name the name in pathname_format
   (PARTIAL gives the full name) when space_name is the full name of a
   space of the tree; 0 and the empty name for any other name (never fails
   on a name). */
void ks_coordinate_space_tree_verify_name(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    int32_t pathname_format, int32_t *result, ks_space_name *found_name,
    ks_status *status);

/* The stored transform, exactly as given; the identity for the root. */
void ks_coordinate_space_tree_parent_from_child_transform(
    const ks_coordinate_space_tree *tree, const ks_space_name *space_name,
    ks_transform_2d_linear *result, ks_status *status);

/* GetTransform: the transform from from_space_name coordinates to
   to_space_name coordinates, the inverse of root_from_to composed with
   root_from_from (root_from_from itself when to_space_name is "@"), where
   root_from_x composes the parent_from_child transforms from x up to the
   root: p_top * (... * (p_parent * (p_x * identity))). Exactly the
   identity for the same name twice. KS_FAILURE_TRANSFORM_SINGULAR when
   root_from_to cannot be inverted within the bound,
   KS_FAILURE_BAD_PARAMETER when a composition would leave it. */
void ks_coordinate_space_tree_get_transform(
    const ks_coordinate_space_tree *tree, const ks_space_name *to_space_name,
    const ks_space_name *from_space_name, ks_transform_2d_linear *result,
    ks_status *status);

/* ------------------------------------------------------------------ */
/* Images (CogImage8Grey, CogImage16Grey, CogImage24PlanarColor)       */
/* ------------------------------------------------------------------ */

/* An image's pixels live behind an opaque handle that *_create returns
   and *_destroy frees (and sets to NULL). A handle holds width x height
   pixels (both at least 1, width * height at most KS_IMAGE_MAX_PIXELS);
   pixel (x, y) is column x, row y, 0-based. The library never shares the
   pixels of two handles.

   NULL stands for an image without pixels (an unallocated image): width
   and height give 0, duplicate gives NULL, destroy does nothing, and every
   function that needs pixels fails with KS_FAILURE_IMAGE_NO_PIXELS. A
   handle that is not NULL must come from *_create or *_duplicate and not
   have been destroyed. A coordinate outside the image gives
   KS_FAILURE_INDEX_OUT_OF_RANGE; a size below 1 or above the limit gives
   KS_FAILURE_BAD_PARAMETER; KS_FAILURE_OUT_OF_MEMORY when the pixels
   cannot be allocated (the handle is then NULL).

   A 24-bit planar colour image is three 8-bit images of one size, red,
   green and blue (three NULLs for an image without pixels). The
   ks_image_24_planar_color_* functions take the three handles and fail
   with KS_FAILURE_BAD_PARAMETER for any other mix. Passing one handle as
   two planes is not detected (the library cannot compare handles); it is
   safe, the writes then happen in the order red, green, blue. */

#define KS_IMAGE_MAX_PIXELS 2147483647

typedef struct ks_image_8_grey ks_image_8_grey;   /* opaque */
typedef struct ks_image_16_grey ks_image_16_grey; /* opaque */

void ks_image_8_grey_create(int32_t width, int32_t height, uint8_t value,
                            ks_image_8_grey **image, ks_status *status);
void ks_image_8_grey_destroy(ks_image_8_grey **image, ks_status *status);
void ks_image_8_grey_width(const ks_image_8_grey *image, int32_t *result,
                           ks_status *status);
void ks_image_8_grey_height(const ks_image_8_grey *image, int32_t *result,
                            ks_status *status);
void ks_image_8_grey_get_pixel(const ks_image_8_grey *image, int32_t x,
                               int32_t y, uint8_t *value, ks_status *status);
/* Sets the pixel at (x, y) and no other. */
void ks_image_8_grey_set_pixel(ks_image_8_grey *image, int32_t x, int32_t y,
                               uint8_t value, ks_status *status);
void ks_image_8_grey_fill(ks_image_8_grey *image, uint8_t value,
                          ks_status *status);
/* A new image with the same pixels (NULL for NULL). */
void ks_image_8_grey_duplicate(const ks_image_8_grey *image,
                               ks_image_8_grey **result, ks_status *status);
/* Copy row y to or from the length bytes at row. The checks, in order:
   the image (KS_FAILURE_IMAGE_NO_PIXELS, KS_FAILURE_BAD_PARAMETER); y in
   0 .. height - 1 and length == width (KS_FAILURE_INDEX_OUT_OF_RANGE);
   row not NULL (KS_FAILURE_BAD_PARAMETER). */
void ks_image_8_grey_get_row(const ks_image_8_grey *image, int32_t y,
                             uint8_t *row, int32_t length,
                             ks_status *status);
void ks_image_8_grey_set_row(ks_image_8_grey *image, int32_t y,
                             const uint8_t *row, int32_t length,
                             ks_status *status);

/* The same for 16-bit images. */
void ks_image_16_grey_create(int32_t width, int32_t height, uint16_t value,
                             ks_image_16_grey **image, ks_status *status);
void ks_image_16_grey_destroy(ks_image_16_grey **image, ks_status *status);
void ks_image_16_grey_width(const ks_image_16_grey *image, int32_t *result,
                            ks_status *status);
void ks_image_16_grey_height(const ks_image_16_grey *image, int32_t *result,
                             ks_status *status);
void ks_image_16_grey_get_pixel(const ks_image_16_grey *image, int32_t x,
                                int32_t y, uint16_t *value,
                                ks_status *status);
void ks_image_16_grey_set_pixel(ks_image_16_grey *image, int32_t x,
                                int32_t y, uint16_t value,
                                ks_status *status);
void ks_image_16_grey_fill(ks_image_16_grey *image, uint16_t value,
                           ks_status *status);
void ks_image_16_grey_duplicate(const ks_image_16_grey *image,
                                ks_image_16_grey **result,
                                ks_status *status);
void ks_image_16_grey_get_row(const ks_image_16_grey *image, int32_t y,
                              uint16_t *row, int32_t length,
                              ks_status *status);
void ks_image_16_grey_set_row(ks_image_16_grey *image, int32_t y,
                              const uint16_t *row, int32_t length,
                              ks_status *status);

/* Colour images: three planes. create returns three new planes (three
   NULLs on failure); set_plane copies pixels into plane, one plane of a
   colour image (NULL for a colour image without pixels):
   KS_FAILURE_IMAGE_NO_PIXELS when pixels is NULL, KS_FAILURE_BAD_PARAMETER
   when the sizes differ; duplicate copies three planes (three NULLs for
   three NULLs). */
void ks_image_24_planar_color_create(
    int32_t width, int32_t height, uint8_t red_value, uint8_t green_value,
    uint8_t blue_value, ks_image_8_grey **red, ks_image_8_grey **green,
    ks_image_8_grey **blue, ks_status *status);
void ks_image_24_planar_color_get_pixel(
    const ks_image_8_grey *red, const ks_image_8_grey *green,
    const ks_image_8_grey *blue, int32_t x, int32_t y, uint8_t *red_value,
    uint8_t *green_value, uint8_t *blue_value, ks_status *status);
void ks_image_24_planar_color_set_pixel(
    ks_image_8_grey *red, ks_image_8_grey *green, ks_image_8_grey *blue,
    int32_t x, int32_t y, uint8_t red_value, uint8_t green_value,
    uint8_t blue_value, ks_status *status);
void ks_image_24_planar_color_set_plane(ks_image_8_grey *plane,
                                        const ks_image_8_grey *pixels,
                                        ks_status *status);
void ks_image_24_planar_color_duplicate(
    const ks_image_8_grey *red, const ks_image_8_grey *green,
    const ks_image_8_grey *blue, ks_image_8_grey **new_red,
    ks_image_8_grey **new_green, ks_image_8_grey **new_blue,
    ks_status *status);

/* The coordinate space state of an image (ICogImage): its tree, its
   selected space name as stored (selected) and its pixel_from_root
   transform (from root space "@" to pixel space "#"). "#" is pixel space,
   "." the selected space, every other name a space of the tree; a stored
   selection whose space has left the tree reads as "@". Every function
   first checks the tree (KS_FAILURE_BAD_PARAMETER, as for the tree
   functions); names returned have NUL characters after their text. */

/* The selection as it reads ("#", a space of the tree, or "@"). */
void ks_image_selected_space_name(const ks_coordinate_space_tree *tree,
                                  const ks_space_name *selected,
                                  ks_space_name *result, ks_status *status);
/* Selects "#" or a space of the tree ("." keeps the selection as it
   reads); KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME, selected unchanged,
   for any other name. */
void ks_image_set_selected_space_name(const ks_coordinate_space_tree *tree,
                                      ks_space_name *selected,
                                      const ks_space_name *space_name,
                                      ks_status *status);
/* "." as the selection reads, "#" and tree names unchanged;
   KS_FAILURE_IMAGE_BAD_SELECTED_SPACE_NAME for any other name. */
void ks_image_resolve_space_name(const ks_coordinate_space_tree *tree,
                                 const ks_space_name *selected,
                                 const ks_space_name *space_name,
                                 ks_space_name *result, ks_status *status);
/* GetTransform: from from_space_name to to_space_name, both resolved as
   above. Exactly the identity for the same space; between tree spaces the
   tree's get_transform; into "#": pixel_from_root composed with the tree's
   transform from the space into "@"; out of "#": the tree's transform from
   "@" into the space composed with the inverse of pixel_from_root. */
void ks_image_get_transform(const ks_coordinate_space_tree *tree,
                            const ks_space_name *selected,
                            const ks_transform_2d_linear *pixel_from_root,
                            const ks_space_name *to_space_name,
                            const ks_space_name *from_space_name,
                            ks_transform_2d_linear *result,
                            ks_status *status);
/* The selection rule of SetCoordinateSpaceTree: the selection as it reads
   in tree is kept when it is "#" or a space of new_tree, and becomes "@"
   otherwise. The caller then copies new_tree into the image's tree. */
void ks_image_selection_for_new_tree(const ks_coordinate_space_tree *tree,
                                     ks_space_name *selected,
                                     const ks_coordinate_space_tree *new_tree,
                                     ks_status *status);
/* Stores transform as pixel_from_root: it must be within
   KS_TRANSFORM_MAX_VALUE (KS_FAILURE_BAD_PARAMETER) and invertible within
   it (KS_FAILURE_TRANSFORM_SINGULAR); unchanged on failure. */
void ks_image_set_pixel_from_root_transform(
    ks_transform_2d_linear *pixel_from_root,
    const ks_transform_2d_linear *transform, ks_status *status);

/* ------------------------------------------------------------------ */
/* Image files (CogImageFile, CogImageFileTool)                        */
/* ------------------------------------------------------------------ */

/* The PNM and BMP codecs work on bytes in memory; reading and writing
   files is left to the caller. The formats and their rules are those of
   AMV.Image_File (src/amv-image_file.ads). Messages never contain a file
   name.

   bytes/length arguments: length must be in 0 .. KS_IMAGE_FILE_MAX_LENGTH
   and bytes not NULL when length > 0 (KS_FAILURE_BAD_PARAMETER); the
   library reads (or writes) exactly length bytes there. */

#define KS_IMAGE_FILE_MAX_LENGTH ((int64_t)1 << 56)

/* Modes of CogImageFile (CogImageFileModeConstants). */
#define KS_IMAGE_FILE_MODE_CLOSED 1
#define KS_IMAGE_FILE_MODE_READ   2
#define KS_IMAGE_FILE_MODE_WRITE  3
#define KS_IMAGE_FILE_MODE_UPDATE 4

/* Write formats, chosen from the extension of a file name. */
#define KS_IMAGE_FILE_FORMAT_PGM 1
#define KS_IMAGE_FILE_FORMAT_PPM 2
#define KS_IMAGE_FILE_FORMAT_PNM 3
#define KS_IMAGE_FILE_FORMAT_BMP 4

/* What a decoded file holds. */
#define KS_IMAGE_FILE_KIND_PNM 1
#define KS_IMAGE_FILE_KIND_BMP 2

/* Image types. */
#define KS_IMAGE_FILE_IMAGE_8_GREY            1
#define KS_IMAGE_FILE_IMAGE_16_GREY           2
#define KS_IMAGE_FILE_IMAGE_24_PLANAR_COLOR   3

/* Encodings of an image in a file. */
#define KS_IMAGE_FILE_ENCODING_P5_8          1 /* 8-bit grey, P5, 255 */
#define KS_IMAGE_FILE_ENCODING_P5_16         2 /* 16-bit grey, P5, 65535 */
#define KS_IMAGE_FILE_ENCODING_P6_FROM_GREY  3 /* 8-bit grey as P6, R=G=B */
#define KS_IMAGE_FILE_ENCODING_P6_COLOR      4 /* colour, P6, 255 */
#define KS_IMAGE_FILE_ENCODING_BMP_8         5 /* 8-bit grey palette BMP */
#define KS_IMAGE_FILE_ENCODING_BMP_24        6 /* colour, 24-bit BMP */

/* Operations whose mode rules require_open and require_mode check. */
#define KS_IMAGE_FILE_OPERATION_ITEM   1
#define KS_IMAGE_FILE_OPERATION_APPEND 2
#define KS_IMAGE_FILE_OPERATION_RUN    3

#define KS_IMAGE_FILE_MAX_IMAGES     2147483647
#define KS_IMAGE_FILE_MAX_BMP_SIZE   4294967295u

typedef struct ks_image_file_contents ks_image_file_contents; /* opaque */

/* Decodes every image of the complete contents of a PNM or BMP file
   (recognised from its first bytes) into a new contents handle, which
   ks_image_file_contents_destroy frees. KS_FAILURE_IMAGE_FILE for a file
   that is not well formed or not supported (*contents is then NULL);
   KS_FAILURE_OUT_OF_MEMORY. A header is checked against the bytes present
   before any pixels are allocated. */
void ks_image_file_decode(const uint8_t *bytes, int64_t length,
                          ks_image_file_contents **contents,
                          ks_status *status);
/* Frees the contents and its images and sets *contents to NULL. */
void ks_image_file_contents_destroy(ks_image_file_contents **contents,
                                    ks_status *status);
/* The number of images (0 for NULL) and the kind (0 for NULL). */
void ks_image_file_contents_count(const ks_image_file_contents *contents,
                                  int32_t *result, ks_status *status);
void ks_image_file_contents_kind(const ks_image_file_contents *contents,
                                 int32_t *result, ks_status *status);
/* The type and maxval (255 for BMP) of image index (0-based);
   KS_FAILURE_INDEX_OUT_OF_RANGE outside 0 .. count - 1. */
void ks_image_file_contents_image_info(
    const ks_image_file_contents *contents, int32_t index,
    int32_t *image_type, int32_t *maxval, ks_status *status);
/* KS_FAILURE_IMAGE_FILE unless image index exists ("the file holds 2
   image(s); there is no image with index 5"). */
void ks_image_file_contents_check_read_index(
    const ks_image_file_contents *contents, int32_t index,
    ks_status *status);
/* New copies of image index, owned by the caller, of the type the file
   gives it (KS_FAILURE_BAD_PARAMETER for another type). */
void ks_image_file_contents_get_8_grey(
    const ks_image_file_contents *contents, int32_t index,
    ks_image_8_grey **image, ks_status *status);
void ks_image_file_contents_get_16_grey(
    const ks_image_file_contents *contents, int32_t index,
    ks_image_16_grey **image, ks_status *status);
void ks_image_file_contents_get_24_planar_color(
    const ks_image_file_contents *contents, int32_t index,
    ks_image_8_grey **red, ks_image_8_grey **green, ks_image_8_grey **blue,
    ks_status *status);
/* Image index converted to a new 8-bit grey image: 8-bit samples kept,
   16-bit round(v * 255 / maxval), colour round(0.299 r + 0.587 g +
   0.114 b), rounded half up exactly. */
void ks_image_file_contents_get_8_grey_converted(
    const ks_image_file_contents *contents, int32_t index,
    ks_image_8_grey **image, ks_status *status);

/* The write format of a file name (length characters, not
   NUL-terminated): the extension after the last '.' of the last path
   component, ignoring case; KS_FAILURE_IMAGE_FILE for another one. */
void ks_image_file_format_from_name(const char *name, int32_t length,
                                    int32_t *format, ks_status *status);
/* The encoding of an image of image_type and this size in format:
   KS_FAILURE_IMAGE_NO_PIXELS for a size of 0, KS_FAILURE_IMAGE_FILE when
   the format cannot hold the image or a BMP file would be too large. */
void ks_image_file_choose_encoding(int32_t format, int32_t image_type,
                                   int32_t width, int32_t height,
                                   int32_t *encoding, ks_status *status);
/* The number of bytes ks_image_file_encode_* writes; separator 1 adds a
   leading line feed (PNM only). */
void ks_image_file_encoded_size(int32_t encoding, int32_t width,
                                int32_t height, int32_t separator,
                                int64_t *size, ks_status *status);
/* The rules of appending an image to a file object that has count images
   (count of its file object) and a disk file of disk_size bytes (0 when
   missing) whose last byte is final_byte: a BMP file holds one image
   (KS_FAILURE_IMAGE_FILE); a PNM image needs a leading line feed
   (*separator = 1) after a last byte that is not Netpbm whitespace.
   *new_count is count + 1. */
void ks_image_file_check_append(int32_t encoding, int32_t count,
                                int64_t disk_size, uint8_t final_byte,
                                int32_t *separator, int32_t *new_count,
                                ks_status *status);
/* Write the encoded image into exactly ks_image_file_encoded_size bytes
   (KS_FAILURE_BAD_PARAMETER for another length or an encoding of another
   image type); the bytes are unchanged on failure. */
void ks_image_file_encode_8_grey(int32_t encoding, int32_t separator,
                                 const ks_image_8_grey *image,
                                 uint8_t *bytes, int64_t length,
                                 ks_status *status);
void ks_image_file_encode_16_grey(int32_t encoding, int32_t separator,
                                  const ks_image_16_grey *image,
                                  uint8_t *bytes, int64_t length,
                                  ks_status *status);
void ks_image_file_encode_24_planar_color(
    int32_t encoding, int32_t separator, const ks_image_8_grey *red,
    const ks_image_8_grey *green, const ks_image_8_grey *blue,
    uint8_t *bytes, int64_t length, ks_status *status);
/* Update mode: the number of images of the contents of an existing file
   (0 for no bytes), checked as by decode without allocating them, and
   KS_FAILURE_IMAGE_FILE when they are not in format. */
void ks_image_file_count_for_update(int32_t format, const uint8_t *bytes,
                                    int64_t length, int32_t *count,
                                    ks_status *status);

/* The state rules of CogImageFile and CogImageFileTool. check_open_mode:
   Open takes READ, WRITE or UPDATE (KS_FAILURE_BAD_PARAMETER for CLOSED).
   require_open: KS_FAILURE_IMAGE_FILE when the file is closed;
   require_mode: also Item needs READ, Append needs WRITE or UPDATE.
   tool_next_index: the image a Read-mode run outputs (next_index mod
   count) and the next one; KS_FAILURE_IMAGE_FILE when count is 0. */
void ks_image_file_check_open_mode(int32_t mode, ks_status *status);
void ks_image_file_require_open(int32_t mode, int32_t operation,
                                ks_status *status);
void ks_image_file_require_mode(int32_t mode, int32_t operation,
                                ks_status *status);
void ks_image_file_tool_next_index(int32_t next_index, int32_t count,
                                   int32_t *index, int32_t *new_next_index,
                                   ks_status *status);

/* ------------------------------------------------------------------ */
/* Shapes (CogRectangle, CogRectangleAffine, CogCircle, CogEllipse,    */
/* CogPolygon, CogCircularAnnulusSection, CogLine, CogLineSegment,     */
/* CogPointMarker, CogCircularArc; geometry only)                      */
/* ------------------------------------------------------------------ */

/* The meaning of every property and operation is documented in
   src/amv-shapes.ads (AMV.Shapes) and src/amv-kernels-shapes.ads.
   Every coordinate and angle a shape holds, takes or returns must be
   finite and within +/-KS_SHAPE_MAX_VALUE, every length (width, height,
   side length, radius, length, a line's distance from the origin) within
   [0, KS_SHAPE_MAX_LENGTH], a radial_scale within [0, KS_SHAPE_MAX_VALUE]
   and radius * radial_scale within KS_SHAPE_MAX_LENGTH; otherwise, and
   when a result (a centre, corner, bounding box, end point or mapped
   shape) would leave those bounds, the functions fail with
   KS_FAILURE_BAD_PARAMETER naming the property. Areas lie within
   [0, KS_SHAPE_MAX_AREA], perimeters within [0, KS_SHAPE_MAX_PERIMETER].
   Transforms are bounded as for ks_transform_2d_linear_*. contains_point
   sets *result to 1 or 0. */

#define KS_SHAPE_MAX_VALUE      1.0e150
#define KS_SHAPE_MAX_LENGTH     4.0e150
#define KS_SHAPE_MAX_AREA       4.49423283715578976932e307 /* 2**1022 */
#define KS_SHAPE_MAX_PERIMETER  1.372959532026122e157 /* 2**522 */
#define KS_SHAPE_MAX_SLACK      1.0e145
#define KS_POLYGON_MAX_VERTICES 1048576
#define KS_POLYGON_APPEND       (-1)

/* Shape type codes (the result_type of a map that may change the type). */
#define KS_SHAPE_RECTANGLE                1
#define KS_SHAPE_RECTANGLE_AFFINE         2
#define KS_SHAPE_CIRCLE                   3
#define KS_SHAPE_ELLIPSE                  4
#define KS_SHAPE_POLYGON                  5
#define KS_SHAPE_CIRCULAR_ANNULUS_SECTION 6
#define KS_SHAPE_LINE                     7
#define KS_SHAPE_LINE_SEGMENT             8
#define KS_SHAPE_POINT_MARKER             9
#define KS_SHAPE_CIRCULAR_ARC             10

typedef struct {
    double x, y;          /* the corner with the smallest coordinates */
    double width, height; /* >= 0 */
} ks_rectangle;

typedef struct {
    double center_x, center_y;
    double side_x_length, side_y_length; /* >= 0 */
    double rotation, skew;
} ks_rectangle_affine;

typedef struct {
    double origin_x, origin_y;
    double corner_x_x, corner_x_y;
    double corner_y_x, corner_y_y;
    double corner_opposite_x, corner_opposite_y;
} ks_rectangle_affine_corners;

typedef struct {
    double center_x, center_y, radius;
} ks_circle;

typedef struct {
    double center_x, center_y, radius_x, radius_y, rotation;
} ks_ellipse;

typedef struct {
    double center_x, center_y, radius, angle_start, angle_span;
    double radial_scale;
} ks_circular_annulus_section;

typedef struct {
    double x, y, rotation;
} ks_line;

typedef struct {
    double start_x, start_y, end_x, end_y;
} ks_line_segment;

typedef struct {
    double x, y, rotation;
} ks_point_marker;

typedef struct {
    double center_x, center_y, radius, angle_start, angle_span;
} ks_circular_arc;

/* A polygon: an opaque handle; NULL is a polygon without vertices. */
typedef struct ks_polygon ks_polygon;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_rectangle) == 32, "ks_rectangle must be 32 bytes");
_Static_assert(offsetof(ks_rectangle, height) == 24,
               "ks_rectangle.height offset");
_Static_assert(sizeof(ks_rectangle_affine) == 48,
               "ks_rectangle_affine must be 48 bytes");
_Static_assert(offsetof(ks_rectangle_affine, skew) == 40,
               "ks_rectangle_affine.skew offset");
_Static_assert(sizeof(ks_rectangle_affine_corners) == 64,
               "ks_rectangle_affine_corners must be 64 bytes");
_Static_assert(offsetof(ks_rectangle_affine_corners, corner_opposite_y)
                   == 56,
               "ks_rectangle_affine_corners.corner_opposite_y offset");
_Static_assert(sizeof(ks_circle) == 24, "ks_circle must be 24 bytes");
_Static_assert(offsetof(ks_circle, radius) == 16, "ks_circle.radius offset");
_Static_assert(sizeof(ks_ellipse) == 40, "ks_ellipse must be 40 bytes");
_Static_assert(offsetof(ks_ellipse, rotation) == 32,
               "ks_ellipse.rotation offset");
_Static_assert(sizeof(ks_circular_annulus_section) == 48,
               "ks_circular_annulus_section must be 48 bytes");
_Static_assert(offsetof(ks_circular_annulus_section, radial_scale) == 40,
               "ks_circular_annulus_section.radial_scale offset");
_Static_assert(sizeof(ks_line) == 24, "ks_line must be 24 bytes");
_Static_assert(offsetof(ks_line, rotation) == 16, "ks_line.rotation offset");
_Static_assert(sizeof(ks_line_segment) == 32,
               "ks_line_segment must be 32 bytes");
_Static_assert(offsetof(ks_line_segment, end_y) == 24,
               "ks_line_segment.end_y offset");
_Static_assert(sizeof(ks_point_marker) == 24,
               "ks_point_marker must be 24 bytes");
_Static_assert(offsetof(ks_point_marker, rotation) == 16,
               "ks_point_marker.rotation offset");
_Static_assert(sizeof(ks_circular_arc) == 40,
               "ks_circular_arc must be 40 bytes");
_Static_assert(offsetof(ks_circular_arc, angle_span) == 32,
               "ks_circular_arc.angle_span offset");
#endif

/* CogRectangle. set_xy_width_height and set_center_width_height build a
   checked rectangle (width and height >= 0); from_bounding_box is
   EnclosingRectangle (min <= max required). map gives a rectangle
   (KS_SHAPE_RECTANGLE, in *rectangle_result) under an axis-aligned
   transform, otherwise an affine rectangle (KS_SHAPE_RECTANGLE_AFFINE, in
   *affine_result). */
void ks_rectangle_set_xy_width_height(double x, double y, double width,
                                      double height, ks_rectangle *result,
                                      ks_status *status);
void ks_rectangle_set_center_width_height(double center_x, double center_y,
                                          double width, double height,
                                          ks_rectangle *result,
                                          ks_status *status);
void ks_rectangle_get_center_width_height(const ks_rectangle *rectangle,
                                          double *center_x, double *center_y,
                                          double *width, double *height,
                                          ks_status *status);
void ks_rectangle_contains_point(const ks_rectangle *rectangle, double x,
                                 double y, int32_t *result,
                                 ks_status *status);
void ks_rectangle_boundary_slack(const ks_rectangle *rectangle,
                                 double *result, ks_status *status);
void ks_rectangle_get_bounding_box(const ks_rectangle *rectangle,
                                   double *min_x, double *min_y,
                                   double *max_x, double *max_y,
                                   ks_status *status);
void ks_rectangle_area(const ks_rectangle *rectangle, double *result,
                       ks_status *status);
void ks_rectangle_perimeter(const ks_rectangle *rectangle, double *result,
                            ks_status *status);
void ks_rectangle_map(const ks_rectangle *rectangle,
                      const ks_transform_2d_linear *transform,
                      int32_t *result_type, ks_rectangle *rectangle_result,
                      ks_rectangle_affine *affine_result, ks_status *status);
void ks_rectangle_from_bounding_box(double min_x, double min_y, double max_x,
                                    double max_y, ks_rectangle *result,
                                    ks_status *status);

/* CogRectangleAffine. */
void ks_rectangle_affine_set_center_lengths_rotation_skew(
    double center_x, double center_y, double side_x_length,
    double side_y_length, double rotation, double skew,
    ks_rectangle_affine *result, ks_status *status);
void ks_rectangle_affine_set_origin_lengths_rotation_skew(
    double origin_x, double origin_y, double side_x_length,
    double side_y_length, double rotation, double skew,
    ks_rectangle_affine *result, ks_status *status);
void ks_rectangle_affine_set_origin_corner_x_corner_y(
    double origin_x, double origin_y, double corner_x_x, double corner_x_y,
    double corner_y_x, double corner_y_y, ks_rectangle_affine *result,
    ks_status *status);
void ks_rectangle_affine_get_corners(const ks_rectangle_affine *rectangle,
                                     ks_rectangle_affine_corners *result,
                                     ks_status *status);
void ks_rectangle_affine_get_parent_from_child_transform(
    const ks_rectangle_affine *rectangle, ks_transform_2d_linear *result,
    ks_status *status);
void ks_rectangle_affine_contains_point(const ks_rectangle_affine *rectangle,
                                        double x, double y, int32_t *result,
                                        ks_status *status);
void ks_rectangle_affine_boundary_slack(const ks_rectangle_affine *rectangle,
                                        double *result, ks_status *status);
void ks_rectangle_affine_get_bounding_box(
    const ks_rectangle_affine *rectangle, double *min_x, double *min_y,
    double *max_x, double *max_y, ks_status *status);
void ks_rectangle_affine_area(const ks_rectangle_affine *rectangle,
                              double *result, ks_status *status);
void ks_rectangle_affine_map(const ks_rectangle_affine *rectangle,
                             const ks_transform_2d_linear *transform,
                             ks_rectangle_affine *result, ks_status *status);

/* CogCircle. map gives a circle (KS_SHAPE_CIRCLE) under a similarity,
   possibly reflecting, otherwise an ellipse (KS_SHAPE_ELLIPSE). */
void ks_circle_set_center_radius(double center_x, double center_y,
                                 double radius, ks_circle *result,
                                 ks_status *status);
void ks_circle_contains_point(const ks_circle *circle, double x, double y,
                              int32_t *result, ks_status *status);
void ks_circle_boundary_slack(const ks_circle *circle, double *result,
                              ks_status *status);
void ks_circle_get_bounding_box(const ks_circle *circle, double *min_x,
                                double *min_y, double *max_x, double *max_y,
                                ks_status *status);
void ks_circle_area(const ks_circle *circle, double *result,
                    ks_status *status);
void ks_circle_map(const ks_circle *circle,
                   const ks_transform_2d_linear *transform,
                   int32_t *result_type, ks_circle *circle_result,
                   ks_ellipse *ellipse_result, ks_status *status);

/* CogEllipse. */
void ks_ellipse_set_center_xy_radius_xy_rotation(double center_x,
                                                 double center_y,
                                                 double radius_x,
                                                 double radius_y,
                                                 double rotation,
                                                 ks_ellipse *result,
                                                 ks_status *status);
void ks_ellipse_contains_point(const ks_ellipse *ellipse, double x, double y,
                               int32_t *result, ks_status *status);
void ks_ellipse_boundary_slack(const ks_ellipse *ellipse, double *result,
                               ks_status *status);
void ks_ellipse_get_bounding_box(const ks_ellipse *ellipse, double *min_x,
                                 double *min_y, double *max_x, double *max_y,
                                 ks_status *status);
void ks_ellipse_area(const ks_ellipse *ellipse, double *result,
                     ks_status *status);
void ks_ellipse_map(const ks_ellipse *ellipse,
                    const ks_transform_2d_linear *transform,
                    ks_ellipse *result, ks_status *status);

/* CogPolygon: at most KS_POLYGON_MAX_VERTICES vertices, indexed from 0.
   create gives an empty polygon and add_vertex creates one when
   *polygon is NULL; destroy frees it and sets *polygon to NULL. An index
   outside the vertices gives KS_FAILURE_INDEX_OUT_OF_RANGE (add_vertex
   takes -1 .. count, KS_POLYGON_APPEND appends). duplicate and map give
   new handles (NULL for NULL); a failed call changes nothing. */
void ks_polygon_create(ks_polygon **polygon, ks_status *status);
void ks_polygon_destroy(ks_polygon **polygon, ks_status *status);
void ks_polygon_duplicate(const ks_polygon *polygon, ks_polygon **result,
                          ks_status *status);
void ks_polygon_num_vertices(const ks_polygon *polygon, int32_t *result,
                             ks_status *status);
void ks_polygon_get_vertex(const ks_polygon *polygon, int32_t index,
                           double *x, double *y, ks_status *status);
void ks_polygon_set_vertex(ks_polygon *polygon, int32_t index, double x,
                           double y, ks_status *status);
void ks_polygon_add_vertex(ks_polygon **polygon, double x, double y,
                           int32_t index, ks_status *status);
void ks_polygon_remove_vertex(ks_polygon *polygon, int32_t index,
                              ks_status *status);
void ks_polygon_clear(ks_polygon *polygon, ks_status *status);
void ks_polygon_contains_point(const ks_polygon *polygon, double x, double y,
                               int32_t *result, ks_status *status);
void ks_polygon_boundary_slack(const ks_polygon *polygon, double *result,
                               ks_status *status);
void ks_polygon_get_bounding_box(const ks_polygon *polygon, double *min_x,
                                 double *min_y, double *max_x, double *max_y,
                                 ks_status *status);
void ks_polygon_area(const ks_polygon *polygon, double *result,
                     ks_status *status);
void ks_polygon_perimeter(const ks_polygon *polygon, double *result,
                          ks_status *status);
void ks_polygon_map(const ks_polygon *polygon,
                    const ks_transform_2d_linear *transform,
                    ks_polygon **result, ks_status *status);

/* CogCircularAnnulusSection. map: similarities only (possibly
   reflecting), KS_FAILURE_BAD_PARAMETER otherwise. */
void ks_circular_annulus_section_set_center_radius_angle_start_angle_span_radial_scale(
    double center_x, double center_y, double radius, double angle_start,
    double angle_span, double radial_scale,
    ks_circular_annulus_section *result, ks_status *status);
void ks_circular_annulus_section_contains_point(
    const ks_circular_annulus_section *section, double x, double y,
    int32_t *result, ks_status *status);
void ks_circular_annulus_section_boundary_slack(
    const ks_circular_annulus_section *section, double *result,
    ks_status *status);
void ks_circular_annulus_section_get_bounding_box(
    const ks_circular_annulus_section *section, double *min_x,
    double *min_y, double *max_x, double *max_y, ks_status *status);
void ks_circular_annulus_section_area(
    const ks_circular_annulus_section *section, double *result,
    ks_status *status);
void ks_circular_annulus_section_map(
    const ks_circular_annulus_section *section,
    const ks_transform_2d_linear *transform,
    ks_circular_annulus_section *result, ks_status *status);

/* CogLine. set_distance_rotation: (x, y) = distance * (-sin rotation,
   cos rotation); get_distance_rotation: distance = y cos rotation -
   x sin rotation. map: KS_FAILURE_TRANSFORM_SINGULAR when the direction
   maps to zero. */
void ks_line_set_xy_rotation(double x, double y, double rotation,
                             ks_line *result, ks_status *status);
void ks_line_set_from_start_xy_end_xy(double start_x, double start_y,
                                      double end_x, double end_y,
                                      ks_line *result, ks_status *status);
void ks_line_set_from_line_segment(const ks_line_segment *segment,
                                   ks_line *result, ks_status *status);
void ks_line_set_distance_rotation(double distance, double rotation,
                                   ks_line *result, ks_status *status);
void ks_line_get_distance_rotation(const ks_line *line, double *distance,
                                   double *rotation, ks_status *status);
void ks_line_map(const ks_line *line, const ks_transform_2d_linear *transform,
                 ks_line *result, ks_status *status);

/* CogLineSegment. */
void ks_line_segment_set_start_end(double start_x, double start_y,
                                   double end_x, double end_y,
                                   ks_line_segment *result,
                                   ks_status *status);
void ks_line_segment_set_start_length_rotation(double start_x,
                                               double start_y, double length,
                                               double rotation,
                                               ks_line_segment *result,
                                               ks_status *status);
void ks_line_segment_get_start_length_rotation(
    const ks_line_segment *segment, double *start_x, double *start_y,
    double *length, double *rotation, ks_status *status);
void ks_line_segment_get_midpoint(const ks_line_segment *segment, double *x,
                                  double *y, ks_status *status);
void ks_line_segment_map(const ks_line_segment *segment,
                         const ks_transform_2d_linear *transform,
                         ks_line_segment *result, ks_status *status);

/* CogPointMarker. */
void ks_point_marker_set_xy_rotation(double x, double y, double rotation,
                                     ks_point_marker *result,
                                     ks_status *status);
void ks_point_marker_map(const ks_point_marker *marker,
                         const ks_transform_2d_linear *transform,
                         ks_point_marker *result, ks_status *status);

/* CogCircularArc. map: similarities only, as for the annulus section. */
void ks_circular_arc_set_center_radius_angle_start_angle_span(
    double center_x, double center_y, double radius, double angle_start,
    double angle_span, ks_circular_arc *result, ks_status *status);
void ks_circular_arc_get_start_end(const ks_circular_arc *arc,
                                   double *start_x, double *start_y,
                                   double *end_x, double *end_y,
                                   ks_status *status);
void ks_circular_arc_map(const ks_circular_arc *arc,
                         const ks_transform_2d_linear *transform,
                         ks_circular_arc *result, ks_status *status);

/* ------------------------------------------------------------------ */
/* Pixel regions (AMV.Regions: the pixels of an image a region covers) */
/* ------------------------------------------------------------------ */

/* A pixel region: an opaque handle; NULL is the empty region. It holds
   the smallest bounding rectangle x_min .. x_min + width - 1 by
   y_min .. y_min + height - 1 around its pixels (pixel coordinates) and
   their number. whole_image, rasterize_*, restrict_to_mask and duplicate
   return new handles (NULL for the empty region); destroy frees one and sets
   *region to NULL. A failed call returns NULL. The meaning of every
   operation is documented in src/amv-regions.ads and
   src/amv-kernels-regions.ads.

   rasterize_<type> takes the size of the image, the transform from the
   region's selected space to pixel space (ks_image_get_transform with
   "#" as the target) and the region. Pixel (x, y) is included when its
   centre, mapped by the inverse of pixel_from_region, lies within
   +/-KS_SHAPE_MAX_VALUE and ks_<type>_contains_point accepts it; only
   the pixels near the region's bounding box are tested. Failures, in
   this order: KS_FAILURE_IMAGE_NO_PIXELS for a 0 x 0 image,
   KS_FAILURE_BAD_PARAMETER for any other size that is not at least 1 x 1
   with at most KS_PIXEL_REGION_MAX_PIXELS pixels or for a transform
   outside the bounds of ks_transform_2d_linear_*,
   KS_FAILURE_TRANSFORM_SINGULAR when the transform has no inverse within
   them, KS_FAILURE_BAD_PARAMETER for a region that is not valid or whose
   bounding box leaves the bounds of the shapes, KS_FAILURE_OUT_OF_MEMORY.

   restrict_to_mask returns a new region with the pixels of region that
   the 8-bit image mask does not mark "don't care". The mask is laid over
   the pixels at an offset: mask pixel (u, v) lies over pixel
   (u + offset_x, v + offset_y). A mask pixel of value 0 marks the pixel
   under it "don't care"; a pixel under a mask pixel of any other value,
   and every pixel that no mask pixel lies over, is kept. A NULL mask lies
   over no pixel (the result then holds every pixel of region); a NULL
   region gives NULL, as does a result without pixels. The result has the
   smallest bounding rectangle around its pixels. Failures, in this order:
   KS_FAILURE_BAD_PARAMETER for a region or mask handle that is not
   consistent, KS_FAILURE_OUT_OF_MEMORY. The tools that take an input
   image mask (the histogram tool) are run on the restricted region: pass
   the result of this function as their region.

   contains returns 1 when pixel (x, y) belongs to the region and 0
   otherwise (also for NULL); it takes constant time and has no status. */

#define KS_PIXEL_REGION_MAX_PIXELS 2147483647

typedef struct ks_pixel_region ks_pixel_region; /* opaque */

void ks_pixel_region_whole_image(int32_t image_width, int32_t image_height,
                                 ks_pixel_region **region,
                                 ks_status *status);
void ks_pixel_region_destroy(ks_pixel_region **region, ks_status *status);
void ks_pixel_region_duplicate(const ks_pixel_region *region,
                               ks_pixel_region **result, ks_status *status);
/* A new region of every pixel of region's bounding rectangle (NULL for the
   empty region). */
void ks_pixel_region_bounding_box(const ks_pixel_region *region,
                                  ks_pixel_region **result,
                                  ks_status *status);
void ks_pixel_region_is_empty(const ks_pixel_region *region, int32_t *result,
                              ks_status *status);
void ks_pixel_region_pixel_count(const ks_pixel_region *region,
                                 int32_t *result, ks_status *status);
void ks_pixel_region_bounds(const ks_pixel_region *region, int32_t *x_min,
                            int32_t *y_min, int32_t *width, int32_t *height,
                            ks_status *status);
int32_t ks_pixel_region_contains(const ks_pixel_region *region, int32_t x,
                                 int32_t y);
void ks_pixel_region_rasterize_rectangle(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_rectangle *rectangle, ks_pixel_region **region,
    ks_status *status);
void ks_pixel_region_rasterize_rectangle_affine(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_rectangle_affine *rectangle, ks_pixel_region **region,
    ks_status *status);
void ks_pixel_region_rasterize_circle(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_circle *circle, ks_pixel_region **region, ks_status *status);
void ks_pixel_region_rasterize_ellipse(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_ellipse *ellipse, ks_pixel_region **region, ks_status *status);
void ks_pixel_region_rasterize_polygon(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_polygon *polygon, ks_pixel_region **region, ks_status *status);
void ks_pixel_region_rasterize_circular_annulus_section(
    int32_t image_width, int32_t image_height,
    const ks_transform_2d_linear *pixel_from_region,
    const ks_circular_annulus_section *section, ks_pixel_region **region,
    ks_status *status);
void ks_pixel_region_restrict_to_mask(const ks_pixel_region *region,
                                      const ks_image_8_grey *mask,
                                      int32_t offset_x, int32_t offset_y,
                                      ks_pixel_region **result,
                                      ks_status *status);

/* ------------------------------------------------------------------ */
/* Real images (AMV.Image_Math; no VisionPro counterpart)              */
/* ------------------------------------------------------------------ */

/* A floating point image behind an opaque handle that *_create (or any
   function returning an image) gives and ks_real_image_destroy frees (and
   sets to NULL). A handle holds width x height values (each at least 0,
   width * height at most KS_REAL_IMAGE_MAX_PIXELS); pixel (x, y) is
   column x, row y, 0-based, its centre at (x, y). An image whose width or
   height is 0 is empty (it keeps its size but holds no pixels); NULL is
   the empty image of size 0 x 0. The library never shares the values of
   two handles, and every function returning an image returns a new one.

   Every value lies within +/-KS_REAL_IMAGE_MAX_VALUE: create, set_pixel
   and fill fail with KS_FAILURE_BAD_PARAMETER for a value that is not
   finite or not within it, and every value a function computes is clamped
   to it (only rounding at the very edge of the bound can reach the
   clamp). Coordinates and sigma must be finite, a transform within
   +/-KS_TRANSFORM_MAX_VALUE. get_pixel and set_pixel fail with
   KS_FAILURE_INDEX_OUT_OF_RANGE outside the image (always for an empty
   one). The filters return an empty image of the same size for an empty
   one (NULL for NULL); bilinear, resample, to_8_grey and statistics fail
   with KS_FAILURE_BAD_PARAMETER for an empty image ("Bilinear: the image
   is empty"), the 8-bit variants with KS_FAILURE_IMAGE_NO_PIXELS for a
   NULL 8-bit image. The functions returning a new image set it to NULL
   when they fail. */

#define KS_REAL_IMAGE_MAX_VALUE  1.0e100
#define KS_REAL_IMAGE_MAX_PIXELS 2147483647
#define KS_REAL_IMAGE_MAX_SIGMA  1.0e6

typedef struct ks_real_image ks_real_image; /* opaque */

void ks_real_image_create(int32_t width, int32_t height, double value,
                          ks_real_image **image, ks_status *status);
void ks_real_image_destroy(ks_real_image **image, ks_status *status);
void ks_real_image_width(const ks_real_image *image, int32_t *result,
                         ks_status *status);
void ks_real_image_height(const ks_real_image *image, int32_t *result,
                          ks_status *status);
void ks_real_image_get_pixel(const ks_real_image *image, int32_t x,
                             int32_t y, double *value, ks_status *status);
void ks_real_image_set_pixel(ks_real_image *image, int32_t x, int32_t y,
                             double value, ks_status *status);
void ks_real_image_fill(ks_real_image *image, double value,
                        ks_status *status);
void ks_real_image_duplicate(const ks_real_image *image,
                             ks_real_image **result, ks_status *status);

/* The whole 8-bit image, or the window of width x height pixels at
   (x_min, y_min), which must be non-empty and lie inside the image. */
void ks_real_image_from_8_grey(const ks_image_8_grey *image,
                               ks_real_image **result, ks_status *status);
void ks_real_image_from_8_grey_window(const ks_image_8_grey *image,
                                      int32_t x_min, int32_t y_min,
                                      int32_t width, int32_t height,
                                      ks_real_image **result,
                                      ks_status *status);
/* Every value rounded to the nearest integer (halves away from zero) and
   clamped to 0 .. 255. */
void ks_real_image_to_8_grey(const ks_real_image *image,
                             ks_image_8_grey **result, ks_status *status);

/* Bilinear interpolation between pixel centres, coordinates outside the
   image clamped to its border. */
void ks_real_image_bilinear(const ks_real_image *image, double x, double y,
                            double *result, ks_status *status);
void ks_real_image_bilinear_8_grey(const ks_image_8_grey *image, double x,
                                   double y, double *result,
                                   ks_status *status);
/* 1 when (x, y) lies in [0, width - 1] x [0, height - 1], otherwise 0. */
void ks_real_image_is_inside(const ks_real_image *image, double x, double y,
                             int32_t *result, ks_status *status);
/* A width x height image whose pixel (i, j) is the bilinear sample at
   pixel_from_output mapping (i, j). */
void ks_real_image_resample(const ks_real_image *image,
                            const ks_transform_2d_linear *pixel_from_output,
                            int32_t width, int32_t height,
                            ks_real_image **result, ks_status *status);
void ks_real_image_resample_8_grey(
    const ks_image_8_grey *image,
    const ks_transform_2d_linear *pixel_from_output, int32_t width,
    int32_t height, ks_real_image **result, ks_status *status);

/* Separable Gaussian filter, radius ceil(3 sigma), borders replicated;
   sigma <= 0 gives a copy, sigma above KS_REAL_IMAGE_MAX_SIGMA fails. */
void ks_real_image_gaussian_smooth(const ks_real_image *image, double sigma,
                                   ks_real_image **result,
                                   ks_status *status);
/* Mean over a (2 half_size + 1) square window, borders replicated;
   half_size 0 gives a copy, a negative one fails. */
void ks_real_image_box_smooth(const ks_real_image *image, int32_t half_size,
                              ks_real_image **result, ks_status *status);
/* 3 x 3 Sobel derivatives normalised by 1/8, borders replicated: gx is
   d/dx (to the right), gy d/dy (downwards). */
void ks_real_image_sobel(const ks_real_image *image, ks_real_image **gx,
                         ks_real_image **gy, ks_status *status);
/* Halves both dimensions (rounding down, at least 1) by averaging 2 x 2
   blocks. */
void ks_real_image_downsample_2(const ks_real_image *image,
                                ks_real_image **result, ks_status *status);
/* Population statistics; the mean lies within [minimum, maximum] and the
   standard deviation within [0, maximum - minimum]. */
void ks_real_image_statistics(const ks_real_image *image, double *mean,
                              double *std_dev, double *minimum,
                              double *maximum, ks_status *status);

/* ------------------------------------------------------------------ */
/* Geometry (AMV.Geometry; no VisionPro counterpart)                   */
/* ------------------------------------------------------------------ */

/* Every coordinate and radius must be finite and within
   +/-KS_GEOMETRY_MAX_COORDINATE, every rotation finite; a coordinate,
   length or radius a function would return beyond that bound fails too
   ("Distance: the result would exceed +/-1.0E150"). Failures are
   KS_FAILURE_BAD_PARAMETER with the messages of AMV.Geometry ("Fit_Line:
   the points coincide"); the results are then 0. The fits take count
   points (count in 0 .. KS_GEOMETRY_MAX_POINTS, points not NULL when count
   is positive); the robust fits set used[i] to 1 when point i takes part
   in the final fit (0 otherwise, and all 0 when the fit fails). */

#define KS_GEOMETRY_MAX_COORDINATE 1.0e150
#define KS_GEOMETRY_MAX_POINTS     2147483647

typedef struct {
    double x, y;
} ks_point_2d;

typedef struct {
    double x, y;     /* a point on the line */
    double rotation; /* its direction: (cos rotation, sin rotation) */
} ks_line_2d;

typedef struct {
    double center_x, center_y;
    double radius;
} ks_circle_2d;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(ks_point_2d) == 16, "ks_point_2d must be 16 bytes");
_Static_assert(sizeof(ks_line_2d) == 24, "ks_line_2d must be 24 bytes");
_Static_assert(offsetof(ks_line_2d, rotation) == 16,
               "ks_line_2d.rotation offset");
_Static_assert(sizeof(ks_circle_2d) == 24, "ks_circle_2d must be 24 bytes");
_Static_assert(offsetof(ks_circle_2d, radius) == 16,
               "ks_circle_2d.radius offset");
#endif

void ks_geometry_distance(const ks_point_2d *p, const ks_point_2d *q,
                          double *result, ks_status *status);
/* Positive when p lies on the side of the left normal (-sin, cos). */
void ks_geometry_signed_distance(const ks_point_2d *p,
                                 const ks_line_2d *line, double *result,
                                 ks_status *status);
void ks_geometry_distance_to_line(const ks_point_2d *p,
                                  const ks_line_2d *line, double *result,
                                  ks_status *status);
/* The foot of the perpendicular from p, and its signed position along the
   line from (line.x, line.y). */
void ks_geometry_project(const ks_point_2d *p, const ks_line_2d *line,
                         ks_point_2d *result, ks_status *status);
void ks_geometry_position_along(const ks_point_2d *p,
                                const ks_line_2d *line, double *result,
                                ks_status *status);
/* |(|p - centre| - radius)|. */
void ks_geometry_distance_to_circle(const ks_point_2d *p,
                                    const ks_circle_2d *circle,
                                    double *result, ks_status *status);
/* *parallel is 1 (and *point (0, 0)) when |sin| of the angle between the
   lines is at most 1e-12. */
void ks_geometry_intersect_lines(const ks_line_2d *line_1,
                                 const ks_line_2d *line_2,
                                 ks_point_2d *point, int32_t *parallel,
                                 ks_status *status);
/* *count = 0, 1 (tangent; both points equal) or 2; a negative radius
   fails. */
void ks_geometry_intersect_line_circle(const ks_line_2d *line,
                                       const ks_circle_2d *circle,
                                       ks_point_2d *point_1,
                                       ks_point_2d *point_2, int32_t *count,
                                       ks_status *status);
void ks_geometry_intersect_circles(const ks_circle_2d *circle_1,
                                   const ks_circle_2d *circle_2,
                                   ks_point_2d *point_1, ks_point_2d *point_2,
                                   int32_t *count, ks_status *status);
/* line_2.rotation - line_1.rotation reduced to (-pi, pi]. */
void ks_geometry_angle_between(const ks_line_2d *line_1,
                               const ks_line_2d *line_2, double *result,
                               ks_status *status);
/* Orthogonal least squares line through the centroid, rotation in
   (-pi/2, pi/2]. */
void ks_geometry_fit_line(const ks_point_2d *points, int32_t count,
                          ks_line_2d *line, double *rms_error,
                          ks_status *status);
void ks_geometry_fit_line_robust(const ks_point_2d *points, int32_t count,
                                 int32_t num_to_ignore, ks_line_2d *line,
                                 double *rms_error, int32_t *used,
                                 ks_status *status);
/* Geometric least squares circle. */
void ks_geometry_fit_circle(const ks_point_2d *points, int32_t count,
                            ks_circle_2d *circle, double *rms_error,
                            ks_status *status);
void ks_geometry_fit_circle_robust(const ks_point_2d *points, int32_t count,
                                   int32_t num_to_ignore,
                                   ks_circle_2d *circle, double *rms_error,
                                   int32_t *used, ks_status *status);

#ifdef __cplusplus
}
#endif

/* ------------------------------------------------------------------ */
/* Tools: one header per tool (include/amv_<tool>.h, with its own     */
/* extern "C" block) for the entry points of AMV.Kernels.<Tool>        */
/* ------------------------------------------------------------------ */

#include "amv_image_processing.h"
#include "amv_blob.h"
#include "amv_caliper.h"
#include "amv_ip_one_image.h"
#include "amv_ip_geometry.h"
#include "amv_dimensioning.h"
#include "amv_create_shapes.h"
#include "amv_calib_fix.h"
#include "amv_cnl_search.h"
#include "amv_pm_align.h"
#include "amv_tool_group.h"

#endif /* AMV_H */
