//! Global cache of agent metadata sourced from alleycat probe
//! responses. Platforms (Swift / Kotlin) read from here when they need
//! to render an agent's label, icon, sort order, BETA badge, or branch
//! on capability flags.
//!
//! The store is keyed by the lowercase agent `name` (the same string
//! alleycat advertises and uses to route `Connect` requests). Multiple
//! servers may advertise the same agent name; the latest probe wins —
//! agents are expected to converge on identical metadata across hosts
//! built from the same alleycat version.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use crate::ffi::alleycat::{AppAgentCapabilities, AppAgentPresentation};

#[derive(Debug, Clone, uniffi::Record)]
pub struct AppAgentMetadata {
    pub name: String,
    pub display_name: String,
    pub presentation: Option<AppAgentPresentation>,
    pub capabilities: Option<AppAgentCapabilities>,
}

#[derive(Default)]
pub struct AgentMetadataStore {
    inner: RwLock<HashMap<String, AppAgentMetadata>>,
}

impl AgentMetadataStore {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Replace this agent's metadata. Called whenever a probe response
    /// carries fresh data. Older alleycat hosts that omit `presentation`
    /// / `capabilities` / `icon` still overwrite the entry — clients
    /// must tolerate partial metadata.
    pub fn upsert(&self, metadata: AppAgentMetadata) {
        let key = metadata.name.to_ascii_lowercase();
        let mut guard = self.inner.write().expect("agent metadata lock");
        guard.insert(key, metadata);
    }

    pub fn upsert_all<I>(&self, entries: I)
    where
        I: IntoIterator<Item = AppAgentMetadata>,
    {
        let mut guard = self.inner.write().expect("agent metadata lock");
        for metadata in entries {
            let key = metadata.name.to_ascii_lowercase();
            guard.insert(key, metadata);
        }
    }

    pub fn get(&self, name: &str) -> Option<AppAgentMetadata> {
        let key = name.to_ascii_lowercase();
        let guard = self.inner.read().expect("agent metadata lock");
        guard.get(&key).cloned()
    }

    /// All known agents in presentation-sort order. Agents without an
    /// explicit `sort_order` fall to the end, tie-broken by name.
    pub fn all_sorted(&self) -> Vec<AppAgentMetadata> {
        let guard = self.inner.read().expect("agent metadata lock");
        let mut out: Vec<AppAgentMetadata> = guard.values().cloned().collect();
        out.sort_by(|a, b| {
            let a_order = a
                .presentation
                .as_ref()
                .map(|p| p.sort_order)
                .unwrap_or(i32::MAX);
            let b_order = b
                .presentation
                .as_ref()
                .map(|p| p.sort_order)
                .unwrap_or(i32::MAX);
            a_order.cmp(&b_order).then_with(|| a.name.cmp(&b.name))
        });
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata(name: &str, sort_order: i32) -> AppAgentMetadata {
        AppAgentMetadata {
            name: name.to_owned(),
            display_name: name.to_owned(),
            presentation: Some(AppAgentPresentation {
                title: None,
                is_beta: false,
                sort_order,
                description: None,
                aliases: Vec::new(),
            }),
            capabilities: None,
        }
    }

    #[test]
    fn upsert_replaces_by_lowercased_name() {
        let store = AgentMetadataStore::new();
        store.upsert(metadata("Codex", 0));
        store.upsert(metadata("codex", 5));
        let fetched = store.get("CODEX").expect("present");
        assert_eq!(fetched.presentation.unwrap().sort_order, 5);
    }

    #[test]
    fn all_sorted_orders_by_sort_order_then_name() {
        let store = AgentMetadataStore::new();
        store.upsert(metadata("zeta", 1));
        store.upsert(metadata("alpha", 1));
        store.upsert(metadata("middle", 0));
        let sorted: Vec<String> = store.all_sorted().into_iter().map(|m| m.name).collect();
        assert_eq!(sorted, vec!["middle", "alpha", "zeta"]);
    }
}
