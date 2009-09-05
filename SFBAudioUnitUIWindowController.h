/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>

@interface SFBAudioUnitUIWindowController : NSWindowController
{
	IBOutlet NSDrawer *_presetsDrawer;
	IBOutlet NSOutlineView *_presetsOutlineView;

@private
	AudioUnit _audioUnit;
	AUEventListenerRef _auEventListener;

	NSString *_auNameAndManufacturer;
	NSString *_auManufacturer;
	NSString *_auName;
	
	NSString *_auPresentPresetName;
	
	NSView *_auView;
	NSMutableArray *_presetsTree;
}

// The AudioUnit to work with
- (AudioUnit) audioUnit;
- (void) setAudioUnit:(AudioUnit)audioUnit;

// Save the current settings as a preset 
- (IBAction) savePreset:(id)sender;

// Toggle whether the AU is bypassed
- (IBAction) toggleBypassEffect:(id)sender;

// Save/Restore settings from a preset file in a non-standard location
- (IBAction) savePresetToFile:(id)sender;
- (IBAction) loadPresetFromFile:(id)sender;

// Load a factory preset
- (void) loadFactoryPresetNumber:(NSNumber *)presetNumber presetName:(NSString *)presetName;

// Save/Restore presets to/from a specific URL
- (void) loadCustomPresetFromURL:(NSURL *)presetURL;
- (void) saveCustomPresetToURL:(NSURL *)presetURL presetName:(NSString *)presetName;

@end
