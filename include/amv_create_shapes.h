/*
 * AdaMachineVision (AMV) C API: the shape creation tools of
 * Cognex.VisionPro.Dimensioning (CogCreateCircleTool, CogCreateEllipseTool,
 * CogCreateLineTool, CogCreateSegmentTool, CogCreateLineBisectPointsTool,
 * CogCreateLineParallelTool, CogCreateLinePerpendicularTool,
 * CogCreateSegmentAvgSegsTool). Included by amv.h; the entry points belong
 * to the SPARK kernel AMV.Kernels.Create_Shapes, whose spec describes every
 * construction and bound in full.
 *
 * Each tool creates one shape (the value of its VisionPro GetOutput*
 * method) and writes it to *result. Every shape is created in one space,
 * the "selected space" (the selected space of the tool's InputImage in the
 * Ada API): each input shape comes with the transform from its own space
 * into it (selected_from_<shape>; pass the identity when everything is in
 * one space) and is mapped first; plain coordinates are taken in the
 * selected space.
 *
 *   circle, ellipse, line, segment: the input shape mapped (a circle must
 *     stay a circle: its transform a similarity);
 *   line_bisect_points: the line through the midpoint of the two points,
 *     rotated by pi/2 from the direction start -> end (the points must
 *     differ);
 *   line_parallel: the line through (x, y) with the line's rotation;
 *   line_perpendicular: the line through (x, y) with the line's rotation
 *     plus pi/2;
 *   segment_avg_segs: from the midpoint of the start points to the
 *     midpoint of the end points (segments in opposite directions are not
 *     turned round).
 *
 * Every rotation returned lies in (-pi, pi]. Every coordinate taken, and
 * every coordinate and radius of a created shape, lies within 1.0e150
 * (KS_CREATE_SHAPES_MAX_VALUE), so a created shape is a valid input of
 * every other tool. Failures: KS_FAILURE_BAD_PARAMETER (a value that is
 * not finite or beyond the bound, a shape beyond it once mapped, an ellipse
 * radius of 0 before or after the mapping, a circle under a non-similarity,
 * equal points for the bisector), KS_FAILURE_TRANSFORM_SINGULAR (a line
 * whose direction maps to zero). A failed call writes the default value of
 * the shape struct, as the ks_<shape>_* entry points of amv.h do: circle
 * {0, 0, 50}, ellipse {0, 0, 50, 25, 0}, line {0, 0, 0}, segment
 * {0, 0, 100, 0}.
 */

#ifndef AMV_CREATE_SHAPES_H
#define AMV_CREATE_SHAPES_H

#include "amv.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KS_CREATE_SHAPES_MAX_VALUE 1.0e150

/* CogCreateCircleTool: InputCircle in the selected space. */
void ks_create_circle_execute(
    const ks_circle *input_circle,
    const ks_transform_2d_linear *selected_from_input_circle,
    ks_circle *result, ks_status *status);

/* CogCreateEllipseTool: Ellipse in the selected space. */
void ks_create_ellipse_execute(
    const ks_ellipse *ellipse,
    const ks_transform_2d_linear *selected_from_ellipse, ks_ellipse *result,
    ks_status *status);

/* CogCreateLineTool: Line in the selected space. */
void ks_create_line_execute(const ks_line *line,
                            const ks_transform_2d_linear *selected_from_line,
                            ks_line *result, ks_status *status);

/* CogCreateSegmentTool: Segment in the selected space. */
void ks_create_segment_execute(
    const ks_line_segment *segment,
    const ks_transform_2d_linear *selected_from_segment,
    ks_line_segment *result, ks_status *status);

/* CogCreateLineBisectPointsTool: the perpendicular bisector of
   (start_x, start_y) and (end_x, end_y). */
void ks_create_line_bisect_points_execute(double start_x, double start_y,
                                          double end_x, double end_y,
                                          ks_line *result, ks_status *status);

/* CogCreateLineParallelTool: the line through (x, y) parallel to line. */
void ks_create_line_parallel_execute(
    double x, double y, const ks_line *line,
    const ks_transform_2d_linear *selected_from_line, ks_line *result,
    ks_status *status);

/* CogCreateLinePerpendicularTool: the line through (x, y) perpendicular to
   line. */
void ks_create_line_perpendicular_execute(
    double x, double y, const ks_line *line,
    const ks_transform_2d_linear *selected_from_line, ks_line *result,
    ks_status *status);

/* CogCreateSegmentAvgSegsTool: the average of segment_a and segment_b. */
void ks_create_segment_avg_segs_execute(
    const ks_line_segment *segment_a, const ks_line_segment *segment_b,
    const ks_transform_2d_linear *selected_from_segment_a,
    const ks_transform_2d_linear *selected_from_segment_b,
    ks_line_segment *result, ks_status *status);

#ifdef __cplusplus
}
#endif

#endif /* AMV_CREATE_SHAPES_H */
