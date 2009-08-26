/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

enum {
	kAudioUnitPresetDomain_User		= 0,
	kAudioUnitPresetDomain_Local	= 1
};

@interface SFBAudioUnitUISaveAUPresetSheet : NSObject
{
	IBOutlet NSWindow *_sheet;

@private
	NSString *_presetName;
	int _presetDomain;
}

- (NSWindow *) sheet;

- (IBAction) ok:(id)sender;
- (IBAction) cancel:(id)sender;

- (NSString *) presetName;
- (void) setPresetName:(NSString *)presetName;

- (int) presetDomain;
- (void) setPresetDomain:(int)presetDomain;

@end
