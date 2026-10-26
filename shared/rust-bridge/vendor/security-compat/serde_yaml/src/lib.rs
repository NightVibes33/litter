//! Preserve the legacy YAML API with the maintained serde_yaml_bw implementation.
//! Its parser uses granit; its emitter uses the maintained libyaml-norway fork.
pub use serde_yaml_bw::*;
