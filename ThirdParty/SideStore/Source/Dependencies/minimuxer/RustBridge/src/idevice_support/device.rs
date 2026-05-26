use crate::idevice_support::rsd::connect_to_rsd_services;
use ::idevice::lockdown::LockdownClient;
use idevice::IdeviceError;
use std::time::Duration;

/// Tests if the device is on and listening without jumping through hoops
pub fn test_device_connection() -> bool {
    use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpStream};

    let port: u16;

    port = 62078;

    // Connect to lockdownd's socket
    TcpStream::connect_timeout(
        &SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(10, 7, 0, 1), port)),
        Duration::from_millis(100),
    )
    .is_ok()
}

pub async fn fetch_udid_rppairing() -> Result<String, IdeviceError> {
    let mut lockdown_client = connect_to_rsd_services::<LockdownClient>().await?;

    let udid_val = lockdown_client
        .get_value(Some("UniqueDeviceID"), None)
        .await?;

    match udid_val.as_string() {
        Some(s) => Ok(s.to_string()),
        None => Err(IdeviceError::InvalidArgument),
    }
}
