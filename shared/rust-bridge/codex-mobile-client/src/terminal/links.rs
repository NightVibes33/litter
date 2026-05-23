//! Terminal URL detection.
//!
//! Combines:
//!   - OSC 8 hyperlinks emitted by the shell (parsed by [`super::osc`]).
//!   - Plain-text URL detection via the `linkify` crate over viewport
//!     text supplied by the platform.
//!
//! Platform contract: after Ghostty paints the viewport (or on a debounce
//! tied to `notify_needs_draw`), the platform calls
//! [`crate::terminal::TerminalRenderer::set_viewport_text`] with the
//! current visible rows. The renderer runs the linkifier across those
//! rows, merges results with OSC 8 hyperlinks (OSC 8 wins on overlap),
//! and caches the result. Tap handling reads the cache via
//! [`crate::terminal::TerminalRenderer::link_at`].
//!
//! Cache key: `(start_row, content_hash)`. If the viewport text is
//! unchanged, the cached `Vec<TerminalLink>` is reused.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use super::osc::{TerminalCellPosition, TerminalHyperlink};

/// Source of a [`TerminalLink`]. OSC 8 is shell-emitted and authoritative;
/// `Linkifier` is heuristic plain-text scan.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TerminalLinkSource {
    Osc8,
    Linkifier,
}

/// A live, tap-targetable link in the terminal viewport. `start` and `end`
/// are cell positions (rows are 0-based from the top of the viewport
/// snapshot the platform supplied, not absolute scrollback positions).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TerminalLink {
    pub start: TerminalCellPosition,
    pub end: TerminalCellPosition,
    pub url: String,
    pub source: TerminalLinkSource,
}

/// Snapshot of the renderer's cached link state.
#[derive(Debug, Default)]
pub(crate) struct LinksCache {
    /// First row of the last viewport snapshot the platform supplied.
    start_row: u32,
    /// Hash of the last viewport content (row count + concatenated bytes).
    content_hash: u64,
    /// Last computed link set.
    links: Vec<TerminalLink>,
}

impl LinksCache {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    /// Update the viewport text and recompute links if content changed.
    /// `start_row` is the absolute row of the first entry in `rows`
    /// (typically the top of the visible viewport).
    pub(crate) fn update(
        &mut self,
        start_row: u32,
        rows: &[String],
        osc_hyperlinks: &[TerminalHyperlink],
    ) {
        let hash = hash_rows(rows);
        if hash == self.content_hash && start_row == self.start_row && !self.links.is_empty() {
            // OSC hyperlinks may have changed even if the viewport text
            // hasn't (a new shell-emitted hyperlink would arrive without
            // affecting the rendered text immediately). Re-merge cheaply
            // when the OSC set differs by length or last entry.
            if !osc_set_changed(&self.links, osc_hyperlinks) {
                return;
            }
        }
        self.start_row = start_row;
        self.content_hash = hash;
        self.links = compute_links(start_row, rows, osc_hyperlinks);
    }

    pub(crate) fn snapshot(&self) -> Vec<TerminalLink> {
        self.links.clone()
    }

    pub(crate) fn link_at(&self, position: TerminalCellPosition) -> Option<TerminalLink> {
        self.links
            .iter()
            .find(|link| contains(link, position))
            .cloned()
    }
}

fn compute_links(
    start_row: u32,
    rows: &[String],
    osc_hyperlinks: &[TerminalHyperlink],
) -> Vec<TerminalLink> {
    let mut out: Vec<TerminalLink> = osc_hyperlinks
        .iter()
        .map(|hl| TerminalLink {
            start: hl.start,
            end: hl.end,
            url: hl.url.clone(),
            source: TerminalLinkSource::Osc8,
        })
        .collect();

    let finder = linkify::LinkFinder::new();
    for (offset, row) in rows.iter().enumerate() {
        let abs_row = start_row.saturating_add(offset as u32);
        for link in finder.links(row) {
            // linkify reports byte offsets into the row. Translate to
            // column offsets by counting non-continuation bytes; we treat
            // each non-continuation byte as one cell (best-effort wide-
            // char handling — see osc.rs cursor estimator).
            let start_col = column_for_byte(row, link.start());
            let end_col = column_for_byte(row, link.end());
            let candidate = TerminalLink {
                start: TerminalCellPosition {
                    row: abs_row,
                    col: start_col,
                },
                end: TerminalCellPosition {
                    row: abs_row,
                    col: end_col,
                },
                url: link.as_str().to_string(),
                source: TerminalLinkSource::Linkifier,
            };
            // OSC 8 wins on overlap: skip plain-text candidates that
            // touch any OSC 8 range we already recorded.
            let overlaps_osc8 = out
                .iter()
                .filter(|existing| matches!(existing.source, TerminalLinkSource::Osc8))
                .any(|existing| overlaps(existing, &candidate));
            if !overlaps_osc8 {
                out.push(candidate);
            }
        }
    }
    out
}

fn column_for_byte(row: &str, byte_offset: usize) -> u32 {
    let mut col: u32 = 0;
    for (i, b) in row.bytes().enumerate() {
        if i >= byte_offset {
            break;
        }
        let is_continuation = (b & 0xC0) == 0x80;
        if !is_continuation {
            col += 1;
        }
    }
    col
}

fn hash_rows(rows: &[String]) -> u64 {
    let mut hasher = DefaultHasher::new();
    rows.len().hash(&mut hasher);
    for row in rows {
        row.hash(&mut hasher);
    }
    hasher.finish()
}

fn osc_set_changed(cached: &[TerminalLink], hyperlinks: &[TerminalHyperlink]) -> bool {
    let cached_osc: Vec<&TerminalLink> = cached
        .iter()
        .filter(|l| matches!(l.source, TerminalLinkSource::Osc8))
        .collect();
    if cached_osc.len() != hyperlinks.len() {
        return true;
    }
    cached_osc
        .iter()
        .zip(hyperlinks.iter())
        .any(|(c, h)| c.url != h.url || c.start != h.start || c.end != h.end)
}

fn contains(link: &TerminalLink, pos: TerminalCellPosition) -> bool {
    // Single-row link: [start.col, end.col).
    if link.start.row == link.end.row {
        return pos.row == link.start.row && pos.col >= link.start.col && pos.col < link.end.col;
    }
    // Multi-row link: full rows in between, plus tails.
    if pos.row < link.start.row || pos.row > link.end.row {
        return false;
    }
    if pos.row == link.start.row {
        return pos.col >= link.start.col;
    }
    if pos.row == link.end.row {
        return pos.col < link.end.col;
    }
    true
}

fn overlaps(a: &TerminalLink, b: &TerminalLink) -> bool {
    // Conservative rectangular intersection over (row, col) ranges.
    // Works because both kinds of link record a contiguous left-to-right
    // cell range; multi-row spans intersect if any row of `b` falls
    // inside `a`'s row range and the column ranges overlap on shared
    // rows.
    let a_min_row = a.start.row;
    let a_max_row = a.end.row;
    let b_min_row = b.start.row;
    let b_max_row = b.end.row;
    if a_max_row < b_min_row || b_max_row < a_min_row {
        return false;
    }
    // Same-row fast path.
    if a_min_row == a_max_row && b_min_row == b_max_row && a_min_row == b_min_row {
        let a0 = a.start.col;
        let a1 = a.end.col;
        let b0 = b.start.col;
        let b1 = b.end.col;
        return a0 < b1 && b0 < a1;
    }
    // Conservatively report multi-row overlaps as true.
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cell(row: u32, col: u32) -> TerminalCellPosition {
        TerminalCellPosition { row, col }
    }

    #[test]
    fn linkifies_plain_url_in_viewport() {
        let mut cache = LinksCache::new();
        let rows = vec!["see https://example.com for info".to_string()];
        cache.update(0, &rows, &[]);
        let links = cache.snapshot();
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].url, "https://example.com");
        assert!(matches!(links[0].source, TerminalLinkSource::Linkifier));
        assert_eq!(links[0].start, cell(0, 4));
        assert_eq!(
            links[0].end,
            cell(0, 4 + "https://example.com".len() as u32)
        );
    }

    #[test]
    fn osc8_hyperlink_preserved() {
        let mut cache = LinksCache::new();
        let osc = vec![TerminalHyperlink {
            start: cell(2, 0),
            end: cell(2, 5),
            url: "https://foo.test".into(),
            id: String::new(),
        }];
        cache.update(0, &["plain row".to_string()], &osc);
        let links = cache.snapshot();
        assert_eq!(links.len(), 1);
        assert!(matches!(links[0].source, TerminalLinkSource::Osc8));
        assert_eq!(links[0].url, "https://foo.test");
    }

    #[test]
    fn osc8_wins_over_linkified_on_overlap() {
        let mut cache = LinksCache::new();
        // Same row contains a plain URL AND an OSC 8 spanning the same range.
        let row = "https://example.com".to_string();
        let url_len = row.len() as u32;
        let osc = vec![TerminalHyperlink {
            start: cell(0, 0),
            end: cell(0, url_len),
            url: "https://example.com".into(),
            id: String::new(),
        }];
        cache.update(0, &[row], &osc);
        let links = cache.snapshot();
        assert_eq!(links.len(), 1);
        assert!(matches!(links[0].source, TerminalLinkSource::Osc8));
    }

    #[test]
    fn link_at_hits_inside_range() {
        let mut cache = LinksCache::new();
        cache.update(0, &["see https://example.com end".to_string()], &[]);
        // URL begins at col 4, ends at col 4 + 19 = 23 (exclusive).
        assert!(cache.link_at(cell(0, 4)).is_some());
        assert!(cache.link_at(cell(0, 15)).is_some());
        assert!(cache.link_at(cell(0, 22)).is_some());
        assert!(cache.link_at(cell(0, 23)).is_none());
        assert!(cache.link_at(cell(0, 3)).is_none());
        assert!(cache.link_at(cell(1, 5)).is_none());
    }

    #[test]
    fn content_hash_skips_recompute() {
        let mut cache = LinksCache::new();
        cache.update(0, &["https://a.test".to_string()], &[]);
        let first = cache.snapshot();
        // Calling again with identical inputs reuses the cache.
        cache.update(0, &["https://a.test".to_string()], &[]);
        assert_eq!(cache.snapshot(), first);
    }

    #[test]
    fn cache_invalidates_when_osc_set_changes() {
        let mut cache = LinksCache::new();
        let rows = vec!["plain text".to_string()];
        cache.update(0, &rows, &[]);
        assert_eq!(cache.snapshot().len(), 0);
        let osc = vec![TerminalHyperlink {
            start: cell(0, 0),
            end: cell(0, 5),
            url: "https://x".into(),
            id: String::new(),
        }];
        // Same rows, different OSC set: must re-merge.
        cache.update(0, &rows, &osc);
        assert_eq!(cache.snapshot().len(), 1);
    }

    #[test]
    fn multiple_links_one_row() {
        let mut cache = LinksCache::new();
        cache.update(
            0,
            &["see http://a.test and https://b.test ok".to_string()],
            &[],
        );
        let links = cache.snapshot();
        assert_eq!(links.len(), 2);
    }

    #[test]
    fn handles_multibyte_characters() {
        let mut cache = LinksCache::new();
        // "λ https://x.test" — λ is 2 bytes (0xCE 0xBB) but 1 cell.
        cache.update(0, &["λ https://x.test".to_string()], &[]);
        let links = cache.snapshot();
        assert_eq!(links.len(), 1);
        // λ is at col 0, space at col 1, URL starts at col 2.
        assert_eq!(links[0].start, cell(0, 2));
    }
}
