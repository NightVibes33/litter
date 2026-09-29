#!/usr/bin/env python3
"""Install Alley Cat's mobile in-process Codex code-mode runtime.

The upstream Codex pin is kept exact. This patch is deliberately narrow:
desktop keeps the upstream standalone V8 code-mode host, while iOS/Android use
QuickJS in-process because a mobile app cannot rely on spawning the host binary.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

SERVICE_MOBILE = r'''use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

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
use codex_code_mode_protocol::DEFAULT_EXEC_YIELD_TIME_MS;
use rquickjs::AsyncContext;
use rquickjs::AsyncRuntime;
use rquickjs::CatchResultExt;
use rquickjs::Function;
use rquickjs::Promise;
use rquickjs::async_with;
use rquickjs::function::Async;
use serde_json::Value as JsonValue;
use tokio::sync::Notify;
use tokio::sync::watch;
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
globalThis.yield_control = () => __codexYield();
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
pub struct DisabledCodeModeSessionProvider;

impl CodeModeSessionProvider for DisabledCodeModeSessionProvider {
    fn availability(&self) -> Result<(), String> {
        Err("code-mode host is disabled".to_string())
    }

    fn create_session<'a>(
        &'a self,
        _delegate: Arc<dyn CodeModeSessionDelegate>,
    ) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async { Err("code-mode host is disabled".to_string()) })
    }
}

#[derive(Default)]
pub struct InProcessCodeModeSessionProvider;

impl CodeModeSessionProvider for InProcessCodeModeSessionProvider {
    fn availability(&self) -> Result<(), String> {
        Ok(())
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
            Ok(Arc::new(InProcessCodeModeSession::with_delegate_and_limits(
                delegate, limits,
            )) as Arc<dyn CodeModeSession>)
        })
    }
}

struct MobileCell {
    items: Mutex<Vec<FunctionCallOutputContentItem>>,
    cursor: Mutex<usize>,
    completion_rx: watch::Receiver<Option<Result<(), String>>>,
    yield_requested: AtomicBool,
    yield_notify: Notify,
    cancellation: CancellationToken,
}

impl MobileCell {
    fn drain_items(&self) -> Vec<FunctionCallOutputContentItem> {
        let items = self.items.lock().unwrap_or_else(|p| p.into_inner());
        let mut cursor = self.cursor.lock().unwrap_or_else(|p| p.into_inner());
        let start = (*cursor).min(items.len());
        let out = items[start..].to_vec();
        *cursor = items.len();
        out
    }
}

pub struct InProcessCodeModeSession {
    delegate: Arc<dyn CodeModeSessionDelegate>,
    store: Arc<Mutex<HashMap<String, JsonValue>>>,
    cells: Arc<Mutex<HashMap<CellId, Arc<MobileCell>>>>,
    next_cell_id: AtomicU64,
    limits: CodeModeSessionCellExecutionLimits,
}

impl InProcessCodeModeSession {
    pub fn new() -> Self {
        Self::with_delegate_and_limits(
            Arc::new(codex_code_mode_protocol::NoopCodeModeSessionDelegate),
            CodeModeSessionCellExecutionLimits::default(),
        )
    }

    pub fn with_delegate(delegate: Arc<dyn CodeModeSessionDelegate>) -> Self {
        Self::with_delegate_and_limits(delegate, CodeModeSessionCellExecutionLimits::default())
    }

    pub fn with_delegate_and_limits(
        delegate: Arc<dyn CodeModeSessionDelegate>,
        limits: CodeModeSessionCellExecutionLimits,
    ) -> Self {
        Self {
            delegate,
            store: Arc::new(Mutex::new(HashMap::new())),
            cells: Arc::new(Mutex::new(HashMap::new())),
            next_cell_id: AtomicU64::new(1),
            limits,
        }
    }

    fn bounded_yield_ms(&self, requested: Option<u64>) -> u64 {
        let requested = requested.unwrap_or(DEFAULT_EXEC_YIELD_TIME_MS);
        self.limits
            .max_yield_time_ms
            .map(|limit| requested.min(limit))
            .unwrap_or(requested)
    }
}

impl Default for InProcessCodeModeSession {
    fn default() -> Self {
        Self::new()
    }
}

impl CodeModeSession for InProcessCodeModeSession {
    fn execute<'a>(
        &'a self,
        request: ExecuteRequest,
    ) -> CodeModeSessionResultFuture<'a, StartedCell> {
        Box::pin(async move {
            let cell_id = CellId::new(format!(
                "mobile-{}",
                self.next_cell_id.fetch_add(1, Ordering::Relaxed)
            ));
            let yield_time_ms = self.bounded_yield_ms(request.yield_time_ms);
            let (completion_tx, completion_rx) = watch::channel(None);
            let cell = Arc::new(MobileCell {
                items: Mutex::new(Vec::new()),
                cursor: Mutex::new(0),
                completion_rx,
                yield_requested: AtomicBool::new(false),
                yield_notify: Notify::new(),
                cancellation: CancellationToken::new(),
            });
            self.cells
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .insert(cell_id.clone(), Arc::clone(&cell));

            let delegate = Arc::clone(&self.delegate);
            let store = Arc::clone(&self.store);
            let task_cell = Arc::clone(&cell);
            let task_cell_id = cell_id.clone();
            let heap_limit = self.limits.max_heap_size_bytes;
            tokio::spawn(async move {
                let result = run_javascript(
                    task_cell_id.clone(),
                    request,
                    delegate.clone(),
                    store,
                    Arc::clone(&task_cell),
                    heap_limit,
                )
                .await;
                delegate.cell_closed(&task_cell_id);
                completion_tx.send_replace(Some(result));
                task_cell.yield_notify.notify_waiters();
            });

            let cells = Arc::clone(&self.cells);
            let initial_cell = Arc::clone(&cell);
            let initial_id = cell_id.clone();
            Ok(StartedCell::from_future(cell_id, async move {
                observe_cell(cells, initial_id, initial_cell, yield_time_ms).await
            }))
        })
    }

    fn wait<'a>(&'a self, request: WaitRequest) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(async move {
            let cell = self
                .cells
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .get(&request.cell_id)
                .cloned();
            let Some(cell) = cell else {
                return Ok(WaitOutcome::MissingCell(missing_cell_response(request.cell_id)));
            };
            let response = observe_cell(
                Arc::clone(&self.cells),
                request.cell_id,
                cell,
                self.bounded_yield_ms(Some(request.yield_time_ms)),
            )
            .await?;
            Ok(WaitOutcome::LiveCell(response))
        })
    }

    fn terminate<'a>(&'a self, cell_id: CellId) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(async move {
            let cell = self
                .cells
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .remove(&cell_id);
            let Some(cell) = cell else {
                return Ok(WaitOutcome::MissingCell(missing_cell_response(cell_id)));
            };
            cell.cancellation.cancel();
            Ok(WaitOutcome::LiveCell(RuntimeResponse::Terminated {
                cell_id,
                content_items: cell.drain_items(),
                code_mode_host_duration: None,
            }))
        })
    }

    fn shutdown<'a>(&'a self) -> CodeModeSessionResultFuture<'a, ()> {
        Box::pin(async move {
            let cells = self
                .cells
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .drain()
                .map(|(_, cell)| cell)
                .collect::<Vec<_>>();
            for cell in cells {
                cell.cancellation.cancel();
            }
            Ok(())
        })
    }
}

async fn observe_cell(
    cells: Arc<Mutex<HashMap<CellId, Arc<MobileCell>>>>,
    cell_id: CellId,
    cell: Arc<MobileCell>,
    yield_time_ms: u64,
) -> Result<RuntimeResponse, String> {
    let mut completion_rx = cell.completion_rx.clone();

    loop {
        if let Some(result) = completion_rx.borrow().clone() {
            cells
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .remove(&cell_id);
            return Ok(RuntimeResponse::Result {
                cell_id,
                content_items: cell.drain_items(),
                error_text: result.err(),
                code_mode_host_duration: None,
            });
        }

        if cell.yield_requested.swap(false, Ordering::AcqRel) {
            return Ok(RuntimeResponse::Yielded {
                cell_id,
                content_items: cell.drain_items(),
                code_mode_host_duration: None,
            });
        }

        tokio::select! {
            changed = completion_rx.changed() => {
                if changed.is_err() {
                    cells.lock().unwrap_or_else(|p| p.into_inner()).remove(&cell_id);
                    return Err("mobile code-mode execution ended unexpectedly".to_string());
                }
            }
            _ = cell.yield_notify.notified() => {}
            _ = tokio::time::sleep(Duration::from_millis(yield_time_ms)) => {
                return Ok(RuntimeResponse::Yielded {
                    cell_id,
                    content_items: cell.drain_items(),
                    code_mode_host_duration: None,
                });
            }
        }
    }
}

async fn run_javascript(
    cell_id: CellId,
    request: ExecuteRequest,
    delegate: Arc<dyn CodeModeSessionDelegate>,
    store: Arc<Mutex<HashMap<String, JsonValue>>>,
    cell: Arc<MobileCell>,
    heap_limit: Option<usize>,
) -> Result<(), String> {
    let runtime = AsyncRuntime::new()
        .map_err(|error| format!("failed to create mobile JavaScript runtime: {error}"))?;
    runtime.set_max_stack_size(512 * 1024).await;
    if let Some(heap_limit) = heap_limit {
        runtime.set_memory_limit(heap_limit).await;
    }

    let context = AsyncContext::full(&runtime)
        .await
        .map_err(|error| format!("failed to create mobile JavaScript context: {error}"))?;

    let tool_metadata = request
        .enabled_tools
        .iter()
        .map(|tool| serde_json::json!({
            "name": tool.name,
            "description": tool.description,
        }))
        .collect::<Vec<_>>();
    let metadata_json = serde_json::to_string(&tool_metadata).map_err(|error| error.to_string())?;
    let source = request.source;
    let outer_call_id = request.tool_call_id;
    let cancellation = cell.cancellation.clone();

    async_with!(context => |ctx| {
        let globals = ctx.globals();

        globals.set("__codexText", Function::new(ctx.clone(), {
            let cell = Arc::clone(&cell);
            move |text: String| {
                cell.items
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .push(FunctionCallOutputContentItem::InputText { text });
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexImage", Function::new(ctx.clone(), {
            let cell = Arc::clone(&cell);
            move |encoded: String| {
                if let Some(item) = image_item(&encoded) {
                    cell.items.lock().unwrap_or_else(|p| p.into_inner()).push(item);
                }
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexAudio", Function::new(ctx.clone(), {
            let cell = Arc::clone(&cell);
            move |encoded: String| {
                if let Some(item) = audio_item(&encoded) {
                    cell.items.lock().unwrap_or_else(|p| p.into_inner()).push(item);
                }
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexGeneratedImage", Function::new(ctx.clone(), {
            let cell = Arc::clone(&cell);
            move |encoded: String| {
                for item in generated_image_items(&encoded) {
                    cell.items.lock().unwrap_or_else(|p| p.into_inner()).push(item);
                }
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexStore", Function::new(ctx.clone(), {
            let store = Arc::clone(&store);
            move |key: String, encoded: String| {
                if let Ok(value) = serde_json::from_str(&encoded) {
                    store.lock().unwrap_or_else(|p| p.into_inner()).insert(key, value);
                }
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexLoad", Function::new(ctx.clone(), {
            let store = Arc::clone(&store);
            move |key: String| -> Option<String> {
                store
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .get(&key)
                    .and_then(|value| serde_json::to_string(value).ok())
            }
        })).map_err(|error| error.to_string())?;

        globals.set("__codexSleep", Function::new(ctx.clone(), Async({
            let cancellation = cancellation.clone();
            move |milliseconds: f64| {
                let cancellation = cancellation.clone();
                async move {
                    tokio::select! {
                        _ = tokio::time::sleep(Duration::from_millis(milliseconds.max(0.0) as u64)) => {}
                        _ = cancellation.cancelled() => {}
                    }
                }
            }
        }))).map_err(|error| error.to_string())?;

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
                async move {
                    if text.trim().is_empty() {
                        return;
                    }
                    let _ = delegate
                        .notify(call_id, cell_id, text, cancellation)
                        .await;
                }
            }
        }))).map_err(|error| error.to_string())?;

        globals.set("__codexYield", Function::new(ctx.clone(), {
            let cell = Arc::clone(&cell);
            move || {
                cell.yield_requested.store(true, Ordering::Release);
                cell.yield_notify.notify_waiters();
            }
        })).map_err(|error| error.to_string())?;

        ctx.eval::<(), _>(BOOTSTRAP)
            .catch(&ctx)
            .map_err(|error| error.to_string())?;
        ctx.eval::<(), _>(format!("globalThis.ALL_TOOLS = {metadata_json};"))
            .catch(&ctx)
            .map_err(|error| error.to_string())?;

        for (index, tool) in request.enabled_tools.into_iter().enumerate() {
            let host_name = format!("__codexTool{index}");
            let js_name = serde_json::to_string(&tool.name).map_err(|error| error.to_string())?;
            let host_name_json =
                serde_json::to_string(&host_name).map_err(|error| error.to_string())?;

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
                        match delegate
                            .invoke_tool(
                                CodeModeNestedToolCall {
                                    cell_id,
                                    runtime_tool_call_id: format!(
                                        "mobile-tool-{}",
                                        NEXT_TOOL_ID.fetch_add(1, Ordering::Relaxed)
                                    ),
                                    tool_name,
                                    tool_kind,
                                    input,
                                },
                                cancellation,
                            )
                            .await
                        {
                            Ok(value) => serde_json::json!({ "ok": true, "value": value }).to_string(),
                            Err(error) => serde_json::json!({ "ok": false, "error": error }).to_string(),
                        }
                    }
                }
            }))).map_err(|error| error.to_string())?;

            let install = format!(
                r#"tools[{js_name}] = async input => {{ const raw = await globalThis[{host_name_json}](typeof input === "string" ? input : JSON.stringify(input ?? {{}})); const result = JSON.parse(raw); if (!result.ok) throw new Error(result.error); return result.value; }};"#
            );
            ctx.eval::<(), _>(install)
                .catch(&ctx)
                .map_err(|error| error.to_string())?;
        }

        let wrapped = format!(
            "(async () => {{ try {{\n{source}\n}} catch (error) {{ if (error && error.__codexExit) return; throw error; }} }})()"
        );
        let promise: Promise = ctx
            .eval(wrapped)
            .catch(&ctx)
            .map_err(|error| error.to_string())?;
        promise
            .into_future::<()>()
            .await
            .catch(&ctx)
            .map_err(|error| error.to_string())?;

        if cancellation.is_cancelled() {
            return Err("mobile code-mode execution was terminated".to_string());
        }

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
    } else {
        let url = if let Some(url) = value.get("image_url").and_then(JsonValue::as_str) {
            url.to_string()
        } else {
            content_data_url(value, "image")?
        };
        let detail = value.get("detail").and_then(JsonValue::as_str).or_else(|| {
            value
                .pointer("/_meta/codex~1imageDetail")
                .and_then(JsonValue::as_str)
        });
        (url, detail)
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
        content_data_url(&value, "audio")?
    };
    Some(FunctionCallOutputContentItem::InputAudio { audio_url })
}

fn generated_image_items(encoded: &str) -> Vec<FunctionCallOutputContentItem> {
    let Ok(value) = serde_json::from_str::<JsonValue>(encoded) else {
        return Vec::new();
    };
    let Some(image_url) = value.get("image_url").and_then(JsonValue::as_str) else {
        return Vec::new();
    };

    let mut items = vec![FunctionCallOutputContentItem::InputImage {
        image_url: image_url.to_string(),
        detail: None,
    }];
    if let Some(text) = value.get("output_hint").and_then(JsonValue::as_str) {
        items.push(FunctionCallOutputContentItem::InputText {
            text: text.to_string(),
        });
    }
    items
}

fn content_data_url(value: &JsonValue, expected_type: &str) -> Option<String> {
    if let Some(kind) = value.get("type").and_then(JsonValue::as_str)
        && kind != expected_type
    {
        return None;
    }
    let data = value.get("data").and_then(JsonValue::as_str)?;
    let mime = value
        .get("mimeType")
        .or_else(|| value.get("mime_type"))
        .and_then(JsonValue::as_str)?;
    Some(format!("data:{mime};base64,{data}"))
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
pub struct ProcessOwnedCodeModeSessionProvider {
    inner: InProcessCodeModeSessionProvider,
}

impl ProcessOwnedCodeModeSessionProvider {
    pub fn with_host_program(_host_program: PathBuf) -> Self {
        Self::default()
    }
}

impl CodeModeSessionProvider for ProcessOwnedCodeModeSessionProvider {
    fn availability(&self) -> Result<(), String> {
        self.inner.availability()
    }

    fn create_session<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
    ) -> CodeModeSessionProviderFuture<'a> {
        self.inner.create_session(delegate)
    }

    fn create_session_with_limits<'a>(
        &'a self,
        delegate: Arc<dyn CodeModeSessionDelegate>,
        limits: CodeModeSessionCellExecutionLimits,
    ) -> CodeModeSessionProviderFuture<'a> {
        self.inner.create_session_with_limits(delegate, limits)
    }
}

pub type ProcessOwnedCodeModeSession = InProcessCodeModeSession;
'''

def replace_once(path: Path, before: str, after: str, label: str) -> None:
    text = path.read_text()
    if after in text:
        return
    if before not in text:
        raise SystemExit(f"mobile code-mode patch drift: missing {label} in {path}")
    path.write_text(text.replace(before, after, 1))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("codex_root", nargs="?", default="shared/third_party/codex")
    args = parser.parse_args()
    root = Path(args.codex_root).resolve()

    workspace = root / "codex-rs/Cargo.toml"
    replace_once(
        workspace,
        'serde_json = "1"\nserde_path_to_error',
        'serde_json = "1"\nrquickjs = { version = "0.9.0", features = ["bindgen", "futures", "parallel"] }\nserde_path_to_error',
        "workspace rquickjs dependency",
    )

    code_mode_cargo = root / "codex-rs/code-mode/Cargo.toml"
    replace_once(
        code_mode_cargo,
        'uuid = { workspace = true, features = ["v4"] }\n\n[dev-dependencies]',
        'uuid = { workspace = true, features = ["v4"] }\n\n[target.\'cfg(any(target_os = "ios", target_os = "android"))\'.dependencies]\nrquickjs = { workspace = true }\n\n[dev-dependencies]',
        "mobile rquickjs dependency",
    )

    lib = root / "codex-rs/code-mode/src/lib.rs"
    expected = '''mod grpc_session;
mod remote_session;

pub use codex_code_mode_protocol::*;
pub use grpc_session::GrpcCodeModeSessionProvider;
pub use remote_session::DisabledCodeModeSessionProvider;
pub use remote_session::ProcessOwnedCodeModeSession;
pub use remote_session::ProcessOwnedCodeModeSessionProvider;
'''
    replacement = '''mod grpc_session;
#[cfg(not(any(target_os = "ios", target_os = "android")))]
mod remote_session;
#[cfg(any(target_os = "ios", target_os = "android"))]
mod service_mobile;

pub use codex_code_mode_protocol::*;
pub use grpc_session::GrpcCodeModeSessionProvider;
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use remote_session::DisabledCodeModeSessionProvider;
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use remote_session::ProcessOwnedCodeModeSession;
#[cfg(not(any(target_os = "ios", target_os = "android")))]
pub use remote_session::ProcessOwnedCodeModeSessionProvider;
#[cfg(any(target_os = "ios", target_os = "android"))]
pub use service_mobile::*;
'''
    if lib.read_text() != replacement:
        if lib.read_text() != expected:
            raise SystemExit("mobile code-mode patch drift: codex-rs/code-mode/src/lib.rs changed upstream")
        lib.write_text(replacement)

    service = root / "codex-rs/code-mode/src/service_mobile.rs"
    service.write_text(SERVICE_MOBILE)

    description = root / "codex-rs/code-mode-protocol/src/description.rs"
    replace_once(
        description,
        "- Evaluates the provided JavaScript code in a fresh V8 isolate as an async module.",
        "- Evaluates the provided JavaScript code in a fresh JavaScript runtime as an async module.",
        "runtime-neutral exec description",
    )

    # Hard failure if the mobile bridge ever regresses to a no-op/stub.
    service_text = service.read_text()
    required = (
        "globalThis.tools = Object.create(null);",
        "globalThis.ALL_TOOLS = ",
        "delegate.invoke_tool",
        "impl CodeModeSessionProvider for ProcessOwnedCodeModeSessionProvider",
        "impl CodeModeSessionProvider for InProcessCodeModeSessionProvider",
        "RuntimeResponse::Yielded",
        "FunctionCallOutputContentItem::InputAudio",
    )
    normalized_service_text = re.sub(r"\s+", "", service_text)
    missing = [
        marker for marker in required
        if re.sub(r"\s+", "", marker) not in normalized_service_text
    ]
    if missing:
        raise SystemExit(f"mobile code-mode bridge incomplete: missing {missing}")
    forbidden = (
        "code mode is unavailable on mobile",
        "exec is unavailable on mobile targets",
        "MOBILE_UNSUPPORTED_MESSAGE",
    )
    present = [marker for marker in forbidden if marker in service_text]
    if present:
        raise SystemExit(f"mobile code-mode bridge contains unsupported stub markers: {present}")

    print("Mobile Codex code mode patched for iOS/Android: QuickJS + nested tools + wait/yield/terminate")

if __name__ == "__main__":
    main()
