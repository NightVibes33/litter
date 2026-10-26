use super::RemoteShell;
use crate::shell_quoting::{posix_quote, powershell_quote};
use base64::Engine;

pub(crate) fn attachment_name(name: &str) -> String {
    let name: String = name
        .chars()
        .take(120)
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect();
    if name.is_empty() || name == "." || name == ".." {
        "attachment".into()
    } else {
        name
    }
}

pub(crate) fn begin_script(shell: RemoteShell, id: &str, name: &str) -> String {
    let relative = format!(".alleycat/attachments/{id}/{}", attachment_name(name));
    match shell {
        RemoteShell::Posix => format!(
            "set -eu; umask 077; p=\"$HOME\"/{}; mkdir -p \"$HOME/.alleycat/attachments\"; mkdir \"${{p%/*}}\"; : > \"$p\"; printf '%s' \"$p\"",
            posix_quote(&relative)
        ),
        RemoteShell::PowerShell => format!(
            "$ErrorActionPreference='Stop'; $p=Join-Path ([Environment]::GetFolderPath('UserProfile')) {}; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); $f=[IO.File]::Open($p,[IO.FileMode]::CreateNew); $f.Dispose(); [Console]::Write($p.Replace('\\','/'))",
            powershell_quote(&relative)
        ),
    }
}

pub(crate) fn verify_script(shell: RemoteShell, path: &str, size: u64) -> String {
    match shell {
        RemoteShell::Posix => format!(
            "set -eu; p={}; [ -f \"$p\" ] && [ ! -L \"$p\" ] && [ -r \"$p\" ] && [ \"$(wc -c < \"$p\" | tr -d '[:space:]')\" = '{size}' ]",
            posix_quote(path)
        ),
        RemoteShell::PowerShell => format!(
            "$ErrorActionPreference='Stop'; $f=Get-Item -LiteralPath {}; if ($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -ne {size}) {{ throw 'Attachment verification failed' }}",
            powershell_quote(path)
        ),
    }
}

pub(crate) fn cancel_script(shell: RemoteShell, path: &str) -> String {
    match shell {
        RemoteShell::Posix => format!(
            "set -eu; p={}; rm -f -- \"$p\"; rmdir -- \"${{p%/*}}\"",
            posix_quote(path)
        ),
        RemoteShell::PowerShell => format!(
            "$ErrorActionPreference='Stop'; $p={}; Remove-Item -LiteralPath $p -Force; [IO.Directory]::Delete([IO.Path]::GetDirectoryName($p))",
            powershell_quote(path)
        ),
    }
}

pub(crate) fn append_command(remote_path: &str, shell: RemoteShell) -> String {
    match shell {
        RemoteShell::Posix => {
            super::exec::build_posix_exec_command(&format!("cat >> {}", posix_quote(remote_path)))
        }
        RemoteShell::PowerShell => {
            let script = format!(
                "$ErrorActionPreference='Stop'; $f=[IO.File]::Open({},[IO.FileMode]::Append,[IO.FileAccess]::Write); try {{ [Console]::OpenStandardInput().CopyTo($f) }} finally {{ $f.Dispose() }}",
                powershell_quote(remote_path)
            );
            let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
            format!(
                "powershell -NoProfile -NonInteractive -EncodedCommand {}",
                base64::engine::general_purpose::STANDARD.encode(bytes)
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::process::{Command, Stdio};

    #[test]
    fn attachment_names_cannot_escape_the_transfer_directory() {
        for name in [
            "../escape.zip",
            "$(touch stolen)",
            "x';exit 7;'",
            "../",
            "",
            ".",
            "..",
        ] {
            let safe = attachment_name(name);
            assert!(!safe.is_empty());
            assert!(!safe.contains(['/', '\\', '\'', '$', ';']));
            assert!(!matches!(safe.as_str(), "." | ".."));
        }
        assert_eq!(attachment_name("report.zip"), "report.zip");
    }

    #[test]
    #[cfg(unix)]
    fn posix_transfer_preserves_binary_bytes_checks_size_and_cleans_only_its_file() {
        let home = std::env::temp_dir().join(format!(
            "alleycat-transfer-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&home).unwrap();
        let run = |script: &str| {
            Command::new("sh")
                .arg("-c")
                .arg(script)
                .env("HOME", &home)
                .output()
                .unwrap()
        };
        let created = run(&begin_script(
            RemoteShell::Posix,
            "test-transfer",
            "../my 'report.zip",
        ));
        assert!(created.status.success(), "{:?}", created);
        let path = String::from_utf8(created.stdout).unwrap();
        assert!(
            std::path::Path::new(&path)
                .starts_with(home.join(".alleycat/attachments/test-transfer"))
        );
        let bytes: Vec<u8> = (0..131_072).map(|n| (n % 256) as u8).collect();
        // Append twice over stdin, including every byte value and more bytes
        // than a Windows command line can carry.
        for _ in 0..2 {
            let mut child = Command::new("sh")
                .arg("-c")
                .arg(append_command(&path, RemoteShell::Posix))
                .stdin(Stdio::piped())
                .spawn()
                .unwrap();
            child.stdin.take().unwrap().write_all(&bytes).unwrap();
            assert!(child.wait().unwrap().success());
        }
        assert_eq!(std::fs::read(&path).unwrap(), bytes.repeat(2));
        assert!(
            run(&verify_script(RemoteShell::Posix, &path, 262_144))
                .status
                .success()
        );
        assert!(
            !run(&verify_script(RemoteShell::Posix, &path, 262_143))
                .status
                .success()
        );
        let link = format!("{path}.link");
        std::os::unix::fs::symlink(&path, &link).unwrap();
        assert!(
            !run(&verify_script(RemoteShell::Posix, &link, 262_144))
                .status
                .success()
        );
        std::fs::remove_file(link).unwrap();
        let neighbor = home.join(".alleycat/attachments/keep.zip");
        std::fs::write(&neighbor, b"keep").unwrap();
        assert!(
            run(&cancel_script(RemoteShell::Posix, &path))
                .status
                .success()
        );
        assert!(!std::path::Path::new(&path).exists());
        assert_eq!(std::fs::read(neighbor).unwrap(), b"keep");
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn powershell_streaming_uses_a_short_encoded_command_and_quoted_literal_path() {
        let command = append_command("C:/Users/O'Brien/report.zip", RemoteShell::PowerShell);
        assert!(command.len() < 8191);
        let encoded = command.split_whitespace().last().unwrap();
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .unwrap();
        let utf16: Vec<u16> = bytes
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        let script = String::from_utf16(&utf16).unwrap();
        assert!(script.contains("'C:/Users/O''Brien/report.zip'"));
        assert!(script.contains("OpenStandardInput().CopyTo($f)"));
        assert!(script.contains("finally { $f.Dispose() }"));
    }
}
