//! Legacy parser entrypoints backed by maintained `toml`.
pub use toml::de::Error;
pub use toml::{from_str, to_string, to_string_pretty};
