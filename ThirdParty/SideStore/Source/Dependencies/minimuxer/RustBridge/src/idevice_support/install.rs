// Jackson Coxson

use idevice::{
    afc::{opcode::AfcFopenMode, AfcClient},
    installation_proxy::InstallationProxyClient,
    IdeviceError,
};
use plist::{Dictionary, Value};

use crate::idevice_support::rsd::connect_to_rsd_services;
use tokio::io::AsyncWriteExt;

const PKG_PATH: &str = "PublicStaging";

pub async fn yeet_app_afc_rppairing(
    bundle_id: String,
    ipa_bytes: &[u8],
) -> Result<(), IdeviceError> {
    let mut afc = connect_to_rsd_services::<AfcClient>().await?;

    ensure_afc_directory(&mut afc, PKG_PATH).await?;
    ensure_afc_directory(&mut afc, &format!("{PKG_PATH}/{bundle_id}")).await?;

    let path = format!("{PKG_PATH}/{bundle_id}/app.ipa");
    let mut handle = afc.open(&path, AfcFopenMode::WrOnly).await?;

    handle.write_all(ipa_bytes).await?;

    handle.shutdown().await?;

    handle.close().await
}

pub async fn install_ipa_rppairing(bundle_id: String) -> Result<(), IdeviceError> {
    let mut inst_client = connect_to_rsd_services::<InstallationProxyClient>().await?;

    let mut client_opts = Dictionary::new();
    client_opts.insert("CFBundleIdentifier".into(), bundle_id.clone().into());

    inst_client
        .install(
            format!("{PKG_PATH}/{bundle_id}/app.ipa"),
            Some(Value::Dictionary(client_opts)),
        )
        .await
}

pub async fn remove_app_rppairing(bundle_id: String) -> Result<(), IdeviceError> {
    let mut inst_client = connect_to_rsd_services::<InstallationProxyClient>().await?;

    inst_client.uninstall(bundle_id, None).await
}

async fn ensure_afc_directory(afc: &mut AfcClient, path: &str) -> Result<(), IdeviceError> {
    if afc.get_file_info(path).await.is_err() {
        afc.mk_dir(path).await?;

        afc.get_file_info(path).await?;
    }

    Ok(())
}
