//! Software compositor: draws OverlayFrame data onto raw RGBA pixel buffers.
//! Used by the export pipeline to burn overlays into video frames.

use crate::calibration::Point2D;
use crate::overlay_geometry::types::OverlayFrame;

/// Software compositor that draws overlay geometry onto RGBA buffers.
pub struct Compositor;

impl Compositor {
    /// Composite an OverlayFrame onto an RGBA pixel buffer.
    /// The buffer must be width * height * 4 bytes (RGBA8).
    pub fn composite_frame(
        buffer: &mut [u8],
        width: u32,
        height: u32,
        frame: &OverlayFrame,
        background_dim: f32,
    ) {
        let w = width as usize;
        let h = height as usize;
        assert_eq!(buffer.len(), w * h * 4);

        // Apply background dimming
        if background_dim > 0.0 {
            let dim_factor = 1.0 - background_dim;
            let (pixels, _) = buffer.as_chunks_mut::<4>();
            for pixel in pixels {
                pixel[0] = (pixel[0] as f32 * dim_factor) as u8;
                pixel[1] = (pixel[1] as f32 * dim_factor) as u8;
                pixel[2] = (pixel[2] as f32 * dim_factor) as u8;
                // Alpha unchanged
            }
        }

        // Draw the darkened fall lane behind everything else
        if let Some(lane) = &frame.fall_lane_quad {
            if frame.lane_opacity > 0.0 {
                Self::fill_quad(
                    buffer,
                    width,
                    height,
                    lane,
                    [0.0, 0.0, 0.0, frame.lane_opacity],
                );
                // Subtle edge line along the keyboard, matching the preview painter.
                Self::draw_line(
                    buffer,
                    width,
                    height,
                    &lane[0],
                    &lane[1],
                    1.5,
                    [1.0, 1.0, 1.0, 0.15],
                );
            }
        }

        // Draw key highlights first (below strips)
        for highlight in &frame.key_highlights {
            Self::fill_quad(buffer, width, height, &highlight.quad, highlight.color);
        }

        // Draw strip glow layers
        for strip in &frame.strips {
            if strip.glow_radius > 0.0 && strip.glow_intensity > 0.0 {
                let mut glow_color = strip.color;
                glow_color[3] *= strip.glow_intensity * 0.4;
                // Draw slightly expanded quad for glow effect
                let expanded = Self::expand_quad(&strip.quad, strip.glow_radius as f64);
                Self::draw_quad(
                    buffer,
                    width,
                    height,
                    &expanded,
                    glow_color,
                    strip.corner_radius as f64 + strip.glow_radius as f64,
                    0.0,
                    [0.0; 4],
                );
            }
        }

        // Draw main strips
        for strip in &frame.strips {
            Self::draw_quad(
                buffer,
                width,
                height,
                &strip.quad,
                strip.color,
                strip.corner_radius as f64,
                strip.border_width as f64,
                strip.border_color,
            );
        }
    }

    /// Draw a hard-edged filled quad (no rounding, no outline).
    fn fill_quad(buffer: &mut [u8], width: u32, height: u32, quad: &[Point2D; 4], color: [f32; 4]) {
        Self::draw_quad(buffer, width, height, quad, color, 0.0, 0.0, [0.0; 4]);
    }

    /// Draw a straight line of the given thickness as a thin quad.
    fn draw_line(
        buffer: &mut [u8],
        width: u32,
        height: u32,
        from: &Point2D,
        to: &Point2D,
        thickness: f64,
        color: [f32; 4],
    ) {
        let dx = to.x - from.x;
        let dy = to.y - from.y;
        let len = (dx * dx + dy * dy).sqrt();
        if len < 1e-9 {
            return;
        }
        let half = thickness / 2.0;
        let nx = -dy / len * half;
        let ny = dx / len * half;
        let quad = [
            Point2D::new(from.x + nx, from.y + ny),
            Point2D::new(to.x + nx, to.y + ny),
            Point2D::new(to.x - nx, to.y - ny),
            Point2D::new(from.x - nx, from.y - ny),
        ];
        Self::fill_quad(buffer, width, height, &quad, color);
    }

    /// Draw a filled convex quad with alpha blending, optional corner rounding
    /// and an optional outline.
    ///
    /// With no rounding or outline this is the original hard-edged scanline
    /// fill. Otherwise the quad is eroded by the corner radius and shaded from
    /// the signed distance to that eroded core, which rounds the corners and
    /// gives an antialiased edge for free.
    #[allow(clippy::too_many_arguments)]
    fn draw_quad(
        buffer: &mut [u8],
        width: u32,
        height: u32,
        quad: &[Point2D; 4],
        color: [f32; 4],
        corner_radius: f64,
        border_width: f64,
        border_color: [f32; 4],
    ) {
        let w = width as i32;
        let h = height as i32;

        let rounded = corner_radius > 0.0 || border_width > 0.0;
        let radius = corner_radius.min(Self::max_inset(quad));
        let eroded = if rounded {
            Self::erode_convex_quad(quad, radius)
        } else {
            None
        };

        // Find bounding box, padded by one pixel for the antialiased edge.
        let pad = if rounded { 1.0 } else { 0.0 };
        let min_x = (quad.iter().map(|p| p.x).fold(f64::MAX, f64::min) - pad).floor() as i32;
        let max_x = (quad.iter().map(|p| p.x).fold(f64::MIN, f64::max) + pad).ceil() as i32;
        let min_y = (quad.iter().map(|p| p.y).fold(f64::MAX, f64::min) - pad).floor() as i32;
        let max_y = (quad.iter().map(|p| p.y).fold(f64::MIN, f64::max) + pad).ceil() as i32;

        // Clamp to buffer bounds
        let min_x = min_x.max(0);
        let max_x = max_x.min(w - 1);
        let min_y = min_y.max(0);
        let max_y = max_y.min(h - 1);

        if min_x > max_x || min_y > max_y {
            return;
        }

        if color[3] <= 0.0 && !(border_width > 0.0 && border_color[3] > 0.0) {
            return;
        }

        for y in min_y..=max_y {
            for x in min_x..=max_x {
                let px = x as f64 + 0.5;
                let py = y as f64 + 0.5;
                let idx = ((y as usize) * (width as usize) + (x as usize)) * 4;

                match &eroded {
                    None => {
                        if Self::point_in_convex_quad(px, py, quad) {
                            Self::blend_pixel(buffer, idx, color, 1.0);
                        }
                    }
                    Some(core) => {
                        // Negative inside the rounded shape, zero on its edge.
                        let distance = Self::signed_distance_convex(px, py, core) - radius;
                        let coverage = (0.5 - distance).clamp(0.0, 1.0);
                        if coverage <= 0.0 {
                            continue;
                        }
                        let on_border = border_width > 0.0 && distance >= -border_width;
                        let pixel_color = if on_border { border_color } else { color };
                        Self::blend_pixel(buffer, idx, pixel_color, coverage as f32);
                    }
                }
            }
        }
    }

    /// Alpha-blend a single premultiplied-by-coverage color into the buffer.
    fn blend_pixel(buffer: &mut [u8], idx: usize, color: [f32; 4], coverage: f32) {
        let alpha = color[3] * coverage;
        if alpha <= 0.0 {
            return;
        }

        if alpha >= 0.99 {
            buffer[idx] = (color[0] * 255.0) as u8;
            buffer[idx + 1] = (color[1] * 255.0) as u8;
            buffer[idx + 2] = (color[2] * 255.0) as u8;
            buffer[idx + 3] = 255;
            return;
        }

        let dst_r = buffer[idx] as f32 / 255.0;
        let dst_g = buffer[idx + 1] as f32 / 255.0;
        let dst_b = buffer[idx + 2] as f32 / 255.0;
        let dst_a = buffer[idx + 3] as f32 / 255.0;

        let out_a = alpha + dst_a * (1.0 - alpha);
        if out_a <= 0.0 {
            return;
        }
        let out_r = (color[0] * alpha + dst_r * dst_a * (1.0 - alpha)) / out_a;
        let out_g = (color[1] * alpha + dst_g * dst_a * (1.0 - alpha)) / out_a;
        let out_b = (color[2] * alpha + dst_b * dst_a * (1.0 - alpha)) / out_a;

        buffer[idx] = (out_r * 255.0) as u8;
        buffer[idx + 1] = (out_g * 255.0) as u8;
        buffer[idx + 2] = (out_b * 255.0) as u8;
        buffer[idx + 3] = (out_a * 255.0) as u8;
    }

    /// Largest inset that still leaves a non-degenerate core, so a big corner
    /// radius on a thin strip cannot turn the quad inside out.
    fn max_inset(quad: &[Point2D; 4]) -> f64 {
        let mut shortest = f64::MAX;
        for i in 0..4 {
            let j = (i + 1) % 4;
            let dx = quad[j].x - quad[i].x;
            let dy = quad[j].y - quad[i].y;
            shortest = shortest.min((dx * dx + dy * dy).sqrt());
        }
        (shortest / 2.0).max(0.0)
    }

    /// Shrink a convex quad by `amount` pixels along its inward edge normals.
    /// Returns None when the result would collapse.
    fn erode_convex_quad(quad: &[Point2D; 4], amount: f64) -> Option<[Point2D; 4]> {
        if amount <= 0.0 {
            return Some(*quad);
        }

        // Positive for counter-clockwise winding, negative for clockwise.
        let mut area2 = 0.0;
        for i in 0..4 {
            let j = (i + 1) % 4;
            area2 += quad[i].x * quad[j].y - quad[j].x * quad[i].y;
        }
        let winding = if area2 >= 0.0 { 1.0 } else { -1.0 };

        // Offset each edge inward, keeping a point and direction for each line.
        let mut lines = [(0.0f64, 0.0f64, 0.0f64, 0.0f64); 4];
        for i in 0..4 {
            let j = (i + 1) % 4;
            let dx = quad[j].x - quad[i].x;
            let dy = quad[j].y - quad[i].y;
            let len = (dx * dx + dy * dy).sqrt();
            if len < 1e-9 {
                return None;
            }
            let (ux, uy) = (dx / len, dy / len);
            // Inward normal for this winding.
            let (nx, ny) = (-uy * winding, ux * winding);
            lines[i] = (quad[i].x + nx * amount, quad[i].y + ny * amount, ux, uy);
        }

        let mut out = *quad;
        for i in 0..4 {
            let prev = (i + 3) % 4;
            out[i] = Self::line_intersection(lines[prev], lines[i])?;
        }
        Some(out)
    }

    /// Intersect two lines given as (point_x, point_y, dir_x, dir_y).
    fn line_intersection(a: (f64, f64, f64, f64), b: (f64, f64, f64, f64)) -> Option<Point2D> {
        let (ax, ay, adx, ady) = a;
        let (bx, by, bdx, bdy) = b;
        let denominator = adx * bdy - ady * bdx;
        if denominator.abs() < 1e-9 {
            return None;
        }
        let t = ((bx - ax) * bdy - (by - ay) * bdx) / denominator;
        Some(Point2D::new(ax + adx * t, ay + ady * t))
    }

    /// Signed distance from a point to a convex quad: negative inside.
    fn signed_distance_convex(px: f64, py: f64, quad: &[Point2D; 4]) -> f64 {
        let mut nearest = f64::MAX;
        for i in 0..4 {
            let j = (i + 1) % 4;
            nearest = nearest.min(Self::distance_to_segment(px, py, &quad[i], &quad[j]));
        }
        if Self::point_in_convex_quad(px, py, quad) {
            -nearest
        } else {
            nearest
        }
    }

    /// Shortest distance from a point to a line segment.
    fn distance_to_segment(px: f64, py: f64, a: &Point2D, b: &Point2D) -> f64 {
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        let len_squared = dx * dx + dy * dy;
        let t = if len_squared < 1e-12 {
            0.0
        } else {
            (((px - a.x) * dx + (py - a.y) * dy) / len_squared).clamp(0.0, 1.0)
        };
        let cx = a.x + dx * t;
        let cy = a.y + dy * t;
        ((px - cx).powi(2) + (py - cy).powi(2)).sqrt()
    }

    /// Check if a point is inside a convex quadrilateral using cross-product signs.
    fn point_in_convex_quad(px: f64, py: f64, quad: &[Point2D; 4]) -> bool {
        // Check that the point is on the same side of all 4 edges
        let mut sign = 0i8;
        for i in 0..4 {
            let j = (i + 1) % 4;
            let edge_x = quad[j].x - quad[i].x;
            let edge_y = quad[j].y - quad[i].y;
            let to_point_x = px - quad[i].x;
            let to_point_y = py - quad[i].y;
            let cross = edge_x * to_point_y - edge_y * to_point_x;

            if cross.abs() < 1e-10 {
                continue; // On the edge
            }
            let this_sign = if cross > 0.0 { 1i8 } else { -1i8 };
            if sign == 0 {
                sign = this_sign;
            } else if sign != this_sign {
                return false;
            }
        }
        true
    }

    /// Expand a quad outward by a given number of pixels (for glow effect).
    fn expand_quad(quad: &[Point2D; 4], amount: f64) -> [Point2D; 4] {
        // Find centroid
        let cx = (quad[0].x + quad[1].x + quad[2].x + quad[3].x) / 4.0;
        let cy = (quad[0].y + quad[1].y + quad[2].y + quad[3].y) / 4.0;

        let mut expanded = *quad;
        for point in expanded.iter_mut() {
            let dx = point.x - cx;
            let dy = point.y - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            if dist > 0.0 {
                point.x += dx / dist * amount;
                point.y += dy / dist * amount;
            }
        }
        expanded
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::overlay_geometry::types::NoteStrip;

    #[test]
    fn test_point_in_quad() {
        let quad = [
            Point2D::new(0.0, 0.0),
            Point2D::new(10.0, 0.0),
            Point2D::new(10.0, 10.0),
            Point2D::new(0.0, 10.0),
        ];

        assert!(Compositor::point_in_convex_quad(5.0, 5.0, &quad));
        assert!(Compositor::point_in_convex_quad(1.0, 1.0, &quad));
        assert!(!Compositor::point_in_convex_quad(-1.0, 5.0, &quad));
        assert!(!Compositor::point_in_convex_quad(11.0, 5.0, &quad));
    }

    #[test]
    fn test_composite_simple() {
        // 4x4 white image
        let mut buffer = vec![255u8; 4 * 4 * 4];
        let frame = OverlayFrame {
            strips: vec![NoteStrip {
                quad: [
                    Point2D::new(1.0, 1.0),
                    Point2D::new(3.0, 1.0),
                    Point2D::new(3.0, 3.0),
                    Point2D::new(1.0, 3.0),
                ],
                color: [1.0, 0.0, 0.0, 1.0], // Opaque red
                ..Default::default()
            }],
            ..Default::default()
        };

        Compositor::composite_frame(&mut buffer, 4, 4, &frame, 0.0);

        // Pixel at (1,1) should be red
        let (x, y) = (1usize, 1usize);
        let idx = (y * 4 + x) * 4;
        assert_eq!(buffer[idx], 255); // R
        assert_eq!(buffer[idx + 1], 0); // G
        assert_eq!(buffer[idx + 2], 0); // B

        // Pixel at (0,0) should still be white
        assert_eq!(buffer[0], 255);
        assert_eq!(buffer[1], 255);
        assert_eq!(buffer[2], 255);
    }

    #[test]
    fn test_corner_radius_cuts_corners() {
        let quad = [
            Point2D::new(0.0, 0.0),
            Point2D::new(20.0, 0.0),
            Point2D::new(20.0, 20.0),
            Point2D::new(0.0, 20.0),
        ];
        let strip = NoteStrip {
            quad,
            color: [1.0, 0.0, 0.0, 1.0],
            corner_radius: 8.0,
            ..Default::default()
        };
        let frame = OverlayFrame {
            strips: vec![strip],
            ..Default::default()
        };

        let mut buffer = vec![255u8; 20 * 20 * 4];
        Compositor::composite_frame(&mut buffer, 20, 20, &frame, 0.0);

        // The centre is filled...
        let centre = (10 * 20 + 10) * 4;
        assert_eq!(buffer[centre], 255);
        assert_eq!(buffer[centre + 1], 0);

        // ...while the very corner is rounded away and stays white.
        let corner = 0;
        assert_eq!(buffer[corner + 1], 255, "corner pixel should be untouched");
    }

    #[test]
    fn test_border_is_drawn_on_the_edge() {
        let quad = [
            Point2D::new(0.0, 0.0),
            Point2D::new(20.0, 0.0),
            Point2D::new(20.0, 20.0),
            Point2D::new(0.0, 20.0),
        ];
        let strip = NoteStrip {
            quad,
            color: [1.0, 0.0, 0.0, 1.0], // red fill
            border_width: 3.0,
            border_color: [0.0, 0.0, 1.0, 1.0], // blue outline
            ..Default::default()
        };
        let frame = OverlayFrame {
            strips: vec![strip],
            ..Default::default()
        };

        let mut buffer = vec![255u8; 20 * 20 * 4];
        Compositor::composite_frame(&mut buffer, 20, 20, &frame, 0.0);

        // Just inside the edge is the border colour.
        let edge = (10 * 20 + 1) * 4;
        assert_eq!(buffer[edge + 2], 255, "edge should be blue");
        assert_eq!(buffer[edge], 0);

        // The middle keeps the fill colour.
        let centre = (10 * 20 + 10) * 4;
        assert_eq!(buffer[centre], 255, "centre should be red");
        assert_eq!(buffer[centre + 2], 0);
    }

    #[test]
    fn test_fall_lane_is_drawn() {
        let frame = OverlayFrame {
            fall_lane_quad: Some([
                Point2D::new(0.0, 10.0),
                Point2D::new(10.0, 10.0),
                Point2D::new(10.0, 0.0),
                Point2D::new(0.0, 0.0),
            ]),
            lane_opacity: 1.0,
            ..Default::default()
        };

        let mut buffer = vec![255u8; 10 * 10 * 4];
        Compositor::composite_frame(&mut buffer, 10, 10, &frame, 0.0);

        // An opaque black lane covers the frame.
        let idx = (5 * 10 + 5) * 4;
        assert_eq!(buffer[idx], 0);
        assert_eq!(buffer[idx + 1], 0);
        assert_eq!(buffer[idx + 2], 0);
    }

    #[test]
    fn test_erode_convex_quad_shrinks_uniformly() {
        let quad = [
            Point2D::new(0.0, 0.0),
            Point2D::new(10.0, 0.0),
            Point2D::new(10.0, 10.0),
            Point2D::new(0.0, 10.0),
        ];
        let eroded = Compositor::erode_convex_quad(&quad, 2.0).expect("erosion should succeed");
        assert!((eroded[0].x - 2.0).abs() < 1e-6);
        assert!((eroded[0].y - 2.0).abs() < 1e-6);
        assert!((eroded[2].x - 8.0).abs() < 1e-6);
        assert!((eroded[2].y - 8.0).abs() < 1e-6);
    }

    #[test]
    fn test_background_dim() {
        // 2x2 white image
        let mut buffer = vec![255u8; 2 * 2 * 4];
        let frame = OverlayFrame::default();

        Compositor::composite_frame(&mut buffer, 2, 2, &frame, 0.5);

        // Should be approximately half brightness
        assert!(buffer[0] < 130 && buffer[0] > 126); // ~127
    }
}
