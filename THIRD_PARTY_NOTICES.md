# Third Party Notices

## Nyxian / LLVM-On-iOS

Litter includes direct source imports from ProjectNyxian/Nyxian and ProjectNyxian/LLVM-On-iOS under `ThirdParty/Nyxian` and `ThirdParty/LLVM-On-iOS` for on-device BuildKit development. Nyxian is licensed under AGPL-3.0. Imported files retain original headers where present; the copied AGPL license is stored at `ThirdParty/Nyxian/LICENSE`.

Source repositories:

- https://github.com/ProjectNyxian/Nyxian
- https://github.com/ProjectNyxian/LLVM-On-iOS


## Litter BuildKit Private Assets

The public repository includes only the BuildKit manifest contract, command bridge,
the native ABI wrapper source, and Nyxian source references. Apple iPhoneOS SDK
files are intentionally excluded and must be supplied by the user/private build
environment under Apple's Xcode and SDK license terms.
