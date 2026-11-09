# cg-retro

chicken gun port for jailbroken ios 6 and later, armv7 and arm64. ios 16 and
64-bit devices need real-device testing.

## build

```bash
export THEOS=/path/to/theos
export CG_SDK_V7=/path/to/armv7-iphoneos.sdk
export CG_SDK_V64=/path/to/iPhoneOS16.5.sdk
make test
make deb
make ipa
```

the arm64 build needs the ios 16.5 sdk. `CG_CRT_V7` overrides the armv7 startup
object when it is outside the sdk.
the package is `build/cg-retro.deb`, with the app in `/Applications` for a
rootful jailbreak. installation and app registration are not part of the build.
`build/cg-retro.ipa` contains the same ad-hoc signed app in `Payload`. install
it with appsync or sign it with a valid provisioning profile before sideloading.
