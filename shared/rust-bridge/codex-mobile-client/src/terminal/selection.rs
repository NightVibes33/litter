//! Terminal selection geometry: hit testing, word/line boundary math.
//!
//! Ghostty exposes read-back-only selection APIs, so we paint the highlight
//! overlay in platform code and use this module to compute *what* gets
//! selected. Word boundaries use `unicode-segmentation` so CJK + ZWJ-joined
//! emoji come out as one grapheme cluster — matching macOS Terminal /
//! iTerm behaviour rather than naïve whitespace splitting.

use unicode_segmentation::UnicodeSegmentation;

use super::osc::TerminalCellPosition;

/// Inclusive cell range, with optional rectangle (block-selection) mode.
/// `start` and `end` are inclusive in both dimensions.
///
/// Convention: callers pass positions in viewport-relative coords where
/// `row` 0 is the top visible line; scrollback rows are sent as negative
/// when applicable. Because `TerminalCellPosition.row` is `u32`, the
/// platform offsets scrollback into the appropriate row index before
/// calling — this module never sees negative rows directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct TerminalCellRange {
    pub start: TerminalCellPosition,
    pub end: TerminalCellPosition,
    pub rectangle: bool,
}

/// Cell metrics describing the on-screen grid. Used by hit-testing to
/// convert pixel coords → cell coords.
///
/// Pixel coords are in the same coordinate space the platform uses for
/// the surface (iOS = points x scale).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct TerminalCellMetrics {
    pub cell_width_px: f32,
    pub cell_height_px: f32,
    pub cols: u32,
    pub rows: u32,
    /// Top row (0 in screen coords) of the viewport relative to scrollback.
    /// For sessions with no scroll this is 0. The platform doesn't really
    /// need to populate this for hit-test — selection.rs treats coords as
    /// viewport-relative — but exposing it lets future scrollback features
    /// translate.
    pub viewport_top: u32,
}

/// Compute the cell at `(x, y)` pixels given the surface's cell metrics.
/// Returns `None` if metrics describe a zero-sized cell.
pub fn hit_test_cell(
    metrics: TerminalCellMetrics,
    x_px: f32,
    y_px: f32,
) -> Option<TerminalCellPosition> {
    if metrics.cell_width_px <= 0.0 || metrics.cell_height_px <= 0.0 {
        return None;
    }
    let col = (x_px.max(0.0) / metrics.cell_width_px).floor() as u32;
    let row = (y_px.max(0.0) / metrics.cell_height_px).floor() as u32;
    let col = col.min(metrics.cols.saturating_sub(1));
    let row = row.min(metrics.rows.saturating_sub(1));
    Some(TerminalCellPosition { row, col })
}

/// Word boundaries at `col` within `line`, returning the inclusive column
/// range of the word containing the cursor — or `(col, col)` if the
/// cursor is inside whitespace.
///
/// Words are unicode-segmentation word boundaries minus pure-whitespace
/// segments. Multi-cell grapheme clusters (CJK wide chars, ZWJ emoji)
/// expand into the cells they occupy via `unicode-width`-style math; for
/// now we treat one grapheme as one column — platforms with wide-cell
/// rendering can correct this when more PRs land. Acceptable approximation
/// for v1 selection UX.
pub fn word_columns_at(line: &str, col: u32) -> (u32, u32) {
    if line.is_empty() {
        return (col, col);
    }

    // Build a per-column grapheme map so col indices line up with what the
    // renderer paints. One column = one grapheme; double-width handling is
    // a future improvement.
    let graphemes: Vec<&str> = line.graphemes(true).collect();
    if graphemes.is_empty() {
        return (col, col);
    }
    let len = graphemes.len() as u32;
    let cursor = col.min(len.saturating_sub(1)) as usize;

    let cursor_grapheme = graphemes[cursor];
    if is_whitespace_grapheme(cursor_grapheme) {
        return (col, col);
    }

    // Walk left.
    let mut left = cursor;
    while left > 0 {
        if !is_word_grapheme(graphemes[left - 1], cursor_grapheme) {
            break;
        }
        left -= 1;
    }
    // Walk right.
    let mut right = cursor;
    while right + 1 < graphemes.len() {
        if !is_word_grapheme(graphemes[right + 1], cursor_grapheme) {
            break;
        }
        right += 1;
    }
    (left as u32, right as u32)
}

/// Inclusive column range for the full line (col 0 → cols - 1).
pub fn line_columns(metrics: TerminalCellMetrics) -> (u32, u32) {
    if metrics.cols == 0 {
        (0, 0)
    } else {
        (0, metrics.cols - 1)
    }
}

fn is_whitespace_grapheme(g: &str) -> bool {
    g.chars().all(char::is_whitespace)
}

/// Two graphemes belong to the same "word" if neither is whitespace and
/// they share a "class" — alphanumeric-ish vs punctuation-ish. We collapse
/// the cursor's class to a single bool (alphanumeric+identifier-ish vs
/// punctuation/symbol) so dragging right from `foo` through `,bar` snaps
/// to the comma boundary instead of selecting through it.
fn is_word_grapheme(candidate: &str, cursor: &str) -> bool {
    if is_whitespace_grapheme(candidate) {
        return false;
    }
    is_identifier_grapheme(candidate) == is_identifier_grapheme(cursor)
}

fn is_identifier_grapheme(g: &str) -> bool {
    g.chars()
        .all(|c| c.is_alphanumeric() || c == '_' || c == '-' || c == '.')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metrics(cell_w: f32, cell_h: f32, cols: u32, rows: u32) -> TerminalCellMetrics {
        TerminalCellMetrics {
            cell_width_px: cell_w,
            cell_height_px: cell_h,
            cols,
            rows,
            viewport_top: 0,
        }
    }

    #[test]
    fn hit_test_floors_to_cell_indices() {
        let m = metrics(10.0, 20.0, 80, 24);
        let p = hit_test_cell(m, 25.0, 41.0).unwrap();
        assert_eq!(p.col, 2);
        assert_eq!(p.row, 2);
    }

    #[test]
    fn hit_test_clamps_to_grid() {
        let m = metrics(10.0, 20.0, 80, 24);
        let p = hit_test_cell(m, 99999.0, 99999.0).unwrap();
        assert_eq!(p.col, 79);
        assert_eq!(p.row, 23);
    }

    #[test]
    fn hit_test_returns_none_for_zero_metrics() {
        assert!(hit_test_cell(metrics(0.0, 20.0, 80, 24), 10.0, 10.0).is_none());
        assert!(hit_test_cell(metrics(10.0, 0.0, 80, 24), 10.0, 10.0).is_none());
    }

    #[test]
    fn word_selection_picks_ascii_identifier() {
        let (s, e) = word_columns_at("let foo = bar", 5);
        assert_eq!((s, e), (4, 6)); // "foo"
    }

    #[test]
    fn word_selection_stops_at_punctuation() {
        let (s, e) = word_columns_at("foo,bar", 0);
        assert_eq!((s, e), (0, 2)); // "foo"
        let (s, e) = word_columns_at("foo,bar", 4);
        assert_eq!((s, e), (4, 6)); // "bar"
    }

    #[test]
    fn word_selection_in_whitespace_returns_caret() {
        let (s, e) = word_columns_at("  hello", 1);
        assert_eq!((s, e), (1, 1));
    }

    #[test]
    fn word_selection_with_cjk_treats_each_grapheme_as_word_char() {
        let (s, e) = word_columns_at("漢字テスト", 2);
        assert_eq!((s, e), (0, 4));
    }

    #[test]
    fn word_selection_with_zwj_emoji_keeps_cluster() {
        // Family of four (👨‍👩‍👧‍👦) is one grapheme via ZWJ.
        let s = "hi 👨‍👩‍👧‍👦 there";
        let graphemes: Vec<&str> = s.graphemes(true).collect();
        // The emoji should be a single grapheme at col 3.
        assert_eq!(graphemes[3], "👨\u{200d}👩\u{200d}👧\u{200d}👦");
        let (start, end) = word_columns_at(s, 3);
        // Emoji selection should be itself (one grapheme) since the
        // neighbouring graphemes are spaces.
        assert_eq!((start, end), (3, 3));
    }

    #[test]
    fn line_columns_full_width() {
        let (s, e) = line_columns(metrics(10.0, 20.0, 80, 24));
        assert_eq!((s, e), (0, 79));
    }
}
