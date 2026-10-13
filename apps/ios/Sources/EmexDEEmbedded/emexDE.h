#pragma once

// Expose the embedded Nyxian Objective-C interface through the framework module.
#import <NXBridge.h>

// Upstream recovery UI is Objective-C and must be exposed to embedded Swift.
#import <UI/NXRecoveryViewController.h>

// Upstream BootViewController Swift calls NXVolumeButtonMonitor.scan/disarm.
// Expose its Objective-C declaration to this mixed-language framework.
#import <UI/NXVolumeButtonMonitor.h>
