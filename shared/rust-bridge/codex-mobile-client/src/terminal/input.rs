//! Terminal input types + encoders.
//!
//! Rust owns event *shape* + modifier flags + paste bracketing + the
//! on-screen toolbar special-key byte sequences. It does NOT re-encode
//! modifier-keyed CSI / kitty sequences — those are translated by Ghostty
//! itself when the platform calls `ghostty_surface_key` with the
//! [`TerminalKeyEvent`] forwarded via the backend.

/// Action of a key event. Mirrors `ghostty_input_action_e`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TerminalKeyAction {
    Press,
    Release,
    Repeat,
}

/// Modifier flags. Mirrors the subset of `ghostty_input_mods_e` that's
/// useful to translate from platform keyboards.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct TerminalKeyMods {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub meta: bool,
}

impl TerminalKeyMods {
    pub const NONE: TerminalKeyMods = TerminalKeyMods {
        shift: false,
        ctrl: false,
        alt: false,
        meta: false,
    };

    /// Pack mods into the same bit layout `ghostty_input_mods_e` uses
    /// (`SHIFT=1<<0`, `CTRL=1<<1`, `ALT=1<<2`, `SUPER=1<<3`).
    pub fn pack_ghostty(self) -> u32 {
        let mut bits = 0u32;
        if self.shift {
            bits |= 1 << 0;
        }
        if self.ctrl {
            bits |= 1 << 1;
        }
        if self.alt {
            bits |= 1 << 2;
        }
        if self.meta {
            bits |= 1 << 3;
        }
        bits
    }
}

/// Key code. Subset of the W3C UI-events code list plus a catch-all
/// `Other` for keys we haven't mapped yet. Platform translation tables
/// (UIKeyboardHIDUsage on iOS) decode into
/// these.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum TerminalKeyCode {
    Unidentified,
    Enter,
    Tab,
    Backspace,
    Escape,
    Space,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    PageUp,
    PageDown,
    Home,
    End,
    Delete,
    Insert,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    /// Single ASCII letter (lowercased).
    Alpha {
        ch: String,
    },
    /// ASCII digit 0..=9.
    Digit {
        value: u8,
    },
    /// Single ASCII punctuation character.
    Punctuation {
        ch: String,
    },
    /// Anything else; raw platform keycode for diagnostic.
    Other {
        raw: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TerminalKeyEvent {
    pub action: TerminalKeyAction,
    pub code: TerminalKeyCode,
    pub mods: TerminalKeyMods,
    /// Text the platform thinks this key generates (already with mod
    /// processing on iOS). Empty for non-printable keys.
    pub text: String,
    pub repeat: bool,
}

/// Bracket-paste-wrap `text` if `bracketed` is true, then convert CRLF
/// to LF so terminal apps don't see double newlines.
pub fn encode_text(text: &str, bracketed: bool) -> Vec<u8> {
    // Normalize newlines first.
    let normalized: String = text.replace("\r\n", "\n");
    if bracketed {
        let mut out = Vec::with_capacity(normalized.len() + 12);
        out.extend_from_slice(b"\x1b[200~");
        out.extend_from_slice(normalized.as_bytes());
        out.extend_from_slice(b"\x1b[201~");
        out
    } else {
        normalized.into_bytes()
    }
}

/// Byte sequence for an on-screen toolbar key (Esc, Tab, Ctrl-C, arrows,
/// etc) the renderer never sees as a real keypress. This is a stop-gap
/// for the on-screen accessory row — real keypresses from a hardware /
/// IME keyboard go through `TerminalRenderer.send_key_event` instead, so
/// Ghostty's full CSI/kitty translator decides.
pub fn synthesize_special_key(code: &TerminalKeyCode, mods: TerminalKeyMods) -> Vec<u8> {
    match code {
        TerminalKeyCode::Escape => b"\x1b".to_vec(),
        TerminalKeyCode::Tab => b"\t".to_vec(),
        TerminalKeyCode::Enter => b"\r".to_vec(),
        TerminalKeyCode::Backspace => b"\x7f".to_vec(),
        TerminalKeyCode::ArrowUp => b"\x1b[A".to_vec(),
        TerminalKeyCode::ArrowDown => b"\x1b[B".to_vec(),
        TerminalKeyCode::ArrowRight => b"\x1b[C".to_vec(),
        TerminalKeyCode::ArrowLeft => b"\x1b[D".to_vec(),
        TerminalKeyCode::Home => b"\x1b[H".to_vec(),
        TerminalKeyCode::End => b"\x1b[F".to_vec(),
        TerminalKeyCode::PageUp => b"\x1b[5~".to_vec(),
        TerminalKeyCode::PageDown => b"\x1b[6~".to_vec(),
        TerminalKeyCode::Delete => b"\x1b[3~".to_vec(),
        TerminalKeyCode::Insert => b"\x1b[2~".to_vec(),
        TerminalKeyCode::Space => b" ".to_vec(),
        TerminalKeyCode::F1 => b"\x1bOP".to_vec(),
        TerminalKeyCode::F2 => b"\x1bOQ".to_vec(),
        TerminalKeyCode::F3 => b"\x1bOR".to_vec(),
        TerminalKeyCode::F4 => b"\x1bOS".to_vec(),
        TerminalKeyCode::F5 => b"\x1b[15~".to_vec(),
        TerminalKeyCode::F6 => b"\x1b[17~".to_vec(),
        TerminalKeyCode::F7 => b"\x1b[18~".to_vec(),
        TerminalKeyCode::F8 => b"\x1b[19~".to_vec(),
        TerminalKeyCode::F9 => b"\x1b[20~".to_vec(),
        TerminalKeyCode::F10 => b"\x1b[21~".to_vec(),
        TerminalKeyCode::F11 => b"\x1b[23~".to_vec(),
        TerminalKeyCode::F12 => b"\x1b[24~".to_vec(),
        TerminalKeyCode::Alpha { ch } => {
            if mods.ctrl {
                // Ctrl-letter → control byte. Fall back to literal if not ASCII alpha.
                if let Some(c) = ch.chars().next() {
                    let cl = c.to_ascii_lowercase();
                    if cl.is_ascii_alphabetic() {
                        return vec![(cl as u8) - b'a' + 1];
                    }
                }
            }
            ch.as_bytes().to_vec()
        }
        TerminalKeyCode::Digit { value } => vec![b'0' + value.min(&9)],
        TerminalKeyCode::Punctuation { ch } => ch.as_bytes().to_vec(),
        TerminalKeyCode::Unidentified | TerminalKeyCode::Other { .. } => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pack_ghostty_matches_bit_layout() {
        assert_eq!(TerminalKeyMods::NONE.pack_ghostty(), 0);
        let all = TerminalKeyMods {
            shift: true,
            ctrl: true,
            alt: true,
            meta: true,
        };
        assert_eq!(all.pack_ghostty(), 0b1111);
        let ctrl = TerminalKeyMods {
            ctrl: true,
            ..TerminalKeyMods::NONE
        };
        assert_eq!(ctrl.pack_ghostty(), 0b0010);
    }

    #[test]
    fn paste_bracketing_wraps_and_normalizes_newlines() {
        let out = encode_text("hello\r\nworld", true);
        let s = String::from_utf8(out).unwrap();
        assert!(s.starts_with("\x1b[200~"));
        assert!(s.ends_with("\x1b[201~"));
        assert!(s.contains("hello\nworld"));
        assert!(!s.contains("\r\n"));
    }

    #[test]
    fn non_bracketed_paste_still_normalizes_newlines() {
        let out = encode_text("a\r\nb", false);
        assert_eq!(String::from_utf8(out).unwrap(), "a\nb");
    }

    #[test]
    fn synthesize_arrow_keys_emit_csi() {
        assert_eq!(
            synthesize_special_key(&TerminalKeyCode::ArrowUp, TerminalKeyMods::NONE),
            b"\x1b[A".to_vec()
        );
        assert_eq!(
            synthesize_special_key(&TerminalKeyCode::ArrowDown, TerminalKeyMods::NONE),
            b"\x1b[B".to_vec()
        );
    }

    #[test]
    fn synthesize_ctrl_letter_emits_control_byte() {
        let mods = TerminalKeyMods {
            ctrl: true,
            ..TerminalKeyMods::NONE
        };
        let bytes = synthesize_special_key(&TerminalKeyCode::Alpha { ch: "c".into() }, mods);
        assert_eq!(bytes, vec![0x03]);
        let bytes = synthesize_special_key(&TerminalKeyCode::Alpha { ch: "A".into() }, mods);
        // Uppercase still folds to lowercase for Ctrl-A.
        assert_eq!(bytes, vec![0x01]);
    }

    #[test]
    fn synthesize_function_keys_emit_xterm_sequences() {
        assert_eq!(
            synthesize_special_key(&TerminalKeyCode::F1, TerminalKeyMods::NONE),
            b"\x1bOP".to_vec()
        );
        assert_eq!(
            synthesize_special_key(&TerminalKeyCode::F5, TerminalKeyMods::NONE),
            b"\x1b[15~".to_vec()
        );
    }

    #[test]
    fn unidentified_keycode_emits_nothing() {
        assert!(
            synthesize_special_key(&TerminalKeyCode::Unidentified, TerminalKeyMods::NONE)
                .is_empty()
        );
    }
}
