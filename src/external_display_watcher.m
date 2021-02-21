#ifdef DEBUG
#define MyLog NSLog
#else
#define MyLog(...) (void)printf("%s\n",[[NSString stringWithFormat:__VA_ARGS__] UTF8String])
#endif

#import <Cocoa/Cocoa.h>
#import <IOKit/graphics/IOGraphicsLib.h>

static NSString *path;

// Returns the io_service_t (an int) corresponding to a CG display ID, or 0 on failure.
// The io_service_t should be released with IOObjectRelease when not needed.
//
// see: https://stackoverflow.com/questions/20025868/cgdisplayioserviceport-is-deprecated-in-os-x-10-9-how-to-replace
static io_service_t IOServicePortFromCGDisplayID(CGDirectDisplayID displayID) {
  io_iterator_t iter;
  io_service_t serv, servicePort = 0;

  CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");

  // releases matching for us
  kern_return_t err = IOServiceGetMatchingServices( kIOMasterPortDefault, matching, & iter );
  if ( err )
    return 0;

  while ( (serv = IOIteratorNext(iter)) != 0 ) {
    CFDictionaryRef displayInfo;
    CFNumberRef vendorIDRef;
    CFNumberRef productIDRef;
    CFNumberRef serialNumberRef;

    displayInfo = IODisplayCreateInfoDictionary( serv, kIODisplayOnlyPreferredName );

    Boolean success;
    success =  CFDictionaryGetValueIfPresent( displayInfo, CFSTR(kDisplayVendorID),  (const void**) & vendorIDRef );
    success &= CFDictionaryGetValueIfPresent( displayInfo, CFSTR(kDisplayProductID), (const void**) & productIDRef );

    if ( !success ) {
      CFRelease(displayInfo);
      continue;
    }

    SInt32 vendorID;
    CFNumberGetValue( vendorIDRef, kCFNumberSInt32Type, &vendorID );
    SInt32 productID;
    CFNumberGetValue( productIDRef, kCFNumberSInt32Type, &productID );

    // If a serial number is found, use it.
    // Otherwise serial number will be nil (= 0) which will match with the output of 'CGDisplaySerialNumber'
    SInt32 serialNumber = 0;
    if ( CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplaySerialNumber), (const void**) & serialNumberRef) ) {
      CFNumberGetValue( serialNumberRef, kCFNumberSInt32Type, &serialNumber );
    }

    // If the vendor and product id along with the serial don't match
    // then we are not looking at the correct monitor.
    // NOTE: The serial number is important in cases where two monitors
    //       are the exact same.
    if( CGDisplayVendorNumber(displayID) != vendorID ||
        CGDisplayModelNumber(displayID)  != productID ||
        CGDisplaySerialNumber(displayID) != serialNumber ) {
      CFRelease(displayInfo);
      continue;
    }

    servicePort = serv;
    CFRelease(displayInfo);
    break;
  }

  IOObjectRelease(iter);
  return servicePort;
}

static NSString* nameForDisplay(NSNumber *displayNumber) {
  CGDirectDisplayID display = [displayNumber unsignedIntValue];
  io_service_t serv = IOServicePortFromCGDisplayID(display);

  if (serv == 0)
    return @"unknown";

  CFDictionaryRef info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);
  IOObjectRelease(serv);

  CFStringRef display_name;
  CFDictionaryRef names = CFDictionaryGetValue(info, CFSTR(kDisplayProductName));

  if ( !names ||
       !CFDictionaryGetValueIfPresent(names, CFSTR("en_US"), (const void**) & display_name)  ) {
    // This may happen if a desktop Mac is running headless
    CFRelease( info );
    return @"unknown";
  }

  NSString * displayname = [NSString stringWithString: (__bridge NSString *) display_name];
  CFRelease(info);
  return [displayname autorelease];
}

static void runCommand(NSArray *arguments) {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = path;
  task.arguments = arguments;

  [task launch];

  if(task.isRunning)
    [task waitUntilExit];

  int status = [task terminationStatus];
  if(status != 0) {
    MyLog(@"E: Command exited with error! exit_code: %d", status);
  }
}

static void handleConfigChange(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
  NSMutableSet *displays = (NSMutableSet *)userInfo;
  BOOL containsDisplay = [displays containsObject:[NSNumber numberWithUnsignedInteger:display]];
  bool displaySetChanged = 0;

  if (flags & kCGDisplayRemoveFlag && containsDisplay) {
    [displays removeObject:[NSNumber numberWithUnsignedInteger:display]];
    displaySetChanged = 1;
  } else {
    if (CGDisplayIsBuiltin(display)) return;

    if (flags & kCGDisplayAddFlag && !containsDisplay) {
      [displays addObject:[NSNumber numberWithUnsignedInteger:display]];
      displaySetChanged = 1;
    }
  }

  if (displaySetChanged) {
    MyLog(@"I: display state change, found %lu external display(s)", [displays count]);

    NSMutableArray *displayNames = [[NSMutableArray alloc] init];
    for (NSNumber *display in displays) {
      NSString *name = nameForDisplay(display);
      [displayNames addObject:name];
    }

    runCommand(displayNames);

    [displayNames removeAllObjects];
    [displayNames release];
  }
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {

    NSString *HelpString = @"Usage:\n"
      @"ddcctl \t-l [list currently connected display names]\n"
      @"\t-w <path>  [watch for change in display, <path> executable will be executed with current display names as arguments]\n";

    if (argc == 2 && !strcmp(argv[1], "-l")) {
      for (NSScreen *screen in NSScreen.screens) {
        NSDictionary *description = [screen deviceDescription];
        if ([description objectForKey:@"NSDeviceIsScreen"]) {
          CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
          if (CGDisplayIsBuiltin(screenNumber)) continue; // ignore MacBook screens because the lid can be closed and they don't use DDC.
          NSString *name = nameForDisplay([NSNumber numberWithUnsignedInteger:screenNumber]);
          MyLog(@"I: %s", [name UTF8String]);
        }
      }
      return 0;
    } else if (argc == 3 && !strcmp(argv[1], "-w")) {
      NSFileManager *fileManager = [NSFileManager defaultManager];
      path = [NSString stringWithUTF8String: argv[2]];

      if (![fileManager fileExistsAtPath:path]) {
        MyLog(@"%@", HelpString);
        return -1;
      }
    } else {
      MyLog(@"%@", HelpString);
      return -1;
    }


    // get already connected displays
    NSMutableSet *displays = [NSMutableSet setWithCapacity:20];

    for (NSScreen *screen in NSScreen.screens) {
      NSDictionary *description = [screen deviceDescription];
      if ([description objectForKey:@"NSDeviceIsScreen"]) {
        CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(screenNumber)) continue; // ignore MacBook screens because the lid can be closed and they don't use DDC.
        [displays addObject:[NSNumber numberWithUnsignedInteger:screenNumber]];
      }
    }

    MyLog(@"I: watching for external display changes");
    CGDisplayRegisterReconfigurationCallback(handleConfigChange, displays);

    NSApplicationLoad();
    CFRunLoopRun();
  }
  return 0;
}
