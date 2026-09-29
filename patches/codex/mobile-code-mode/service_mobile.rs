use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use codex_code_mode_protocol::CellId;
use codex_code_mode_protocol::CodeModeNestedToolCall;
use codex_code_mode_protocol::CodeModeSession;
use codex_code_mode_protocol::CodeModeSessionCellExecutionLimits;
use codex_code_mode_protocol::CodeModeSessionDelegate;
use codex_code_mode_protocol::CodeModeSessionProvider;
use codex_code_mode_protocol::CodeModeSessionProviderFuture;
use codex_code_mode_protocol::CodeModeSessionResultFuture;
use codex_code_mode_protocol::CodeModeToolKind;
use codex_code_mode_protocol::ExecuteRequest;
use codex_code_mode_protocol::FunctionCallOutputContentItem;
use codex_code_mode_protocol::ImageDetail;
use codex_code_mode_protocol::RuntimeResponse;
use codex_code_mode_protocol::StartedCell;
use codex_code_mode_protocol::WaitOutcome;
use codex_code_mode_protocol::WaitRequest;
use rquickjs::async_with;
use rquickjs::function::Async;
use rquickjs::{AsyncContext, AsyncRuntime, CatchResultExt, Function, Promise};
use serde_json::Value as JsonValue;
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

const BOOTSTRAP: &str = r#"
globalThis.tools = Object.create(null);
globalThis.__codexTimers = new Map();
globalThis.__codexTimerId = 0;
globalThis.text = value => __codexText(typeof value === "string" ? value : JSON.stringify(value) ?? String(value));
globalThis.image = (value, detail) => __codexImage(JSON.stringify({ value, detail }));
globalThis.audio = value => __codexAudio(JSON.stringify(value));
globalThis.generatedImage = value => __codexGeneratedImage(JSON.stringify(value));
globalThis.store = (key, value) => __codexStore(String(key), JSON.stringify(value));
globalThis.load = key => { const value = __codexLoad(String(key)); return value === null ? undefined : JSON.parse(value); };
globalThis.notify = value => __codexNotify(typeof value === "string" ? value : JSON.stringify(value) ?? String(value));
globalThis.exit = () => { throw { __codexExit: true }; };
globalThis.yield_control = async () => {};
globalThis.setTimeout = (callback, delay = 0) => {
  const id = ++__codexTimerId;
  __codexTimers.set(id, true);
  __codexSleep(Math.max(0, Number(delay) || 0)).then(() => {
    if (__codexTimers.delete(id)) callback();
  });
  return id;
};
globalThis.clearTimeout = id => { __codexTimers.delete(id); };
"#;

#[derive(Default)]
pub struct InProcessCodeModeSessionProvider;

impl CodeModeSessionProvider for InProcessCodeModeSessionProvider {
    fn create_session<'a>(&'a self, delegate: Arc<dyn CodeModeSessionDelegate>) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async move {
            Ok(Arc::new(InProcessCodeModeSession::with_delegate(delegate)) as Arc<dyn CodeModeSession>)
        })
    }

    fn create_session_with_limits<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
        _limits: CodeModeSessionCellExecutionLimits,
    ) -> CodeModeSessionProviderFuture<'a> {
        self.create_session(delegate)
    }
}

pub struct InProcessCodeModeSession {
    delegate: Arc<dyn CodeModeSessionDelegate>,
    store: Arc<Mutex<HashMap<String, JsonValue>>>,
    next_cell_id: AtomicU64,
}

impl InProcessCodeModeSession {
    pub fn new() -> Self {
        Self::with_delegate(Arc::new(codex_code_mode_protocol::NoopCodeModeSessionDelegate))
    }

    pub fn with_delegate(delegate: Arc<dyn CodeModeSessionDelegate>) -> Self {
        Self { delegate, store: Arc::new(Mutex::new(HashMap::new())), next_cell_id: AtomicU64::new(1) }
    }

    async fn run_cell(&self, cell_id: CellId, request: ExecuteRequest) -> RuntimeResponse {
        let outputs = Arc::new(Mutex::new(Vec::new()));
        let cancellation = CancellationToken::new();
        let result = run_javascript(
            cell_id.clone(),
            request,
            Arc::clone(&self.delegate),
            Arc::clone(&self.store),
            Arc::clone(&outputs),
            cancellation,
        ).await;
        self.delegate.cell_closed(&cell_id);
        RuntimeResponse::Result {
            cell_id,
            content_items: outputs.lock().unwrap_or_else(|p| p.into_inner()).clone(),
            error_text: result.err(),
            code_mode_host_duration: None,
        }
    }
}

impl Default for InProcessCodeModeSession {
    fn default() -> Self { Self::new() }
}

impl CodeModeSession for InProcessCodeModeSession {
    fn execute<'a>(&'a self, request: ExecuteRequest) -> CodeModeSessionResultFuture<'a, StartedCell> {
        Box::pin(async move {
            let cell_id = CellId::new(format!("mobile-{}", self.next_cell_id.fetch_add(1, Ordering::Relaxed)));
            let response = self.run_cell(cell_id.clone(), request).await;
            let (tx, rx) = oneshot::channel();
            let _ = tx.send(response);
            Ok(StartedCell::new(cell_id, rx))
        })
    }

    fn wait<'a>(&'a self, request: WaitRequest) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(async move { Ok(WaitOutcome::MissingCell(missing_cell_response(request.cell_id))) })
    }

    fn terminate<'a>(&'a self, cell_id: CellId) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(async move { Ok(WaitOutcome::MissingCell(missing_cell_response(cell_id))) })
    }

    fn shutdown<'a>(&'a self) -> CodeModeSessionResultFuture<'a, ()> {
        Box::pin(async { Ok(()) })
    }
}

async fn run_javascript(
    cell_id: CellId,
    request: ExecuteRequest,
    delegate: Arc<dyn CodeModeSessionDelegate>,
    store: Arc<Mutex<HashMap<String, JsonValue>>>,
    outputs: Arc<Mutex<Vec<FunctionCallOutputContentItem>>>,
    cancellation: CancellationToken,
) -> Result<(), String> {
    let runtime = AsyncRuntime::new().map_err(|e| format!("failed to create JavaScript runtime: {e}"))?;
    runtime.set_max_stack_size(512 * 1024).await;
    let context = AsyncContext::full(&runtime).await.map_err(|e| format!("failed to create JavaScript context: {e}"))?;
    let tool_metadata = request.enabled_tools.iter()
        .map(|tool| serde_json::json!({ "name": tool.name, "description": tool.description }))
        .collect::<Vec<_>>();
    let metadata_json = serde_json::to_string(&tool_metadata).map_err(|e| e.to_string())?;
    let source = request.source;
    let outer_call_id = request.tool_call_id;

    async_with!(context => |ctx| {
        let globals = ctx.globals();
        globals.set("__codexText", Function::new(ctx.clone(), {
            let outputs = Arc::clone(&outputs);
            move |text: String| outputs.lock().unwrap_or_else(|p| p.into_inner())
                .push(FunctionCallOutputContentItem::InputText { text })
        })).map_err(|e| e.to_string())?;

        globals.set("__codexImage", Function::new(ctx.clone(), {
            let outputs = Arc::clone(&outputs);
            move |encoded: String| if let Some(item) = image_item(&encoded) {
                outputs.lock().unwrap_or_else(|p| p.into_inner()).push(item)
            }
        })).map_err(|e| e.to_string())?;

        globals.set("__codexAudio", Function::new(ctx.clone(), {
            let outputs = Arc::clone(&outputs);
            move |encoded: String| if let Some(item) = audio_item(&encoded) {
                outputs.lock().unwrap_or_else(|p| p.into_inner()).push(item)
            }
        })).map_err(|e| e.to_string())?;

        globals.set("__codexGeneratedImage", Function::new(ctx.clone(), {
            let outputs = Arc::clone(&outputs);
            move |encoded: String| if let Some(item) = generated_image_item(&encoded) {
                outputs.lock().unwrap_or_else(|p| p.into_inner()).push(item)
            }
        })).map_err(|e| e.to_string())?;

        globals.set("__codexStore", Function::new(ctx.clone(), {
            let store = Arc::clone(&store);
            move |key: String, encoded: String| if let Ok(value) = serde_json::from_str(&encoded) {
                store.lock().unwrap_or_else(|p| p.into_inner()).insert(key, value);
            }
        })).map_err(|e| e.to_string())?;

        globals.set("__codexLoad", Function::new(ctx.clone(), {
            let store = Arc::clone(&store);
            move |key: String| -> Option<String> {
                store.lock().unwrap_or_else(|p| p.into_inner()).get(&key)
                    .and_then(|value| serde_json::to_string(value).ok())
            }
        })).map_err(|e| e.to_string())?;

        globals.set("__codexSleep", Function::new(ctx.clone(), Async(|milliseconds: f64| async move {
            tokio::time::sleep(std::time::Duration::from_millis(milliseconds.max(0.0) as u64)).await;
        }))).map_err(|e| e.to_string())?;

        globals.set("__codexNotify", Function::new(ctx.clone(), Async({
            let delegate = Arc::clone(&delegate);
            let cell_id = cell_id.clone();
            let cancellation = cancellation.clone();
            let outer_call_id = outer_call_id.clone();
            move |text: String| {
                let delegate = Arc::clone(&delegate);
                let cell_id = cell_id.clone();
                let cancellation = cancellation.clone();
                let call_id = outer_call_id.clone();
                async move { let _ = delegate.notify(call_id, cell_id, text, cancellation).await; }
            }
        }))).map_err(|e| e.to_string())?;

        ctx.eval::<(), _>(BOOTSTRAP).catch(&ctx).map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(format!("globalThis.ALL_TOOLS = {metadata_json};"))
            .catch(&ctx).map_err(|e| e.to_string())?;

        for (index, tool) in request.enabled_tools.into_iter().enumerate() {
            let host_name = format!("__codexTool{index}");
            let js_name = serde_json::to_string(&tool.name).map_err(|e| e.to_string())?;
            let host_name_json = serde_json::to_string(&host_name).map_err(|e| e.to_string())?;
            globals.set(host_name.as_str(), Function::new(ctx.clone(), Async({
                let delegate = Arc::clone(&delegate);
                let cell_id = cell_id.clone();
                let cancellation = cancellation.clone();
                let tool_name = tool.tool_name.clone();
                let tool_kind = tool.kind;
                move |encoded: String| {
                    let delegate = Arc::clone(&delegate);
                    let cell_id = cell_id.clone();
                    let cancellation = cancellation.clone();
                    let tool_name = tool_name.clone();
                    async move {
                        let input = match tool_kind {
                            CodeModeToolKind::Freeform => Some(JsonValue::String(encoded)),
                            CodeModeToolKind::Function => serde_json::from_str(&encoded).ok(),
                        };
                        match delegate.invoke_tool(
                            CodeModeNestedToolCall {
                                cell_id,
                                runtime_tool_call_id: format!("mobile-tool-{}", NEXT_TOOL_ID.fetch_add(1, Ordering::Relaxed)),
                                tool_name,
                                tool_kind,
                                input,
                            },
                            cancellation,
                        ).await {
                            Ok(value) => serde_json::json!({ "ok": true, "value": value }).to_string(),
                            Err(error) => serde_json::json!({ "ok": false, "error": error }).to_string(),
                        }
                    }
                }
            }))).map_err(|e| e.to_string())?;
            let install = format!(
                r#"tools[{js_name}] = async input => {{ const raw = await globalThis[{host_name_json}](typeof input === "string" ? input : JSON.stringify(input ?? {{}})); const result = JSON.parse(raw); if (!result.ok) throw new Error(result.error); return result.value; }};"#
            );
            ctx.eval::<(), _>(install).catch(&ctx).map_err(|e| e.to_string())?;
        }

        let wrapped = format!("(async () => {{ try {{\n{source}\n}} catch (error) {{ if (error && error.__codexExit) return; throw error; }} }})()");
        let promise: Promise = ctx.eval(wrapped).catch(&ctx).map_err(|e| e.to_string())?;
        promise.into_future::<()>().await.catch(&ctx).map_err(|e| e.to_string())?;
        Ok::<(), String>(())
    }).await
}

static NEXT_TOOL_ID: AtomicU64 = AtomicU64::new(1);

fn image_item(encoded: &str) -> Option<FunctionCallOutputContentItem> {
    let payload: JsonValue = serde_json::from_str(encoded).ok()?;
    let value = payload.get("value")?;
    let explicit_detail = payload.get("detail").and_then(JsonValue::as_str);
    let (image_url, embedded_detail) = if let Some(url) = value.as_str() {
        (url.to_string(), None)
    } else if let Some(url) = value.get("image_url").and_then(JsonValue::as_str) {
        (url.to_string(), value.get("detail").and_then(JsonValue::as_str)
            .or_else(|| value.pointer("/_meta/codex~1imageDetail").and_then(JsonValue::as_str)))
    } else {
        let data = value.get("data").and_then(JsonValue::as_str)?;
        let mime = value.get("mimeType").and_then(JsonValue::as_str).unwrap_or("image/png");
        (format!("data:{mime};base64,{data}"), None)
    };
    Some(FunctionCallOutputContentItem::InputImage {
        image_url,
        detail: parse_detail(explicit_detail.or(embedded_detail)),
    })
}

fn audio_item(encoded: &str) -> Option<FunctionCallOutputContentItem> {
    let value: JsonValue = serde_json::from_str(encoded).ok()?;
    let audio_url = if let Some(url) = value.as_str() {
        url.to_string()
    } else if let Some(url) = value.get("audio_url").and_then(JsonValue::as_str) {
        url.to_string()
    } else {
        let data = value.get("data").and_then(JsonValue::as_str)?;
        let mime = value.get("mimeType").and_then(JsonValue::as_str).unwrap_or("audio/wav");
        format!("data:{mime};base64,{data}")
    };
    Some(FunctionCallOutputContentItem::InputAudio { audio_url })
}

fn generated_image_item(encoded: &str) -> Option<FunctionCallOutputContentItem> {
    let value: JsonValue = serde_json::from_str(encoded).ok()?;
    let image_url = value.get("image_url")?.as_str()?.to_string();
    Some(FunctionCallOutputContentItem::InputImage { image_url, detail: None })
}

fn parse_detail(value: Option<&str>) -> Option<ImageDetail> {
    match value {
        Some("auto") => Some(ImageDetail::Auto),
        Some("low") => Some(ImageDetail::Low),
        Some("high") => Some(ImageDetail::High),
        Some("original") => Some(ImageDetail::Original),
        _ => None,
    }
}

fn missing_cell_response(cell_id: CellId) -> RuntimeResponse {
    RuntimeResponse::Result {
        error_text: Some(format!("exec cell {cell_id} not found")),
        cell_id,
        content_items: Vec::new(),
        code_mode_host_duration: None,
    }
}

#[derive(Default)]
pub struct ProcessOwnedCodeModeSessionProvider;

impl ProcessOwnedCodeModeSessionProvider {
    pub fn with_host_program(_host_program: PathBuf) -> Self { Self }
}

impl CodeModeSessionProvider for ProcessOwnedCodeModeSessionProvider {
    fn create_session<'a>(&'a self, delegate: Arc<dyn CodeModeSessionDelegate>) -> CodeModeSessionProviderFuture<'a> {
        InProcessCodeModeSessionProvider.create_session(delegate)
    }

    fn create_session_with_limits<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
        limits: CodeModeSessionCellExecutionLimits,
    ) -> CodeModeSessionProviderFuture<'a> {
        InProcessCodeModeSessionProvider.create_session_with_limits(delegate, limits)
    }
}

pub type ProcessOwnedCodeModeSession = InProcessCodeModeSession;

#[derive(Default)]
pub struct DisabledCodeModeSessionProvider;

impl CodeModeSessionProvider for DisabledCodeModeSessionProvider {
    fn availability(&self) -> Result<(), String> { Err("code-mode host is disabled".to_string()) }

    fn create_session<'a>(&'a self, _delegate: Arc<dyn CodeModeSessionDelegate>) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async { Err("code-mode host is disabled".to_string()) })
    }
}
