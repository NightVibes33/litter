// Jackson Coxson

use idevice::{lockdown::LockdownClient, mobile_image_mounter::ImageMounter};
use log::{error, info};
use std::io::Write;

use crate::idevice_support::rsd::{
    connect_to_rsd_services, get_or_create_rppairing_rsd_connection,
};

pub async fn mount_personalized_ddi_rppairing(
    image_bytes: &[u8],
    trustcache_bytes: &[u8],
    manifest_bytes: &[u8],
) -> i32 {
    let mut lockdown_client = match connect_to_rsd_services::<LockdownClient>().await {
        Ok(m) => m,
        Err(e) => {
            error!("ImageMounter: {:?}", e);
            return 4;
        }
    };

    let ucid_val = match lockdown_client.get_value(Some("UniqueChipID"), None).await {
        Ok(s) => s,
        Err(e) => {
            error!("ImageMounter: {:?}", e);
            return 5;
        }
    };

    let unique_chip_id = match ucid_val.as_unsigned_integer() {
        Some(s) => s,
        None => {
            error!("ImageMounter: Failed to convert UniqueChipID to string");
            return 5;
        }
    };

    let mut mounter = match connect_to_rsd_services::<ImageMounter>().await {
        Ok(m) => m,
        Err(e) => {
            error!("ImageMounter: {:?}", e);
            return 6;
        }
    };

    let images = match mounter.copy_devices().await {
        Ok(i) => i,
        Err(e) => {
            error!("copy_devices: {:?}", e);
            return 6;
        }
    };
    if !images.is_empty() {
        info!("Already mounted");
        return 0;
    }

    info!("Mounting personalized DDI...");
    let mut connection = match get_or_create_rppairing_rsd_connection().await {
        Ok(i) => i,
        Err(e) => {
            error!("get connection: {:?}", e);
            return 6;
        }
    };
    let conn = &mut *connection;
    if let Err(e) = mounter
        .mount_personalized_with_callback_rsd(
            &mut conn.adapter,
            &mut conn.handshake,
            image_bytes.to_vec(),
            trustcache_bytes.to_vec(),
            manifest_bytes,
            None,
            unique_chip_id,
            async |((n, d), _)| {
                let pct = (n as f64 / d as f64) * 100.0;
                print!("\rProgress: {pct:.2}%");
                std::io::stdout().flush().unwrap();
                if n == d {
                    println!();
                }
            },
            (),
        )
        .await
    {
        error!("Mount failed: {:?}", e);
        return 8;
    }

    info!("DDI mounted");
    0
}
