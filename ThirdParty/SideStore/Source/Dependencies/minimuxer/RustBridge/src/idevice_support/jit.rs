// Jackson Coxson
use idevice::{
    debug_proxy::DebugProxyClient,
    dvt::{process_control::ProcessControlClient, remote_server::RemoteServerClient},
    IdeviceError, ReadWrite,
};

use crate::idevice_support::rsd::connect_to_rsd_services;

/// Debugs an app from an app ID
pub async fn debug_app_rppairing(app_id: String) -> Result<(), IdeviceError> {
    let mut remote_server =
        connect_to_rsd_services::<RemoteServerClient<Box<dyn ReadWrite + 'static>>>().await?;
    let mut debug_proxy =
        connect_to_rsd_services::<DebugProxyClient<Box<dyn ReadWrite + 'static>>>().await?;

    let mut process_control = ProcessControlClient::new(&mut remote_server).await?;

    let pid = process_control
        .launch_app(app_id, None, None, true, true)
        .await?;

    let _ = process_control.disable_memory_limit(pid).await;

    let commands = [format!("vAttach;{pid:02X}"), "D".to_string()];
    for command in commands {
        debug_proxy.send_command(command.into()).await?;
    }
    Ok(())
}

pub async fn debug_process_rppairing(pid: u32) -> Result<(), IdeviceError> {
    let mut debug_proxy =
        connect_to_rsd_services::<DebugProxyClient<Box<dyn ReadWrite + 'static>>>().await?;

    let commands = [format!("vAttach;{pid:02X}"), "D".to_string()];
    for command in commands {
        debug_proxy.send_command(command.into()).await?;
    }
    Ok(())
}
