//! Bidirectional TCP↔SSH-channel proxy used by every forwarded port.
//!
//! `make_writer()` clones the channel's internal senders so we can copy
//! local→remote on a spawned task while the current task drives
//! remote→local via `channel.wait()` (which takes `&mut self`).

use russh::ChannelMsg;
use russh::client::Msg;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use super::append_android_debug_log;

pub(super) async fn proxy_connection(
    local: tokio::net::TcpStream,
    mut ssh_channel: russh::Channel<Msg>,
    local_port: u16,
    remote_host: &str,
    remote_port: u16,
    peer_addr: std::net::SocketAddr,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let remote_host = remote_host.to_string();

    let mut ssh_writer = ssh_channel.make_writer();
    let (mut local_read, mut local_write) = local.into_split();

    // local → remote on a spawned task.
    let local_to_remote_remote_host = remote_host.clone();
    let local_to_remote = tokio::spawn(async move {
        let mut buf = vec![0u8; 32768];
        loop {
            match local_read.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    if ssh_writer.write_all(&buf[..n]).await.is_err() {
                        append_android_debug_log(&format!(
                            "ssh_forward_local_to_remote_write_failed listen=127.0.0.1:{} remote={}:{} peer={}",
                            local_port, local_to_remote_remote_host, remote_port, peer_addr
                        ));
                        break;
                    }
                }
                Err(error) => {
                    append_android_debug_log(&format!(
                        "ssh_forward_local_read_error listen=127.0.0.1:{} remote={}:{} peer={} error={}",
                        local_port, local_to_remote_remote_host, remote_port, peer_addr, error
                    ));
                    break;
                }
            }
        }
        // Dropping ssh_writer signals we are done writing to the channel.
    });

    // remote → local on the current task.
    loop {
        match ssh_channel.wait().await {
            Some(ChannelMsg::Data { data }) => {
                if local_write.write_all(&data).await.is_err() {
                    append_android_debug_log(&format!(
                        "ssh_forward_local_write_failed listen=127.0.0.1:{} remote={}:{} peer={}",
                        local_port, remote_host, remote_port, peer_addr
                    ));
                    break;
                }
            }
            Some(ChannelMsg::Eof) => {
                append_android_debug_log(&format!(
                    "ssh_forward_channel_eof listen=127.0.0.1:{} remote={}:{} peer={}",
                    local_port, remote_host, remote_port, peer_addr
                ));
                break;
            }
            Some(ChannelMsg::Close) => {
                append_android_debug_log(&format!(
                    "ssh_forward_channel_close listen=127.0.0.1:{} remote={}:{} peer={}",
                    local_port, remote_host, remote_port, peer_addr
                ));
                break;
            }
            None => {
                append_android_debug_log(&format!(
                    "ssh_forward_channel_ended listen=127.0.0.1:{} remote={}:{} peer={}",
                    local_port, remote_host, remote_port, peer_addr
                ));
                break;
            }
            _ => {}
        }
    }

    local_to_remote.abort();
    let _ = ssh_channel.close().await;

    Ok(())
}
