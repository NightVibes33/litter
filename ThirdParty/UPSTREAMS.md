# Vendored Upstreams

These source drops are kept small and source-only. Generated build products, IPAs, provisioning profiles, certificates, and private assets are intentionally excluded.

## Feather / Zsign

- Feather reference repo: https://github.com/khcrysalis/Feather.git
- Feather reference commit inspected for this integration: `6c0dc83a4cdee6206b771a6dd3d1337f89668ffd`
- Vendored signing engine repo: https://github.com/khcrysalis/Zsign-Package.git
- Vendored path: `ThirdParty/Feather/Zsign-Package`
- License: MIT, see `ThirdParty/Feather/Zsign-Package/LICENSE`

## SideStore / Minimuxer / LocalDevVPN

- SideStore reference repo: https://github.com/SideStore/SideStore.git
- SideStore reference commit inspected for this integration: `d292edffd1264918e6a83d3d2a0fb8cfde80e3ca`
- minimuxer repo: https://github.com/SideStore/minimuxer.git
- minimuxer vendored commit: `f9432a085b19de1bbcd744c600f510f499703a97`
- minimuxer vendored path: `ThirdParty/SideStore/minimuxer`
- Minimuxer wrapper path: `ThirdParty/SideStore/MinimuxerWrapper.swift`
- LocalDevVPN repo: https://github.com/jkcoxson/LocalDevVPN.git
- LocalDevVPN vendored commit: `c4566ce08931cef414c9f656e7e33c66bdb2454e`
- LocalDevVPN tunnel-provider path: `ThirdParty/SideStore/LocalDevVPN-TunnelProv`
- License: minimuxer is AGPL-3.0, see `ThirdParty/SideStore/minimuxer/LICENSE`; LocalDevVPN keeps its upstream terms.
