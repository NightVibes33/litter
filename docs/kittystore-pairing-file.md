# KittyStore pairing file

KittyStore needs a device pairing file before installs, refreshes, LocalDevVPN, or Feather signing can talk to the paired iPhone.

## Import in KittyStore

1. Open KittyStore.
2. Open Settings.
3. Open Advanced Settings.
4. Tap Pairing File.
5. Choose Import Pairing File or Replace Pairing File.
6. Select a `.mobiledevicepairing`, `.pairing`, or `.plist` pairing file.

KittyStore saves the same validated pairing record to both `ALTPairingFile.mobiledevicepairing` and `pairingFile.plist` so the embedded store transport and Feather signing path use the same file.

## What KittyStore accepts

KittyStore accepts either a complete Lockdown-style pairing record with these keys:

- `DeviceCertificate`
- `HostCertificate`
- `RootCertificate`
- `SystemBUID`
- `HostID`
- `WiFiMACAddress`
- `EscrowBag`
- `UDID`

Or a complete Remote Pairing record with these keys:

- `PairRecordData`
- `private_key`

A file with only one random pairing-looking key is rejected so bad imports do not break installs later.

## Replace or delete

Use Settings > Advanced Settings > Pairing File any time you need to replace a stale pairing file. If installs or refreshes keep failing after a device restore, delete the old pairing file and import a fresh one.
