use nalgebra::{DMatrix, DVector};

use super::types::{CalibrationData, KeyPosition, KeyboardCorners, KeyboardSize, Point2D};

/// Compute the full calibration from user-placed corners and keyboard size.
/// Returns calibration data with homography matrix and all key positions.
pub fn compute_calibration(
    corners: &KeyboardCorners,
    keyboard_size: KeyboardSize,
) -> CalibrationData {
    let white_keys = keyboard_size.white_keys() as f64;

    // Canonical keyboard rectangle: (0,0) to (white_keys, 1.0)
    // where x=0 is leftmost white key, x=white_keys is rightmost
    let src = [
        Point2D::new(0.0, 0.0),           // top-left
        Point2D::new(white_keys, 0.0),     // top-right
        Point2D::new(white_keys, 1.0),     // bottom-right
        Point2D::new(0.0, 1.0),            // bottom-left
    ];

    let dst = [
        corners.top_left,
        corners.top_right,
        corners.bottom_right,
        corners.bottom_left,
    ];

    let homography = compute_homography(&src, &dst);
    let key_positions = compute_key_positions(&homography, keyboard_size);

    CalibrationData {
        corners: corners.clone(),
        keyboard_size,
        homography,
        key_positions,
    }
}

/// Compute 3x3 homography matrix mapping src points to dst points.
/// Uses the direct 8×8 linear system with h33=1 constraint.
fn compute_homography(src: &[Point2D; 4], dst: &[Point2D; 4]) -> [[f64; 3]; 3] {
    // With h33 = 1, we have 8 unknowns (h11..h32).
    // Each point pair gives 2 equations. Rearranged as A*h = b.
    // Unknowns: [h11, h12, h13, h21, h22, h23, h31, h32]

    let mut a_data = [0.0f64; 64]; // 8×8
    let mut b_data = [0.0f64; 8];

    for i in 0..4 {
        let (x, y) = (src[i].x, src[i].y);
        let (xp, yp) = (dst[i].x, dst[i].y);
        let row1 = i * 2;
        let row2 = i * 2 + 1;

        // x' = (h11*x + h12*y + h13) / (h31*x + h32*y + 1)
        // x'*(h31*x + h32*y + 1) = h11*x + h12*y + h13
        // h11*x + h12*y + h13 - h31*x'*x - h32*x'*y = x'
        a_data[row1 * 8 + 0] = x;
        a_data[row1 * 8 + 1] = y;
        a_data[row1 * 8 + 2] = 1.0;
        a_data[row1 * 8 + 6] = -xp * x;
        a_data[row1 * 8 + 7] = -xp * y;
        b_data[row1] = xp;

        // y' = (h21*x + h22*y + h23) / (h31*x + h32*y + 1)
        // h21*x + h22*y + h23 - h31*y'*x - h32*y'*y = y'
        a_data[row2 * 8 + 3] = x;
        a_data[row2 * 8 + 4] = y;
        a_data[row2 * 8 + 5] = 1.0;
        a_data[row2 * 8 + 6] = -yp * x;
        a_data[row2 * 8 + 7] = -yp * y;
        b_data[row2] = yp;
    }

    let a_mat = DMatrix::from_row_slice(8, 8, &a_data);
    let b_vec = DVector::from_row_slice(&b_data);

    let h_vec = a_mat
        .lu()
        .solve(&b_vec)
        .unwrap_or_else(|| DVector::zeros(8));

    let mut h = [[0.0f64; 3]; 3];
    h[0][0] = h_vec[0];
    h[0][1] = h_vec[1];
    h[0][2] = h_vec[2];
    h[1][0] = h_vec[3];
    h[1][1] = h_vec[4];
    h[1][2] = h_vec[5];
    h[2][0] = h_vec[6];
    h[2][1] = h_vec[7];
    h[2][2] = 1.0;

    h
}

/// Transform a point from canonical space to screen space using the homography.
pub fn transform_point(h: &[[f64; 3]; 3], p: &Point2D) -> Point2D {
    let x = p.x;
    let y = p.y;

    let w = h[2][0] * x + h[2][1] * y + h[2][2];
    let xp = (h[0][0] * x + h[0][1] * y + h[0][2]) / w;
    let yp = (h[1][0] * x + h[1][1] * y + h[1][2]) / w;

    Point2D::new(xp, yp)
}

/// Compute screen-space positions for all keys on the keyboard.
fn compute_key_positions(h: &[[f64; 3]; 3], keyboard_size: KeyboardSize) -> Vec<KeyPosition> {
    let lowest = keyboard_size.lowest_note();
    let highest = keyboard_size.highest_note();
    let mut positions = Vec::new();

    for note in lowest..=highest {
        let is_black = is_black_key(note);
        let (x_left, x_right) = key_x_bounds(note, keyboard_size);

        // Key extends from y=0 (far/top edge) to y=1 (near/bottom edge)
        // Black keys are shorter: y=0 to y=0.6
        let y_top = 0.0;
        let y_bottom = if is_black { 0.6 } else { 1.0 };

        let tl = transform_point(h, &Point2D::new(x_left, y_top));
        let tr = transform_point(h, &Point2D::new(x_right, y_top));
        let br = transform_point(h, &Point2D::new(x_right, y_bottom));
        let bl = transform_point(h, &Point2D::new(x_left, y_bottom));

        let x_center = (x_left + x_right) / 2.0;

        positions.push(KeyPosition {
            note,
            is_black,
            screen_quad: [tl, tr, br, bl],
            canonical_x_center: x_center,
        });
    }

    positions
}

/// Returns true if the MIDI note is a black key.
pub fn is_black_key(note: u8) -> bool {
    let semitone = note % 12;
    matches!(semitone, 1 | 3 | 6 | 8 | 10)
}

/// Compute the x-bounds (left, right) of a key in canonical space.
/// White keys are 1.0 unit wide. Black keys are narrower and positioned between whites.
fn key_x_bounds(note: u8, keyboard_size: KeyboardSize) -> (f64, f64) {
    let lowest = keyboard_size.lowest_note();

    if is_black_key(note) {
        // Black key: position relative to the white key to its left
        let white_index = count_white_keys_below(note, lowest) as f64;
        let semitone = note % 12;

        // Black key offsets from left white key edge (based on real piano geometry)
        // These give the center position as fraction past the left white key
        let center_offset = match semitone {
            1 => 0.55,  // C#
            3 => 0.75,  // D#
            6 => 0.50,  // F#
            8 => 0.62,  // G#
            10 => 0.74, // A#
            _ => 0.5,
        };

        let center_x = white_index + center_offset;
        let half_width = 0.30; // Black key is 0.6 units wide
        (center_x - half_width, center_x + half_width)
    } else {
        // White key: sequential position
        let white_index = count_white_keys_below(note, lowest) as f64;
        (white_index, white_index + 1.0)
    }
}

/// Count how many white keys are at or below this note (starting from lowest).
fn count_white_keys_below(note: u8, lowest: u8) -> u8 {
    let mut count = 0;
    for n in lowest..note {
        if !is_black_key(n) {
            count += 1;
        }
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_black_key() {
        assert!(!is_black_key(60)); // C4 = white
        assert!(is_black_key(61)); // C#4 = black
        assert!(!is_black_key(62)); // D4 = white
        assert!(is_black_key(63)); // D#4 = black
        assert!(!is_black_key(64)); // E4 = white
        assert!(!is_black_key(65)); // F4 = white
        assert!(is_black_key(66)); // F#4 = black
    }

    #[test]
    fn test_identity_homography() {
        // If src == dst, homography should be approximately identity
        let src = [
            Point2D::new(0.0, 0.0),
            Point2D::new(100.0, 0.0),
            Point2D::new(100.0, 50.0),
            Point2D::new(0.0, 50.0),
        ];
        let h = compute_homography(&src, &src);

        let p = Point2D::new(50.0, 25.0);
        let result = transform_point(&h, &p);
        assert!((result.x - 50.0).abs() < 0.01);
        assert!((result.y - 25.0).abs() < 0.01);
    }

    #[test]
    fn test_simple_scale_homography() {
        let src = [
            Point2D::new(0.0, 0.0),
            Point2D::new(1.0, 0.0),
            Point2D::new(1.0, 1.0),
            Point2D::new(0.0, 1.0),
        ];
        // Scale by 200 in x, 100 in y
        let dst = [
            Point2D::new(0.0, 0.0),
            Point2D::new(200.0, 0.0),
            Point2D::new(200.0, 100.0),
            Point2D::new(0.0, 100.0),
        ];
        let h = compute_homography(&src, &dst);

        let p = transform_point(&h, &Point2D::new(0.5, 0.5));
        assert!((p.x - 100.0).abs() < 0.1);
        assert!((p.y - 50.0).abs() < 0.1);
    }

    #[test]
    fn test_key_positions_88() {
        let corners = KeyboardCorners {
            top_left: Point2D::new(0.0, 0.0),
            top_right: Point2D::new(1920.0, 0.0),
            bottom_right: Point2D::new(1920.0, 200.0),
            bottom_left: Point2D::new(0.0, 200.0),
        };
        let cal = compute_calibration(&corners, KeyboardSize::Keys88);
        assert_eq!(cal.key_positions.len(), 88);

        // First key (A0 = note 21) should be near left edge
        let first = &cal.key_positions[0];
        assert_eq!(first.note, 21);
        assert!(!first.is_black); // A0 is white

        // Last key (C8 = note 108) should be near right edge
        let last = &cal.key_positions[87];
        assert_eq!(last.note, 108);
        assert!(!last.is_black); // C8 is white
    }

    #[test]
    fn test_count_white_keys() {
        // From A0 (21) to C8 (108) there are 52 white keys
        let count = count_white_keys_below(108, 21);
        // Should be 51 (all whites below C8, not counting C8 itself)
        assert_eq!(count, 51);
    }
}
