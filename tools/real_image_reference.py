#!/usr/bin/env python3
"""Reference measurements for annotating VisA images, independent of AMV.

Plain Python (standard library only), written separately from AMV's
kernels, so that errors in AMV do not leak into the ground truth.

  real_image_reference.py circle IMAGE.bmp CX CY R BAND [N]
      Refines a circle given roughly by hand: N rays (default 90) from
      (CX, CY); along each, between R - BAND and R + BAND, the edge is the
      peak of the grey-level derivative (either sign, the stronger one
      along most rays), refined by a parabola. A geometric least-squares
      circle is fitted to the edge points; points farther than 3 robust
      sigmas (at least 1 px) are dropped and the fit repeated.
      Prints: cx cy r rms used total

  real_image_reference.py line IMAGE.bmp X0 Y0 X1 Y1 BAND [inward=+1|-1]
      Refines a straight edge given roughly by two points: 60 profiles
      across it, each the peak derivative within +/- BAND, then a total
      least squares line (outliers beyond 3 robust sigmas, at least
      0.75 px, dropped). With inward=+1 (-1) the side +n (-n) is the
      inside (n the segment's direction turned by +90 degrees, as
      (-uy, ux)) and each profile takes the outermost edge whose grey
      level rises towards the inside (the first, from the outside, that
      reaches 0.4 of the profile's strongest, on profiles averaged over
      5 px along the edge); otherwise the strongest
      edge, of the polarity of most profiles. Prints: px py angle_deg rms
      used total

  real_image_reference.py circle_best IMAGE.bmp CX CY R SPREAD
      As circle (band 4, then 3), started from a 5 x 5 grid of centres
      within +/- SPREAD of (CX, CY); keeps the fit with the smallest RMS
      whose radius is within 10 % of R (a rough centre that is several
      pixels off otherwise lets part of the rays find the pad's outer
      edge). Prints: cx cy r rms used total

  real_image_reference.py circle_outer IMAGE.bmp CX CY R BAND [N]
      The outer edge of a light disc on a darker background: N rays
      (default 120) from (CX, CY); along each, between R - BAND and
      R + BAND, the outermost edge whose grey level rises towards the
      centre (the first, scanning from the outside, whose derivative
      reaches 0.4 of the profile's strongest, on profiles averaged over
      5 px across the ray), refined by a parabola; then a geometric
      least-squares circle with the outliers dropped as above. The rays
      start again from that circle's centre, twice. Prints: cx cy r rms
      used total

  real_image_reference.py chord IMAGE.bmp CX CY HALF_BAND LO HI
      The width across a dark disc along x through (CX, CY), averaged over
      the rows within +/- HALF_BAND. Prints: left_x right_x width

Pixel centres are at integer coordinates (as in AMV).
"""

import math
import struct
import sys


def read_bmp(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"BM":
        raise SystemExit("not a BMP: " + path)
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    top_down = height < 0
    height = abs(height)
    if bpp not in (24, 32):
        raise SystemExit("unsupported BMP depth %d" % bpp)
    step = bpp // 8
    row = (width * step + 3) & ~3
    grey = [0.0] * (width * height)
    for y in range(height):
        src_y = y if top_down else height - 1 - y
        base = offset + src_y * row
        for x in range(width):
            b, g, r = data[base + x * step: base + x * step + 3]
            grey[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
    return width, height, grey


class Image:
    def __init__(self, path):
        self.w, self.h, self.p = read_bmp(path)

    def at(self, x, y):
        """Bilinear sample at (x, y); None outside."""
        if x < 0 or y < 0 or x > self.w - 1 or y > self.h - 1:
            return None
        x0, y0 = int(math.floor(x)), int(math.floor(y))
        x1, y1 = min(x0 + 1, self.w - 1), min(y0 + 1, self.h - 1)
        fx, fy = x - x0, y - y0
        p = self.p
        w = self.w
        a = p[y0 * w + x0] * (1 - fx) + p[y0 * w + x1] * fx
        b = p[y1 * w + x0] * (1 - fx) + p[y1 * w + x1] * fx
        return a * (1 - fy) + b * fy


def edge_along(img, cx, cy, ux, uy, t0, t1, step=0.25):
    """Positions t in [t0, t1] (along the unit direction u from (cx, cy))
    of the peak derivative, for each sign: (t_pos, d_pos, t_neg, d_neg)."""
    ts = []
    vs = []
    t = t0
    while t <= t1 + 1e-9:
        v = img.at(cx + ux * t, cy + uy * t)
        if v is None:
            return None
        ts.append(t)
        vs.append(v)
        t += step
    # smoothing [1 2 1]/4, then derivative over +/- 0.5 px
    sm = [vs[0]] + [(vs[i - 1] + 2 * vs[i] + vs[i + 1]) / 4
                    for i in range(1, len(vs) - 1)] + [vs[-1]]
    k = int(round(0.5 / step))
    der = [None] * len(sm)
    for i in range(k, len(sm) - k):
        der[i] = (sm[i + k] - sm[i - k]) / (2 * k * step)
    best = {}
    for sign in (1, -1):
        bi = None
        for i in range(k + 1, len(sm) - k - 1):
            if der[i] is None:
                continue
            if bi is None or sign * der[i] > sign * der[bi]:
                bi = i
        if bi is None:
            return None
        d0, d1, d2 = der[bi - 1], der[bi], der[bi + 1]
        denom = d0 - 2 * d1 + d2
        off = 0.0 if denom == 0 else 0.5 * (d0 - d2) / denom
        off = max(-1.0, min(1.0, off))
        best[sign] = (ts[bi] + off * step, sign * d1)
    return best


def fit_circle(pts):
    # Kasa algebraic fit, then Gauss-Newton on geometric distances.
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    suu = svv = suv = suuu = svvv = suvv = svuu = 0.0
    for x, y in pts:
        u, v = x - mx, y - my
        suu += u * u
        svv += v * v
        suv += u * v
        suuu += u * u * u
        svvv += v * v * v
        suvv += u * v * v
        svuu += v * u * u
    det = suu * svv - suv * suv
    uc = (0.5 * (suuu + suvv) * svv - 0.5 * (svvv + svuu) * suv) / det
    vc = (0.5 * (svvv + svuu) * suu - 0.5 * (suuu + suvv) * suv) / det
    cx, cy = uc + mx, vc + my
    r = math.sqrt(uc * uc + vc * vc + (suu + svv) / n)
    for _ in range(50):
        # J^T J and J^T e for parameters (cx, cy, r)
        a = [[0.0] * 3 for _ in range(3)]
        g = [0.0] * 3
        for x, y in pts:
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            if d == 0:
                continue
            e = d - r
            j = (-dx / d, -dy / d, -1.0)
            for i in range(3):
                g[i] += j[i] * e
                for k in range(3):
                    a[i][k] += j[i] * j[k]
        delta = solve3(a, [-v for v in g])
        cx += delta[0]
        cy += delta[1]
        r += delta[2]
        if max(abs(v) for v in delta) < 1e-9:
            break
    res = [math.hypot(x - cx, y - cy) - r for x, y in pts]
    rms = math.sqrt(sum(e * e for e in res) / n)
    return cx, cy, r, rms, res


def solve3(a, b):
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(3):
        p = max(range(c, 3), key=lambda i: abs(m[i][c]))
        m[c], m[p] = m[p], m[c]
        for i in range(c + 1, 3):
            f = m[i][c] / m[c][c]
            for k in range(c, 4):
                m[i][k] -= f * m[c][k]
    x = [0.0] * 3
    for c in (2, 1, 0):
        x[c] = (m[c][3] - sum(m[c][k] * x[k] for k in range(c + 1, 3))) / m[c][c]
    return x


def refine_circle(img, cx, cy, r, band, n=90):
    found = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ux, uy = math.cos(a), math.sin(a)
        e = edge_along(img, cx, cy, ux, uy, max(1.0, r - band), r + band)
        if e is not None:
            found.append((ux, uy, e))
    # the polarity of most rays
    pos = sum(1 for f in found if f[2][1][1] >= f[2][-1][1])
    sign = 1 if pos * 2 >= len(found) else -1
    pts = [(cx + ux * e[sign][0], cy + uy * e[sign][0]) for ux, uy, e in found]
    total = len(pts)
    for _ in range(3):
        fx, fy, fr, rms, res = fit_circle(pts)
        med = sorted(abs(v) for v in res)[len(res) // 2]
        limit = max(1.0, 3 * 1.4826 * med)
        keep = [p for p, e in zip(pts, res) if abs(e) <= limit]
        if len(keep) == len(pts):
            break
        pts = keep
    fx, fy, fr, rms, res = fit_circle(pts)
    return fx, fy, fr, rms, len(pts), total, sign, pts


def edge_outermost(img, cx, cy, nx, ny, band, inward, step=0.25, fraction=0.4,
                   ux=0.0, uy=0.0, half_width=2):
    """Along the profile through (cx, cy) in direction (nx, ny), from -band
    to +band: the outermost edge whose grey level rises towards the inside
    (+n when inward > 0, -n otherwise), i.e. the first local maximum of
    that derivative, scanning from the outside, that reaches `fraction` of
    the largest one. Returns its position t (sub-pixel) or None."""
    ts, vs = [], []
    t = -band
    while t <= band + 1e-9:
        acc = 0.0
        for j in range(-half_width, half_width + 1):
            v = img.at(cx + nx * t + ux * j, cy + ny * t + uy * j)
            if v is None:
                return None
            acc += v
        ts.append(t); vs.append(acc / (2 * half_width + 1))
        t += step
    sm = [vs[0]] + [(vs[i-1] + 2*vs[i] + vs[i+1]) / 4 for i in range(1, len(vs)-1)] + [vs[-1]]
    k = int(round(0.5 / step))
    sgn = 1 if inward > 0 else -1
    der = [None] * len(sm)
    for i in range(k, len(sm) - k):
        der[i] = sgn * (sm[i + k] - sm[i - k]) / (2 * k * step)
    valid = [i for i in range(k + 1, len(sm) - k - 1)]
    top = max(der[i] for i in valid)
    if top <= 0:
        return None
    order = valid if inward > 0 else list(reversed(valid))
    for i in order:
        d = der[i]
        if d >= fraction * top and d >= der[i-1] and d >= der[i+1]:
            d0, d1, d2 = der[i-1], der[i], der[i+1]
            den = d0 - 2*d1 + d2
            off = 0.0 if den == 0 else 0.5 * (d0 - d2) / den
            return ts[i] + max(-1.0, min(1.0, off)) * step
    return None


def refine_line(img, x0, y0, x1, y1, band, n=60, inward=0):
    """Edge points on profiles across the segment (x0,y0)-(x1,y1), each
    the peak derivative within +/- band, then a total least squares
    line with outlier rejection. Returns (px, py, angle_deg, rms, used,
    total, points): a point on the line and its direction in degrees."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux
    found = []
    if inward != 0:
        pts = []
        for i in range(n):
            t = (i + 0.5) / n
            cx, cy = x0 + dx * t, y0 + dy * t
            e = edge_outermost(img, cx, cy, nx, ny, band, inward, ux=ux, uy=uy)
            if e is not None:
                pts.append((cx + nx * e, cy + ny * e))
        total = len(pts)
        return fit_line_points(pts, total)
    for i in range(n):
        t = (i + 0.5) / n
        cx, cy = x0 + dx * t, y0 + dy * t
        e = edge_along(img, cx, cy, nx, ny, -band, band)
        if e is not None:
            found.append((cx, cy, e))
    if inward == 0:
        pos = sum(1 for f in found if f[2][1][1] >= f[2][-1][1])
        sign = 1 if pos * 2 >= len(found) else -1
    else:
        # The edge whose grey level rises towards the inside: with the
        # inside on the +n side that is a rising edge along n, otherwise a
        # falling one.
        sign = 1 if inward > 0 else -1
    pts = [(cx + nx * e[sign][0], cy + ny * e[sign][0]) for cx, cy, e in found]
    total = len(pts)
    return fit_line_points(pts, total)


def fit_line_points(pts, total):
    def tls(points):
        m = len(points)
        mx = sum(p[0] for p in points) / m
        my = sum(p[1] for p in points) / m
        sxx = sum((p[0] - mx) ** 2 for p in points)
        syy = sum((p[1] - my) ** 2 for p in points)
        sxy = sum((p[0] - mx) * (p[1] - my) for p in points)
        a = 0.5 * math.atan2(2 * sxy, sxx - syy)
        res = [-(p[0] - mx) * math.sin(a) + (p[1] - my) * math.cos(a) for p in points]
        return mx, my, a, res
    for _ in range(3):
        mx, my, a, res = tls(pts)
        med = sorted(abs(v) for v in res)[len(res) // 2]
        limit = max(0.75, 3 * 1.4826 * med)
        keep = [p for p, r in zip(pts, res) if abs(r) <= limit]
        if len(keep) == len(pts):
            break
        pts = keep
    mx, my, a, res = tls(pts)
    rms = math.sqrt(sum(r * r for r in res) / len(res))
    return mx, my, math.degrees(a), rms, len(pts), total, pts


def refine_circle_outer(img, cx, cy, r, band, n=120):
    """The outer edge of a light disc (see circle_outer above)."""
    for _ in range(3):
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            ux, uy = math.cos(a), math.sin(a)
            px, py = cx + ux * r, cy + uy * r
            e = edge_outermost(img, px, py, ux, uy, band, -1,
                               ux=-uy, uy=ux)
            if e is not None:
                pts.append((px + ux * e, py + uy * e))
        total = len(pts)
        for _ in range(3):
            fx, fy, fr, rms, res = fit_circle(pts)
            med = sorted(abs(v) for v in res)[len(res) // 2]
            limit = max(1.0, 3 * 1.4826 * med)
            keep = [p for p, e in zip(pts, res) if abs(e) <= limit]
            if len(keep) == len(pts):
                break
            pts = keep
        fx, fy, fr, rms, res = fit_circle(pts)
        cx, cy, r = fx, fy, fr
    return fx, fy, fr, rms, len(pts), total, pts


def chord(img, cx, cy, half_band, reach_lo, reach_hi):
    """The width across a dark disc along x through (cx, cy): on each row
    cy - half_band .. cy + half_band (step 0.5), the dark-to-light edge
    (rising) found from the centre outwards to the left and to the right
    between reach_lo and reach_hi, the positions averaged over the rows.
    Returns (left_x, right_x, width)."""
    lefts, rights = [], []
    y = cy - half_band
    while y <= cy + half_band + 1e-9:
        r = edge_along(img, cx, y, 1.0, 0.0, reach_lo, reach_hi)
        l = edge_along(img, cx, y, -1.0, 0.0, reach_lo, reach_hi)
        if r is not None and l is not None:
            rights.append(cx + r[1][0])
            lefts.append(cx - l[1][0])
        y += 0.5
    lx = sum(lefts) / len(lefts)
    rx = sum(rights) / len(rights)
    return lx, rx, rx - lx


def main():
    if len(sys.argv) >= 7 and sys.argv[1] == "circle":
        img = Image(sys.argv[2])
        cx, cy, r, band = map(float, sys.argv[3:7])
        n = int(sys.argv[7]) if len(sys.argv) > 7 else 90
        fx, fy, fr, rms, used, total, sign, pts = refine_circle(
            img, cx, cy, r, band, n)
        print("%.3f %.3f %.3f %.3f %d %d %s" % (
            fx, fy, fr, rms, used, total, "rising" if sign > 0 else "falling"))
        if "points" in sys.argv[8:]:
            for x, y in pts:
                print("%.2f %.2f" % (x, y))
    elif len(sys.argv) >= 8 and sys.argv[1] == "line":
        img = Image(sys.argv[2])
        x0, y0, x1, y1, band = map(float, sys.argv[3:8])
        inward = 0
        for a in sys.argv[8:]:
            if a.startswith("inward="):
                inward = int(a.split("=")[1])
        mx, my, ang, rms, used, total, pts = refine_line(img, x0, y0, x1, y1, band, inward=inward)
        print("%.3f %.3f %.4f %.3f %d %d" % (mx, my, ang, rms, used, total))
        if "points" in sys.argv[8:]:
            for x, y in pts:
                print("%.2f %.2f" % (x, y))
    elif len(sys.argv) >= 7 and sys.argv[1] == "circle_best":
        img = Image(sys.argv[2])
        cx, cy, r, spread = map(float, sys.argv[3:7])
        best = None
        for i in range(5):
            for j in range(5):
                sx = cx + spread * (i - 2) / 2.0
                sy = cy + spread * (j - 2) / 2.0
                a = refine_circle(img, sx, sy, r, 4, 48)
                b = refine_circle(img, a[0], a[1], r, 3, 72)
                if abs(b[2] - r) <= 0.1 * r and (best is None or b[3] < best[3]):
                    best = b
        fx, fy, fr, rms, used, total = best[:6]
        print("%.3f %.3f %.3f %.3f %d %d" % (fx, fy, fr, rms, used, total))
    elif len(sys.argv) >= 7 and sys.argv[1] == "circle_outer":
        img = Image(sys.argv[2])
        cx, cy, r, band = map(float, sys.argv[3:7])
        n = int(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7].isdigit() else 120
        fx, fy, fr, rms, used, total, pts = refine_circle_outer(
            img, cx, cy, r, band, n)
        print("%.3f %.3f %.3f %.3f %d %d" % (fx, fy, fr, rms, used, total))
        if "points" in sys.argv[7:]:
            for x, y in pts:
                print("%.2f %.2f" % (x, y))
    elif len(sys.argv) >= 8 and sys.argv[1] == "chord":
        img = Image(sys.argv[2])
        cx, cy, hb, lo, hi = map(float, sys.argv[3:8])
        lx, rx, w = chord(img, cx, cy, hb, lo, hi)
        print("%.3f %.3f %.3f" % (lx, rx, w))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
