use codex_app_server_protocol as upstream;

use crate::conversation::hydrate_thread_item;
use crate::conversation_uniffi::HydratedConversationItem;
use crate::types::ThreadInfo;

pub(crate) fn thread_info_from_upstream(thread: upstream::Thread) -> ThreadInfo {
    ThreadInfo::from(thread)
}

pub(crate) fn thread_info_from_upstream_status_change(
    thread_id: &str,
    status: upstream::ThreadStatus,
) -> ThreadInfo {
    ThreadInfo {
        id: thread_id.to_string(),
        title: None,
        model: None,
        status: status.into(),
        preview: None,
        cwd: None,
        path: None,
        model_provider: None,
        agent_nickname: None,
        agent_role: None,
        parent_thread_id: None,
        forked_from_id: None,
        agent_status: None,
        created_at: None,
        updated_at: None,
    }
}

/// Hydrate an upstream `ThreadItem` into a UI-ready `HydratedConversationItem`.
/// Pass `Some(turn_id)` for items that arrive via `ItemStarted` /
/// `ItemCompleted` notifications, which carry the turn id in the envelope.
/// Setting the turn id makes the live-event item match the turn-id-keyed
/// dedupe in `merge_paged_turns` so the same logical item from
/// `thread/turns/list` (which the upstream rollout-history layer may emit with
/// a synthesized `item-N` id rather than the live UUID) is not added twice.
pub(crate) fn conversation_item_from_upstream_with_turn(
    item: upstream::ThreadItem,
    turn_id: Option<&str>,
) -> Option<HydratedConversationItem> {
    hydrate_thread_item(&item, turn_id, None, &Default::default())
}
