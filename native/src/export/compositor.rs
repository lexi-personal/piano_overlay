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
            for pixel in buffer.chunks_exact_mut(4) {
                pixel[0] = (pixel[0] as f32 * dim_factor) as u8;
                pixel[1] = (pixel[1] as f32 * dim_factor) as u8;
                pixel[2] = (pixel[2] as f32 * dim_factor) as u8;
                // Alpha unchanged
            }
        }

        // Draw key highlights first (below strips)
        for highlight in &frame.key_highlights {
            Self::draw_quad(buffer, width, height, &highlight.quad, highlight.color, 0.0);
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
                    strip.glow_radius,
                );
            }
        }

        // Draw main strips
        for strip in &frame.strips {
            Self::draw_quad(buffer, width, height, &strip.quad, strip.color, 0.0);
        }
    }

    /// Draw a filled convex quad with alpha blending.
    /// Uses scanline rasterization for the convex quadrilateral.
    fn draw_quad(
        buffer: &mut [u8],
        width: u32,
        height: u32,
        quad: &[Point2D; 4],
        color: [f32; 4],
        _blur: f32,
    ) {
        let w = width as i32;
        let h = height as i32;

        // Find bounding box
        let min_x = quad.iter().map(|p| p.x).fold(f64::MAX, f64::min).floor() as i32;
        let max_x = quad.iter().map(|p| p.x).fold(f64::MIN, f64::max).ceil() as i32;
        let min_y = quad.iter().map(|p| p.y).fold(f64::MAX, f64::min).floor() as i32;
        let max_y = quad.iter().map(|p| p.y).fold(f64::MIN, f64::max).ceil() as i32;

        // Clamp to buffer bounds
        let min_x = min_x.max(0);
        let max_x = max_x.min(w - 1);
        let min_y = min_y.max(0);
        let max_y = max_y.min(h - 1);

        if min_x > max_x || min_y > max_y {
            return;
        }

        // Pre-compute color bytes
        let r = (color[0] * 255.0) as u8;
        let g = (color[1] * 255.0) as u8;
        let b = (color[2] * 255.0) as u8;
        let alpha = color[3];

        if alpha <= 0.0 {
            return;
        }

        // Rasterize: for each pixel in bounding box, check if inside quad
        for y in min_y..=max_y {
            for x in min_x..=max_x {
                let px = x as f64 + 0.5;
                let py = y as f64 + 0.5;

                if Self::point_in_convex_quad(px, py, quad) {
                    let idx = ((y as usize) * (width as usize) + (x as usize)) * 4;

                    // Alpha blend (src-over)
                    if alpha >= 0.99 {
                        buffer[idx] = r;
                        buffer[idx + 1] = g;
                        buffer[idx + 2] = b;
                        buffer[idx + 3] = 255;
                    } else {
                        let dst_r = buffer[idx] as f32 / 255.0;
                        let dst_g = buffer[idx + 1] as f32 / 255.0;
                        let dst_b = buffer[idx + 2] as f32 / 255.0;
                        let dst_a = buffer[idx + 3] as f32 / 255.0;

                        let out_a = alpha + dst_a * (1.0 - alpha);
                        if out_a > 0.0 {
                            let out_r = (color[0] * alpha + dst_r * dst_a * (1.0 - alpha)) / out_a;
                            let out_g = (color[1] * alpha + dst_g * dst_a * (1.0 - alpha)) / out_a;
                            let out_b = (color[2] * alpha + dst_b * dst_a * (1.0 - alpha)) / out_a;

                            buffer[idx] = (out_r * 255.0) as u8;
                            buffer[idx + 1] = (out_g * 255.0) as u8;
                            buffer[idx + 2] = (out_b * 255.0) as u8;
                            buffer[idx + 3] = (out_a * 255.0) as u8;
                        }
                    }
                }
            }
        }
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
                glow_radius: 0.0,
                glow_intensity: 0.0,
            }],
            key_highlights: vec![],
            timestamp_ms: 0.0,
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
    fn test_background_dim() {
        // 2x2 white image
        let mut buffer = vec![255u8; 2 * 2 * 4];
        let frame = OverlayFrame {
            strips: vec![],
            key_highlights: vec![],
            timestamp_ms: 0.0,
        };

        Compositor::composite_frame(&mut buffer, 2, 2, &frame, 0.5);

        // Should be approximately half brightness
        assert!(buffer[0] < 130 && buffer[0] > 126); // ~127
    }
}
