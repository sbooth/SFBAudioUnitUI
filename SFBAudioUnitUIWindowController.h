/*
 *  Copyright (C) 2007 - 2011 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>

@interface SFBAudioUnitUIWindowController : NSWindowController
{
@private
	NSDrawer *_presetsDrawer;
	NSOutlineView *_presetsOutlineView;
	NSToolbarItem *_bypassEffectToolbarItem;

	AudioUnit _audioUnit;
	AUEventListenerRef _auEventListener;

	NSString *_auNameAndManufacturer;
	NSString *_auManufacturer;
	NSString *_auName;
	
	NSString *_auPresentPresetName;
	
	NSView *_auView;
	NSMutableArray *_presetsTree;
}

@property (assign) IBOutlet NSDrawer * presetsDrawer;
@property (assign) IBOutlet NSOutlineView * presetsOutlineView;
@property (assign) IBOutlet NSToolbarItem * bypassEffectToolbarItem;

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
