//! iOS cannot spawn the standalone code-mode executable. Use the same upstream
//! runtime and delegate in-process, with executable-code generation disabled.
use std::sync::Arc;

use codex_code_mode_runtime::{
    CodeModeSession, CodeModeSessionCellExecutionLimits, CodeModeSessionDelegate,
    CodeModeSessionProvider, CodeModeSessionProviderFuture, InProcessCodeModeSession, V8JitMode,
    initialize_v8,
};

pub(crate) struct MobileCodeModeProvider;

impl CodeModeSessionProvider for MobileCodeModeProvider {
    fn availability(&self) -> Result<(), String> {
        initialize_v8(V8JitMode::Disabled)
    }

    fn create_session<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
    ) -> CodeModeSessionProviderFuture<'a> {
        self.create_session_with_limits(delegate, CodeModeSessionCellExecutionLimits::default())
    }

    fn create_session_with_limits<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
        limits: CodeModeSessionCellExecutionLimits,
    ) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async move {
            // Upstream's in-process implementation explicitly clears heap limits.
            // Reject that request rather than silently claiming to enforce it.
            if limits.max_heap_size_bytes.is_some() {
                return Err("the mobile code-mode runtime does not support heap limits".into());
            }
            self.availability()?;
            Ok(Arc::new(InProcessCodeModeSession::with_delegate_and_limits(
                delegate, limits,
            )) as Arc<dyn CodeModeSession>)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use codex_code_mode_runtime::{
        ExecuteRequest, FunctionCallOutputContentItem, NoopCodeModeSessionDelegate, RuntimeResponse,
    };

    #[tokio::test]
    async fn jitless_provider_executes_cells_and_rejects_unenforced_limits() {
        let provider = MobileCodeModeProvider;
        let delegate = Arc::new(NoopCodeModeSessionDelegate);
        assert!(
            provider
                .create_session_with_limits(
                    delegate.clone(),
                    CodeModeSessionCellExecutionLimits {
                        max_heap_size_bytes: Some(1024),
                        ..Default::default()
                    }
                )
                .await
                .is_err()
        );
        let session = provider.create_session(delegate).await.unwrap();
        let response = session
            .execute(ExecuteRequest {
                tool_call_id: "mobile-jitless-test".into(),
                enabled_tools: vec![],
                source: "text(1 + 1)".into(),
                yield_time_ms: Some(10_000),
                max_output_tokens: Some(100),
            })
            .await
            .unwrap()
            .initial_response()
            .await
            .unwrap();
        let RuntimeResponse::Result {
            content_items,
            error_text,
            ..
        } = response
        else {
            panic!("cell did not complete: {response:?}");
        };
        assert_eq!(error_text, None);
        assert_eq!(
            content_items,
            vec![FunctionCallOutputContentItem::InputText { text: "2".into() }]
        );
        session.shutdown().await.unwrap();
    }
}
