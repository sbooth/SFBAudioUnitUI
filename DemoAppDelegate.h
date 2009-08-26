/*
 *  Copyright (C) 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>

@interface DemoAppDelegate : NSObject
{
@private
	AUGraph _graph;
	AudioUnit _au;
}

@end
