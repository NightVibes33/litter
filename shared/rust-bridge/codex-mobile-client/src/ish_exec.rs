use std::collections::HashMap;
use std::io;
use std::path::Path;
use std::sync::OnceLock;

use async_trait::async_trait;
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use codex_exec_server::CopyOptions;
use codex_exec_server::CreateDirectoryOptions;
use codex_exec_server::ExecutorFileSystem;
use codex_exec_server::FileMetadata;
use codex_exec_server::FileSystemResult;
use codex_exec_server::FileSystemSandboxContext;
use codex_exec_server::ReadDirectoryEntry;
use codex_exec_server::RemoveOptions;
use codex_utils_absolute_path::AbsolutePathBuf;

use crate::mobile_exec_command::mobile_system_command;
use crate::shell_quoting::posix_quote;

static ISH_EXEC_HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

pub(crate) fn install() {
    ISH_EXEC_HOOK_INSTALLED.get_or_init(|| {
        codex_core::exec::set_ios_exec_hook(run_command);
        codex_core::exec::set_ios_streaming_exec_hook(run_command_streaming);
        crate::shell_preflight::install();
    });
}

pub(crate) fn run_command(
    argv: &[String],
    cwd: &Path,
    _env: &HashMap<String, String>,
    timeout_ms: Option<u64>,
) -> (i32, Vec<u8>) {
    // Run apply_patch in-process since iSH cannot exec the app binary.
    if is_apply_patch_invocation(argv) {
        return run_apply_patch_in_process(argv, cwd);
    }

    let cmd = mobile_system_command(argv);
    eprintln!("[ish-exec] run: {cmd} (cwd={})", cwd.display());

    let cwd_str = fakefs_cwd_string(cwd);
    let (code, output) = crate::ish_runtime::run(&cmd, Some(cwd_str.as_str()), timeout_ms);

    let preview = String::from_utf8_lossy(&output);
    let preview = if preview.len() > 200 {
        &preview[..200]
    } else {
        &preview
    };
    eprintln!(
        "[ish-exec] exit={code} output_len={} preview={preview}",
        output.len()
    );

    (code, output)
}

pub(crate) fn run_command_streaming(
    argv: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    timeout_ms: Option<u64>,
    on_output: codex_core::exec::IosExecOutputHandler,
) -> (i32, Vec<u8>) {
    // Run apply_patch in-process since iSH cannot exec the app binary.
    if is_apply_patch_invocation(argv) {
        let (code, output) = run_command(argv, cwd, env, timeout_ms);
        if !output.is_empty() {
            on_output(output.clone());
        }
        return (code, output);
    }

    let cmd = mobile_system_command(argv);
    eprintln!("[ish-exec] run(streaming): {cmd} (cwd={})", cwd.display());

    let cwd_str = fakefs_cwd_string(cwd);
    let (code, output) =
        crate::ish_runtime::run_streaming(&cmd, Some(cwd_str.as_str()), timeout_ms, |chunk| {
            if !chunk.is_empty() {
                on_output(chunk.to_vec());
            }
        });

    let preview = String::from_utf8_lossy(&output);
    let preview = if preview.len() > 200 {
        &preview[..200]
    } else {
        &preview
    };
    eprintln!(
        "[ish-exec] exit(streaming)={code} output_len={} preview={preview}",
        output.len()
    );

    (code, output)
}

fn fakefs_cwd_string(cwd: &Path) -> String {
    fakefs_cwd_path(cwd).to_string_lossy().into_owned()
}

fn fakefs_cwd_path(cwd: &Path) -> std::path::PathBuf {
    let cwd_string = cwd.to_string_lossy();
    if cwd_string.is_empty() || is_ios_host_path(&cwd_string) {
        return std::path::PathBuf::from(crate::ish_runtime::default_cwd());
    }
    cwd.to_path_buf()
}

fn is_ios_host_path(path: &str) -> bool {
    path.starts_with("/private/")
        || path.starts_with("/var/")
        || path.starts_with("/Users/")
        || path.starts_with("/Library/")
        || path.starts_with("/System/")
        || path.starts_with("/Applications/")
}

fn is_apply_patch_invocation(argv: &[String]) -> bool {
    argv.iter()
        .any(|arg| arg == codex_apply_patch::CODEX_CORE_APPLY_PATCH_ARG1)
}

fn run_apply_patch_in_process(argv: &[String], cwd: &Path) -> (i32, Vec<u8>) {
    let patch_arg = argv
        .iter()
        .skip_while(|arg| *arg != codex_apply_patch::CODEX_CORE_APPLY_PATCH_ARG1)
        .nth(1);
    let Some(patch) = patch_arg else {
        return (1, b"missing apply_patch payload\n".to_vec());
    };

    let fakefs_cwd = fakefs_cwd_path(cwd);
    eprintln!(
        "[ish-exec] apply_patch in-process (cwd={} fakefs_cwd={})",
        cwd.display(),
        fakefs_cwd.display()
    );
    let cwd_abs = match AbsolutePathBuf::from_absolute_path(&fakefs_cwd) {
        Ok(abs) => abs,
        Err(err) => {
            let msg = format!("invalid cwd for apply_patch: {err}\n");
            eprintln!("[ish-exec] apply_patch setup error: {err}");
            return (1, msg.into_bytes());
        }
    };
    let mut stdout_buf = Vec::new();
    let mut stderr_buf = Vec::new();
    let fs = IshFakefsFileSystem;
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(err) => {
            let msg = format!("build tokio runtime for apply_patch: {err}\n");
            eprintln!("[ish-exec] apply_patch runtime error: {err}");
            return (1, msg.into_bytes());
        }
    };
    let result = runtime.block_on(codex_apply_patch::apply_patch(
        patch,
        &cwd_abs,
        &mut stdout_buf,
        &mut stderr_buf,
        &fs,
        None,
    ));
    let code = match result {
        Ok(_) => 0,
        Err(err) => {
            eprintln!("[ish-exec] apply_patch error: {err}");
            if stderr_buf.is_empty() {
                stderr_buf = format!("{err}\n").into_bytes();
            }
            1
        }
    };
    let mut output = stdout_buf;
    output.extend_from_slice(&stderr_buf);
    eprintln!(
        "[ish-exec] apply_patch exit={code} output_len={}",
        output.len()
    );
    (code, output)
}

struct IshFakefsFileSystem;

#[async_trait]
impl ExecutorFileSystem for IshFakefsFileSystem {
    async fn read_file(
        &self,
        path: &AbsolutePathBuf,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<Vec<u8>> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let command = format!("base64 < {}", posix_quote(&path));
        let output = run_ish_fs_command("read_file", &command)?;
        let encoded = String::from_utf8_lossy(&output)
            .chars()
            .filter(|ch| !ch.is_ascii_whitespace())
            .collect::<String>();
        BASE64_STANDARD
            .decode(encoded.as_bytes())
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
    }

    async fn write_file(
        &self,
        path: &AbsolutePathBuf,
        contents: Vec<u8>,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let encoded = BASE64_STANDARD.encode(contents);
        let command = format!(
            "base64 -d > {} <<'LITTER_APPLY_PATCH_B64'\n{}\nLITTER_APPLY_PATCH_B64\n",
            posix_quote(&path),
            encoded
        );
        run_ish_fs_command("write_file", &command).map(|_| ())
    }

    async fn create_directory(
        &self,
        path: &AbsolutePathBuf,
        options: CreateDirectoryOptions,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let command = if options.recursive {
            format!("mkdir -p {}", posix_quote(&path))
        } else {
            format!("mkdir {}", posix_quote(&path))
        };
        run_ish_fs_command("create_directory", &command).map(|_| ())
    }

    async fn get_metadata(
        &self,
        path: &AbsolutePathBuf,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<FileMetadata> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let command = format!(
            "p={}; if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then exit 2; fi; \
             if [ -d \"$p\" ]; then echo is_directory=1; else echo is_directory=0; fi; \
             if [ -f \"$p\" ]; then echo is_file=1; else echo is_file=0; fi; \
             if [ -L \"$p\" ]; then echo is_symlink=1; else echo is_symlink=0; fi; \
             modified=$(stat -c %Y \"$p\" 2>/dev/null || echo 0); \
             case \"$modified\" in ''|*[!0-9]*) modified=0;; esac; \
             echo created_at_ms=0; echo modified_at_ms=$((modified * 1000))",
            posix_quote(&path)
        );
        let output = run_ish_fs_command("get_metadata", &command)?;
        let fields = parse_key_value_output(&output);
        Ok(FileMetadata {
            is_directory: fields.get("is_directory").is_some_and(|value| value == "1"),
            is_file: fields.get("is_file").is_some_and(|value| value == "1"),
            is_symlink: fields.get("is_symlink").is_some_and(|value| value == "1"),
            created_at_ms: fields
                .get("created_at_ms")
                .and_then(|value| value.parse().ok())
                .unwrap_or(0),
            modified_at_ms: fields
                .get("modified_at_ms")
                .and_then(|value| value.parse().ok())
                .unwrap_or(0),
        })
    }

    async fn read_directory(
        &self,
        path: &AbsolutePathBuf,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<Vec<ReadDirectoryEntry>> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let command = format!(
            "p={}; [ -d \"$p\" ] || exit 2; \
             for child in \"$p\"/* \"$p\"/.[!.]* \"$p\"/..?*; do \
               [ -e \"$child\" ] || [ -L \"$child\" ] || continue; \
               name=${{child##*/}}; d=0; f=0; \
               [ -d \"$child\" ] && d=1; [ -f \"$child\" ] && f=1; \
               printf '%s\t%s\t%s\n' \"$(printf '%s' \"$name\" | base64 | tr -d '\n')\" \"$d\" \"$f\"; \
             done",
            posix_quote(&path)
        );
        let output = run_ish_fs_command("read_directory", &command)?;
        let mut entries = Vec::new();
        for line in String::from_utf8_lossy(&output).lines() {
            let mut parts = line.split('\t');
            let Some(name_b64) = parts.next() else { continue };
            let Some(is_directory) = parts.next() else { continue };
            let Some(is_file) = parts.next() else { continue };
            let Ok(name_bytes) = BASE64_STANDARD.decode(name_b64.as_bytes()) else {
                continue;
            };
            entries.push(ReadDirectoryEntry {
                file_name: String::from_utf8_lossy(&name_bytes).into_owned(),
                is_directory: is_directory == "1",
                is_file: is_file == "1",
            });
        }
        Ok(entries)
    }

    async fn remove(
        &self,
        path: &AbsolutePathBuf,
        options: RemoveOptions,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        reject_sandbox_context(sandbox)?;
        let path = path_string(path);
        let missing_branch = if options.force { "exit 0" } else { "exit 2" };
        let command = if options.recursive {
            format!(
                "p={}; if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then {}; fi; rm -rf \"$p\"",
                posix_quote(&path),
                missing_branch
            )
        } else {
            format!(
                "p={}; if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then {}; fi; if [ -d \"$p\" ] && [ ! -L \"$p\" ]; then rmdir \"$p\"; else rm \"$p\"; fi",
                posix_quote(&path),
                missing_branch
            )
        };
        run_ish_fs_command("remove", &command).map(|_| ())
    }

    async fn copy(
        &self,
        source_path: &AbsolutePathBuf,
        destination_path: &AbsolutePathBuf,
        options: CopyOptions,
        sandbox: Option<&FileSystemSandboxContext>,
    ) -> FileSystemResult<()> {
        reject_sandbox_context(sandbox)?;
        let source_path = path_string(source_path);
        let destination_path = path_string(destination_path);
        let command = if options.recursive {
            format!(
                "cp -R {} {}",
                posix_quote(&source_path),
                posix_quote(&destination_path)
            )
        } else {
            format!(
                "cp {} {}",
                posix_quote(&source_path),
                posix_quote(&destination_path)
            )
        };
        run_ish_fs_command("copy", &command).map(|_| ())
    }
}

fn reject_sandbox_context(sandbox: Option<&FileSystemSandboxContext>) -> FileSystemResult<()> {
    if sandbox.is_some() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "path-outside-edit-workspace: iSH fakefs apply_patch does not support host sandbox contexts",
        ));
    }
    Ok(())
}

fn path_string(path: &AbsolutePathBuf) -> String {
    path.as_path().to_string_lossy().into_owned()
}

fn run_ish_fs_command(operation: &str, command: &str) -> FileSystemResult<Vec<u8>> {
    let (code, output) = crate::ish_runtime::run(command, None, Some(30_000));
    if code == 0 {
        return Ok(output);
    }
    Err(ish_fs_error(operation, code, &output))
}

fn ish_fs_error(operation: &str, code: i32, output: &[u8]) -> io::Error {
    if code == crate::ish_runtime::ISH_E_NOT_RUNNING {
        return io::Error::new(
            io::ErrorKind::NotFound,
            "patch-filesystem-not-mounted: iSH fakefs is not bootstrapped",
        );
    }
    let detail = String::from_utf8_lossy(output).trim().to_string();
    let message = if detail.is_empty() {
        format!("patch-filesystem-command-failed: {operation} exited {code}")
    } else {
        format!("patch-filesystem-command-failed: {operation} exited {code}: {detail}")
    };
    let kind = match code {
        2 => io::ErrorKind::NotFound,
        13 => io::ErrorKind::PermissionDenied,
        _ => io::ErrorKind::Other,
    };
    io::Error::new(kind, message)
}

fn parse_key_value_output(output: &[u8]) -> HashMap<String, String> {
    String::from_utf8_lossy(output)
        .lines()
        .filter_map(|line| {
            let (key, value) = line.split_once('=')?;
            Some((key.to_string(), value.to_string()))
        })
        .collect()
}
