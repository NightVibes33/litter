//! Android proot bootstrap and PTY spawning for the local Alpine terminal.

use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::path::Component;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};

use flate2::read::GzDecoder;
use portable_pty::{Child, ChildKiller, CommandBuilder, MasterPty, PtySize, native_pty_system};
use rusqlite::Connection;

use crate::proot_types::ProotBootstrapError;

const PROOT_BINARY_NAME: &str = "libproot.so";
const PROOT_LOADER_NAME: &str = "libproot_loader.so";
const ROOTFS_DIR_NAME: &str = "alpine-rootfs";
const PROOT_TMP_DIR_NAME: &str = "proot-tmp";
const ROOTFS_READY_MARKER: &str = ".litter-proot-ready-v2";
const S_IFMT: u32 = 0o170000;
const S_IFDIR: u32 = 0o040000;
const S_IFREG: u32 = 0o100000;
const S_IFLNK: u32 = 0o120000;

static INSTANCE: OnceLock<Arc<ProotInstance>> = OnceLock::new();

pub(crate) fn instance() -> Option<&'static Arc<ProotInstance>> {
    INSTANCE.get()
}

pub fn bootstrap(
    proot_lib_dir: &Path,
    rootfs_archive: &Path,
    data_dir: &Path,
) -> Result<(), ProotBootstrapError> {
    if INSTANCE.get().is_some() {
        return Ok(());
    }

    let proot_bin = proot_lib_dir.join(PROOT_BINARY_NAME);
    if !proot_bin.is_file() {
        return Err(ProotBootstrapError::MissingArtifact {
            detail: format!("missing proot executable at {}", proot_bin.display()),
        });
    }
    make_executable(&proot_bin)?;

    let proot_loader = proot_lib_dir.join(PROOT_LOADER_NAME);
    if !proot_loader.is_file() {
        return Err(ProotBootstrapError::MissingArtifact {
            detail: format!("missing proot loader at {}", proot_loader.display()),
        });
    }
    make_executable(&proot_loader)?;

    let rootfs = ensure_rootfs(rootfs_archive, data_dir)?;
    let tmp_dir = ensure_proot_tmp_dir(data_dir)?;
    let instance = Arc::new(ProotInstance {
        proot_bin,
        proot_loader,
        rootfs,
        tmp_dir,
    });
    instance.probe()?;
    INSTANCE
        .set(instance)
        .map_err(|_| ProotBootstrapError::AlreadyBootstrapped)
}

pub(crate) struct ProotInstance {
    proot_bin: PathBuf,
    proot_loader: PathBuf,
    rootfs: PathBuf,
    tmp_dir: PathBuf,
}

impl ProotInstance {
    pub(crate) fn spawn_pty(
        &self,
        argv: &[String],
        env: &HashMap<String, String>,
        cwd: &Path,
        cols: u16,
        rows: u16,
    ) -> Result<SpawnedProotPty, ProotRuntimeError> {
        if cols == 0 || rows == 0 {
            return Err(ProotRuntimeError::InvalidSize { cols, rows });
        }
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|error| ProotRuntimeError::Pty {
                detail: format!("opening PTY pair: {error}"),
            })?;

        let mut cmd = CommandBuilder::new(self.proot_bin.to_string_lossy().into_owned());
        cmd.args(self.proot_args(cwd, argv));
        cmd.cwd(self.tmp_dir.as_os_str());
        for (key, value) in env {
            cmd.env(key, value);
        }
        cmd.env("PROOT_TMP_DIR", self.tmp_dir.to_string_lossy().into_owned());
        cmd.env(
            "PROOT_LOADER",
            self.proot_loader.to_string_lossy().into_owned(),
        );

        let reader = pair
            .master
            .try_clone_reader()
            .map_err(|error| ProotRuntimeError::Pty {
                detail: format!("cloning PTY reader: {error}"),
            })?;
        let writer = pair
            .master
            .take_writer()
            .map_err(|error| ProotRuntimeError::Pty {
                detail: format!("taking PTY writer: {error}"),
            })?;
        let child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|error| classify_spawn_error(error.to_string()))?;
        let killer = child.clone_killer();
        Ok(SpawnedProotPty {
            pty: Arc::new(ProotPty {
                writer: Mutex::new(writer),
                master: Mutex::new(pair.master),
                killer: Mutex::new(killer),
            }),
            reader,
            child,
        })
    }

    fn probe(&self) -> Result<(), ProotBootstrapError> {
        let output = Command::new(&self.proot_bin)
            .args(self.proot_args(Path::new("/root"), &[
                "/bin/sh".to_string(),
                "-lc".to_string(),
                "true".to_string(),
            ]))
            .env("PROOT_TMP_DIR", self.tmp_dir.to_string_lossy().into_owned())
            .env(
                "PROOT_LOADER",
                self.proot_loader.to_string_lossy().into_owned(),
            )
            .output()
            .map_err(|error| ProotBootstrapError::Io {
                detail: format!("running proot sentinel: {error}"),
            })?;
        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let detail = format!(
            "proot sentinel exited with status {:?}; stdout={stdout}; stderr={stderr}",
            output.status.code()
        );
        if is_ptrace_denied_text(&detail) {
            return Err(ProotBootstrapError::PtraceDenied { detail });
        }
        Err(ProotBootstrapError::Io { detail })
    }

    fn proot_args(&self, cwd: &Path, argv: &[String]) -> Vec<String> {
        let mut args = vec![
            "--kill-on-exit".to_string(),
            "-0".to_string(),
            "-r".to_string(),
            self.rootfs.to_string_lossy().into_owned(),
            "-b".to_string(),
            "/dev".to_string(),
            "-b".to_string(),
            "/proc".to_string(),
            "-b".to_string(),
            "/sys".to_string(),
            "-w".to_string(),
            cwd.to_string_lossy().into_owned(),
        ];
        args.extend(argv.iter().cloned());
        args
    }
}

pub(crate) struct SpawnedProotPty {
    pub(crate) pty: Arc<ProotPty>,
    pub(crate) reader: Box<dyn Read + Send>,
    pub(crate) child: Box<dyn Child + Send + Sync>,
}

pub(crate) struct ProotPty {
    writer: Mutex<Box<dyn Write + Send>>,
    master: Mutex<Box<dyn MasterPty + Send>>,
    killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
}

impl ProotPty {
    pub(crate) fn write(&self, data: &[u8]) -> Result<(), ProotRuntimeError> {
        let mut writer = self
            .writer
            .lock()
            .map_err(|_| ProotRuntimeError::Poisoned("writer"))?;
        writer
            .write_all(data)
            .map_err(|error| ProotRuntimeError::Pty {
                detail: format!("writing PTY input: {error}"),
            })?;
        writer.flush().map_err(|error| ProotRuntimeError::Pty {
            detail: format!("flushing PTY input: {error}"),
        })
    }

    pub(crate) fn resize(&self, cols: u16, rows: u16) -> Result<(), ProotRuntimeError> {
        if cols == 0 || rows == 0 {
            return Err(ProotRuntimeError::InvalidSize { cols, rows });
        }
        let master = self
            .master
            .lock()
            .map_err(|_| ProotRuntimeError::Poisoned("master"))?;
        master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|error| ProotRuntimeError::Pty {
                detail: format!("resizing PTY: {error}"),
            })
    }

    pub(crate) fn kill(&self) -> Result<(), ProotRuntimeError> {
        let mut killer = self
            .killer
            .lock()
            .map_err(|_| ProotRuntimeError::Poisoned("killer"))?;
        killer.kill().map_err(|error| ProotRuntimeError::Pty {
            detail: format!("killing proot child: {error}"),
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum ProotRuntimeError {
    #[error("invalid PTY size {cols}x{rows}")]
    InvalidSize { cols: u16, rows: u16 },
    #[error("PTY error: {detail}")]
    Pty { detail: String },
    #[error("spawn error: {detail}")]
    Spawn { detail: String },
    #[error("ptrace denied: {detail}")]
    PtraceDenied { detail: String },
    #[error("mutex poisoned: {0}")]
    Poisoned(&'static str),
}

fn ensure_rootfs(rootfs_archive: &Path, data_dir: &Path) -> Result<PathBuf, ProotBootstrapError> {
    if !rootfs_archive.is_file() {
        return Err(ProotBootstrapError::MissingArtifact {
            detail: format!(
                "missing Alpine rootfs archive at {}",
                rootfs_archive.display()
            ),
        });
    }
    let rootfs_identity = rootfs_identity(rootfs_archive)?;
    fs::create_dir_all(data_dir).map_err(|error| ProotBootstrapError::Io {
        detail: format!("creating data dir {}: {error}", data_dir.display()),
    })?;

    let extract_dir = data_dir.join(ROOTFS_DIR_NAME);
    let marker = extract_dir.join(ROOTFS_READY_MARKER);
    if marker.is_file()
        && fs::read_to_string(&marker)
            .ok()
            .as_deref()
            .is_some_and(|stored| stored == rootfs_identity)
    {
        return detect_rootfs_dir(&extract_dir);
    }

    let tmp_dir = data_dir.join(format!("{ROOTFS_DIR_NAME}.tmp"));
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir).map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "removing stale rootfs temp dir {}: {error}",
                tmp_dir.display()
            ),
        })?;
    }
    fs::create_dir_all(&tmp_dir).map_err(|error| ProotBootstrapError::Io {
        detail: format!("creating rootfs temp dir {}: {error}", tmp_dir.display()),
    })?;
    extract_tar_gz(rootfs_archive, &tmp_dir)?;

    if extract_dir.exists() {
        fs::remove_dir_all(&extract_dir).map_err(|error| ProotBootstrapError::Io {
            detail: format!("removing old rootfs dir {}: {error}", extract_dir.display()),
        })?;
    }
    fs::rename(&tmp_dir, &extract_dir).map_err(|error| ProotBootstrapError::Io {
        detail: format!(
            "promoting rootfs dir {} -> {}: {error}",
            tmp_dir.display(),
            extract_dir.display()
        ),
    })?;
    let rootfs = detect_rootfs_dir(&extract_dir)?;
    repair_fakefs_metadata(&extract_dir, &rootfs)?;
    fs::write(&marker, rootfs_identity.as_bytes()).map_err(|error| ProotBootstrapError::Io {
        detail: format!("writing rootfs marker {}: {error}", marker.display()),
    })?;
    Ok(rootfs)
}

fn rootfs_identity(rootfs_archive: &Path) -> Result<String, ProotBootstrapError> {
    let version_path = rootfs_archive.with_file_name("alpine-fs.version");
    if version_path.is_file() {
        let value = fs::read_to_string(&version_path).map_err(|error| ProotBootstrapError::Io {
            detail: format!("reading rootfs version {}: {error}", version_path.display()),
        })?;
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            return Ok(format!("version:{trimmed}\n"));
        }
    }

    let metadata = fs::metadata(rootfs_archive).map_err(|error| ProotBootstrapError::Io {
        detail: format!(
            "reading rootfs archive metadata {}: {error}",
            rootfs_archive.display()
        ),
    })?;
    let modified_millis = metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    Ok(format!("archive:{}:{modified_millis}\n", metadata.len()))
}

fn ensure_proot_tmp_dir(data_dir: &Path) -> Result<PathBuf, ProotBootstrapError> {
    let tmp_dir = data_dir.join(PROOT_TMP_DIR_NAME);
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir).map_err(|error| ProotBootstrapError::Io {
            detail: format!("removing proot temp dir {}: {error}", tmp_dir.display()),
        })?;
    }
    fs::create_dir_all(&tmp_dir).map_err(|error| ProotBootstrapError::Io {
        detail: format!("creating proot temp dir {}: {error}", tmp_dir.display()),
    })?;
    Ok(tmp_dir)
}

fn extract_tar_gz(archive_path: &Path, dest: &Path) -> Result<(), ProotBootstrapError> {
    let file = fs::File::open(archive_path).map_err(|error| ProotBootstrapError::Io {
        detail: format!("opening archive {}: {error}", archive_path.display()),
    })?;
    let decoder = GzDecoder::new(file);
    let mut archive = tar::Archive::new(decoder);
    let entries = archive
        .entries()
        .map_err(|error| ProotBootstrapError::Archive {
            detail: format!("reading archive {}: {error}", archive_path.display()),
        })?;
    for entry in entries {
        let mut entry = entry.map_err(|error| ProotBootstrapError::Archive {
            detail: format!("reading archive entry: {error}"),
        })?;
        let unpacked = entry
            .unpack_in(dest)
            .map_err(|error| ProotBootstrapError::Archive {
                detail: format!("unpacking archive entry into {}: {error}", dest.display()),
            })?;
        if !unpacked {
            return Err(ProotBootstrapError::Archive {
                detail: "archive entry attempted to unpack outside the rootfs directory"
                    .to_string(),
            });
        }
    }
    Ok(())
}

fn detect_rootfs_dir(extract_dir: &Path) -> Result<PathBuf, ProotBootstrapError> {
    for candidate in [extract_dir.join("fs/data"), extract_dir.to_path_buf()] {
        if fs::symlink_metadata(candidate.join("bin/sh")).is_ok() {
            return Ok(candidate);
        }
    }
    Err(ProotBootstrapError::Archive {
        detail: format!(
            "extracted rootfs under {} does not contain bin/sh",
            extract_dir.display()
        ),
    })
}

fn repair_fakefs_metadata(extract_dir: &Path, rootfs: &Path) -> Result<(), ProotBootstrapError> {
    let metadata_db = extract_dir.join("fs/meta.db");
    if !metadata_db.is_file() {
        return Ok(());
    }

    let connection = Connection::open(&metadata_db).map_err(|error| ProotBootstrapError::Io {
        detail: format!("opening fakefs metadata {}: {error}", metadata_db.display()),
    })?;
    let mut statement = connection
        .prepare(
            "select paths.path, stats.stat \
             from paths join stats on paths.inode = stats.inode",
        )
        .map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "preparing fakefs metadata query {}: {error}",
                metadata_db.display()
            ),
        })?;
    let entries = statement
        .query_map([], |row| {
            let path: Vec<u8> = row.get(0)?;
            let stat: Vec<u8> = row.get(1)?;
            Ok((path, stat))
        })
        .map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "querying fakefs metadata {}: {error}",
                metadata_db.display()
            ),
        })?;

    for entry in entries {
        let (path, stat) = entry.map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "reading fakefs metadata row {}: {error}",
                metadata_db.display()
            ),
        })?;
        restore_fakefs_entry(rootfs, &path, &stat)?;
    }
    Ok(())
}

fn restore_fakefs_entry(
    rootfs: &Path,
    path: &[u8],
    stat: &[u8],
) -> Result<(), ProotBootstrapError> {
    let Some(mode) = fakefs_mode(stat) else {
        return Ok(());
    };
    let Some(relative_path) = fakefs_relative_path(path)? else {
        return Ok(());
    };
    let host_path = rootfs.join(relative_path);
    match mode & S_IFMT {
        S_IFLNK => restore_fakefs_symlink(&host_path),
        S_IFREG | S_IFDIR => restore_fakefs_mode(&host_path, mode),
        _ => Ok(()),
    }
}

fn fakefs_mode(stat: &[u8]) -> Option<u32> {
    let mode = stat.get(0..4)?;
    Some(u32::from_le_bytes([mode[0], mode[1], mode[2], mode[3]]))
}

fn fakefs_relative_path(path: &[u8]) -> Result<Option<PathBuf>, ProotBootstrapError> {
    if path.is_empty() || path == b"/" {
        return Ok(Some(PathBuf::new()));
    }
    let Some(relative) = path.strip_prefix(b"/") else {
        return Err(ProotBootstrapError::Archive {
            detail: "fakefs metadata path is not absolute".to_string(),
        });
    };
    if relative.is_empty() {
        return Ok(Some(PathBuf::new()));
    }

    #[cfg(unix)]
    let relative_path = {
        use std::ffi::OsString;
        use std::os::unix::ffi::OsStringExt;

        PathBuf::from(OsString::from_vec(relative.to_vec()))
    };
    #[cfg(not(unix))]
    let relative_path = PathBuf::from(String::from_utf8_lossy(relative).into_owned());

    for component in relative_path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            _ => {
                return Err(ProotBootstrapError::Archive {
                    detail: "fakefs metadata path escapes the rootfs".to_string(),
                });
            }
        }
    }
    Ok(Some(relative_path))
}

fn restore_fakefs_symlink(path: &Path) -> Result<(), ProotBootstrapError> {
    #[cfg(unix)]
    {
        use std::ffi::OsString;
        use std::io::ErrorKind;
        use std::os::unix::ffi::OsStringExt;
        use std::os::unix::fs::symlink;

        let target = match fs::read(path) {
            Ok(target) if !target.is_empty() => target,
            Ok(_) => return Ok(()),
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(()),
            Err(error) => {
                return Err(ProotBootstrapError::Io {
                    detail: format!("reading fakefs symlink {}: {error}", path.display()),
                });
            }
        };

        let metadata = fs::symlink_metadata(path).map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "reading fakefs symlink metadata {}: {error}",
                path.display()
            ),
        })?;
        if metadata.file_type().is_dir() {
            fs::remove_dir(path).map_err(|error| ProotBootstrapError::Io {
                detail: format!(
                    "removing fakefs symlink directory {}: {error}",
                    path.display()
                ),
            })?;
        } else {
            fs::remove_file(path).map_err(|error| ProotBootstrapError::Io {
                detail: format!("removing fakefs symlink file {}: {error}", path.display()),
            })?;
        }

        let target_path = PathBuf::from(OsString::from_vec(target));
        symlink(&target_path, path).map_err(|error| ProotBootstrapError::Io {
            detail: format!(
                "creating fakefs symlink {} -> {}: {error}",
                path.display(),
                target_path.display()
            ),
        })?;
    }
    Ok(())
}

fn restore_fakefs_mode(path: &Path, mode: u32) -> Result<(), ProotBootstrapError> {
    #[cfg(unix)]
    {
        use std::io::ErrorKind;
        use std::os::unix::fs::PermissionsExt;

        let metadata = match fs::symlink_metadata(path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(()),
            Err(error) => {
                return Err(ProotBootstrapError::Io {
                    detail: format!("reading fakefs mode metadata {}: {error}", path.display()),
                });
            }
        };
        if metadata.file_type().is_symlink() {
            return Ok(());
        }
        let permissions = fs::Permissions::from_mode(mode & 0o7777);
        fs::set_permissions(path, permissions).map_err(|error| ProotBootstrapError::Io {
            detail: format!("restoring fakefs mode {}: {error}", path.display()),
        })?;
    }
    Ok(())
}

fn make_executable(path: &Path) -> Result<(), ProotBootstrapError> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = fs::metadata(path).map_err(|error| ProotBootstrapError::Io {
            detail: format!("reading proot metadata {}: {error}", path.display()),
        })?;
        let permissions = metadata.permissions();
        if permissions.mode() & 0o111 != 0 {
            return Ok(());
        }

        let mut permissions = permissions;
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).map_err(|error| ProotBootstrapError::Io {
            detail: format!("marking proot executable {}: {error}", path.display()),
        })?;
    }
    Ok(())
}

fn classify_spawn_error(detail: String) -> ProotRuntimeError {
    if is_ptrace_denied_text(&detail) {
        return ProotRuntimeError::PtraceDenied { detail };
    }
    ProotRuntimeError::Spawn { detail }
}

fn is_ptrace_denied_text(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    lower.contains("ptrace")
        && (lower.contains("permission denied")
            || lower.contains("operation not permitted")
            || lower.contains("not permitted"))
}
