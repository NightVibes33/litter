// Jackson Coxson

use std::{fs, io, path::PathBuf};

use idevice::{misagent::MisagentClient, IdeviceError};

use crate::idevice_support::rsd::connect_to_rsd_services;

/// Installs a provisioning profile on the device
pub async fn install_provisioning_profile_rppairing(profile: &[u8]) -> Result<(), IdeviceError> {
    let profile = profile.to_vec();

    let mut mis_client = connect_to_rsd_services::<MisagentClient>().await?;

    mis_client.install(profile).await
}

pub async fn remove_provisioning_profile_rppairing(id: String) -> Result<(), IdeviceError> {
    let mut mis_client = connect_to_rsd_services::<MisagentClient>().await?;

    mis_client.remove(&id).await
}

pub async fn dump_provisioning_profile_rppairing(docs_path: String) -> Result<(), IdeviceError> {
    let mut mis_client = connect_to_rsd_services::<MisagentClient>().await?;

    let dump_dir = PathBuf::from(format!("{docs_path}/PROVISION"));
    fs::create_dir_all(&dump_dir).map_err(IdeviceError::Socket)?;

    let profiles = mis_client.copy_all().await?;

    for (i, profile) in profiles.iter().enumerate() {
        let file_name = match plist::from_bytes::<plist::Dictionary>(profile.as_slice()) {
            Ok(plist) => match plist.get("UUID") {
                Some(plist::Value::String(uuid)) => format!("{uuid}.mobileprovision"),
                _ => format!("unknown_{i}.mobileprovision"),
            },
            Err(_) => format!("unknown_{i}.plist"),
        };

        fs::write(dump_dir.join(file_name), profile)
            .map_err(|err| IdeviceError::Socket(io::Error::new(err.kind(), err.to_string())))?;
    }

    Ok(())
}
