/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SFBAudioUnitUIWindowController.h"
#import "SFBAudioUnitUISaveAUPresetSheet.h"

#include <CoreAudioKit/CoreAudioKit.h>
#include <AudioUnit/AUCocoaUIView.h>

// ========================================
// Toolbar item identifiers
// ========================================
static NSString * const AudioUnitUIToolbarIdentifier					= @"org.sbooth.AudioUnitUI.Toolbar";
static NSString * const PresetDrawerToolbarItemIdentifier				= @"org.sbooth.AudioUnitUI.Toolbar.PresetDrawer";
static NSString * const SavePresetToolbarItemIdentifier					= @"org.sbooth.AudioUnitUI.Toolbar.SavePreset";
static NSString * const BypassEffectToolbarItemIdentifier				= @"org.sbooth.AudioUnitUI.Toolbar.BypassEffect";
static NSString * const ExportPresetToolbarItemIdentifier				= @"org.sbooth.AudioUnitUI.Toolbar.ExportPreset";
static NSString * const ImportPresetToolbarItemIdentifier				= @"org.sbooth.AudioUnitUI.Toolbar.ImportPreset";

@interface SFBAudioUnitUIWindowController (NotificationManagerMethods)
- (void) auViewFrameDidChange:(NSNotification *)notification;
@end

@interface SFBAudioUnitUIWindowController (PanelCallbacks)
- (void) savePresetToFileSavePanelDidEnd:(NSSavePanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) loadPresetFromFileOpenPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) savePresetSaveAUPresetSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
@end

@interface SFBAudioUnitUIWindowController (Private)
- (void) updateAudioUnitNameAndManufacturer;
- (NSArray *) localPresets;
- (NSArray *) userPresets;
- (NSArray *) presetsForDomain:(short)domain;
- (void) scanPresets;
- (void) updatePresentPresetName;
- (void) updateBypassEffectToolbarItem;
- (void) notifyAUListenersOfParameterChanges;
- (void) startListeningForParameterChangesOnAudioUnit:(AudioUnit)audioUnit;
- (void) stopListeningForParameterChangesOnAudioUnit:(AudioUnit)audioUnit;
- (BOOL) hasCocoaView;
- (NSView *) getCocoaView;
- (void) presetDoubleClicked:(id)sender;
- (void) selectPresetNumber:(NSNumber *)presetNumber presetName:(NSString *)presetName presetPath:(NSString *)presetPath;
@end

// ========================================
// AUEventListener callbacks
// ========================================
static void 
myAUEventListenerProc(void						*inCallbackRefCon,
					  void						*inObject,
					  const AudioUnitEvent		*inEvent,
					  UInt64					inEventHostTime,
					  Float32					inParameterValue)
{

#pragma unused(inObject)
#pragma unused(inEventHostTime)
#pragma unused(inParameterValue)

	SFBAudioUnitUIWindowController *myself = (SFBAudioUnitUIWindowController *)inCallbackRefCon;
	
	if(kAudioUnitEvent_PropertyChange == inEvent->mEventType) {
		switch(inEvent->mArgument.mProperty.mPropertyID) {
			case kAudioUnitProperty_BypassEffect:		[myself updateBypassEffectToolbarItem];			break;
			case kAudioUnitProperty_PresentPreset:		[myself updatePresentPresetName];				break;
		}
	}
}

@implementation SFBAudioUnitUIWindowController

- (id) init
{
	if((self = [super initWithWindowNibName:@"SFBAudioUnitUIWindow"])) {
		_presetsTree = [[NSMutableArray alloc] init];
		
		OSStatus err = AUEventListenerCreate(myAUEventListenerProc,
											 self,
											 CFRunLoopGetCurrent(),
											 kCFRunLoopDefaultMode,
											 0.1f,
											 0.1f,
											 &_auEventListener);
		if(noErr != err) {
			[self release];
			return nil;
		}		
	}
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSViewFrameDidChangeNotification 
												  object:_auView];

	if(NULL != _audioUnit)
		[self stopListeningForParameterChangesOnAudioUnit:_audioUnit];

	OSStatus err = AUListenerDispose(_auEventListener);
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUListenerDispose failed: %i", err);
	
	[_auNameAndManufacturer release], _auNameAndManufacturer = nil;
	[_auManufacturer release], _auManufacturer = nil;
	[_auName release], _auName = nil;
	[_auPresentPresetName release], _auPresentPresetName = nil;

	[_auView release], _auView = nil;
	[_presetsTree release], _presetsTree = nil;
	
	_audioUnit = NULL;
	
	[super dealloc];
}

- (void) awakeFromNib
{
	// Setup the toolbar
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:AudioUnitUIToolbarIdentifier];
    
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setDelegate:self];
	
    [[self window] setToolbar:[toolbar autorelease]];
	
	// Set up the presets outline view
	[_presetsOutlineView setTarget:self];
	[_presetsOutlineView setAction:NULL];
	[_presetsOutlineView setDoubleAction:@selector(presetDoubleClicked:)];
}

- (AudioUnit) audioUnit
{
	return _audioUnit;
}

- (void) setAudioUnit:(AudioUnit)audioUnit
{
	NSParameterAssert(NULL != audioUnit);
	
	if(audioUnit == [self audioUnit])
		return;
	
	// Unregister for all notifications and AUEvents for the current AudioUnit
	if(_auView)
		[[NSNotificationCenter defaultCenter] removeObserver:self 
														name:NSViewFrameDidChangeNotification 
													  object:_auView];
	
	if(NULL != _audioUnit)
		[self stopListeningForParameterChangesOnAudioUnit:_audioUnit];

	// Update the AU
	_audioUnit = audioUnit;

	[[self window] setContentView:nil];
	[_auView release], _auView = nil;

	// Determine if there is a Cocoa view for this AU
	if([self hasCocoaView])
		_auView = [[self getCocoaView] retain];
	else
		_auView = [[AUGenericView alloc] initWithAudioUnit:audioUnit
											  displayFlags:(AUViewTitleDisplayFlag | AUViewPropertiesDisplayFlag | AUViewParametersDisplayFlag)];
//	[_auView setShowsExpertParameters:YES];

	NSRect oldFrameRect = [[self window] frame];
	NSRect newFrameRect = [[self window] frameRectForContentRect:[_auView frame]];
	
	newFrameRect.origin.x = oldFrameRect.origin.x + (oldFrameRect.size.width - newFrameRect.size.width);
	newFrameRect.origin.y = oldFrameRect.origin.y + (oldFrameRect.size.height - newFrameRect.size.height);
	
	[[self window] setFrame:newFrameRect display:YES];
	[[self window] setContentView:_auView];
	
	// Register for notifications and AUEvents for the new AudioUnit
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(auViewFrameDidChange:) 
												 name:NSViewFrameDidChangeNotification 
											   object:_auView];
	
	[self startListeningForParameterChangesOnAudioUnit:_audioUnit];

	// Scan the presets for the new AudioUnit
	[self updateAudioUnitNameAndManufacturer];
	[self scanPresets];
		
	// Synchronize UI to AudioUnit state
	[self updatePresentPresetName];
	[self updateBypassEffectToolbarItem];

	// Set the window title to the name of the AudioUnit
	[[self window] setTitle:_auName];
}

- (IBAction) savePreset:(id)sender
{

#pragma unused(sender)

	SFBAudioUnitUISaveAUPresetSheet *saveAUPresetSheet = [[SFBAudioUnitUISaveAUPresetSheet alloc] init];
	
	[saveAUPresetSheet setPresetName:_auPresentPresetName];
	
	[[NSApplication sharedApplication] beginSheet:[saveAUPresetSheet sheet] 
								   modalForWindow:[self window] 
									modalDelegate:self 
								   didEndSelector:@selector(savePresetSaveAUPresetSheetDidEnd:returnCode:contextInfo:) 
									  contextInfo:saveAUPresetSheet];
}

- (IBAction) toggleBypassEffect:(id)sender
{

#pragma unused(sender)

	UInt32 bypassEffect = NO;
	UInt32 dataSize = sizeof(bypassEffect);
	
	ComponentResult err = AudioUnitGetProperty([self audioUnit], 
											   kAudioUnitProperty_BypassEffect,
											   kAudioUnitScope_Global, 
											   0, 
											   &bypassEffect,
											   &dataSize);
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_BypassEffect) failed: %i", err);
	
	bypassEffect = ! bypassEffect;
	
	err = AudioUnitSetProperty([self audioUnit], 
							   kAudioUnitProperty_BypassEffect,
							   kAudioUnitScope_Global, 
							   0, 
							   &bypassEffect, 
							   sizeof(bypassEffect));
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AudioUnitSetProperty(kAudioUnitProperty_BypassEffect) failed: %i", err);
	
	[self notifyAUListenersOfParameterChanges];
}

- (IBAction) savePresetToFile:(id)sender
{

#pragma unused(sender)

	NSSavePanel *savePanel = [NSSavePanel savePanel];
	
	[savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"aupreset"]];
	
	[savePanel beginSheetForDirectory:nil 
								 file:nil
					   modalForWindow:[self window]
						modalDelegate:self
					   didEndSelector:@selector(savePresetToFileSavePanelDidEnd:returnCode:contextInfo:)
						  contextInfo:nil];
}

- (IBAction) loadPresetFromFile:(id)sender
{

#pragma unused(sender)

	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	
	[openPanel setCanChooseFiles:YES];
	[openPanel setCanChooseDirectories:NO];
	
	[openPanel beginSheetForDirectory:nil 
								 file:nil
								types:[NSArray arrayWithObject:@"aupreset"]
					   modalForWindow:[self window]
						modalDelegate:self
					   didEndSelector:@selector(loadPresetFromFileOpenPanelDidEnd:returnCode:contextInfo:)
						  contextInfo:nil];	
}

- (void) loadFactoryPresetNumber:(NSNumber *)presetNumber presetName:(NSString *)presetName
{
	NSParameterAssert(nil != presetNumber);
	NSParameterAssert(0 <= [presetNumber intValue]);

	AUPreset preset;
	preset.presetNumber = (SInt32)[presetNumber intValue];
	preset.presetName = (CFStringRef)presetName;
	
	ComponentResult err = AudioUnitSetProperty([self audioUnit], 
											   kAudioUnitProperty_PresentPreset,
											   kAudioUnitScope_Global, 
											   0, 
											   &preset, 
											   sizeof(preset));
	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitSetProperty(kAudioUnitProperty_PresentPreset) failed: %i", err);
		return;
	}
	
	[self notifyAUListenersOfParameterChanges];
}

- (void) loadCustomPresetFromURL:(NSURL *)presetURL
{
	NSParameterAssert(nil != presetURL);

	NSError *error = nil;
	NSData *xmlData = [NSData dataWithContentsOfURL:presetURL options:NSUncachedRead error:&error];
	
	if(nil == xmlData) {
		NSLog(@"SFBAudioUnitUI: Unable to load preset from %@ (%@)", presetURL, error);
		return;
	}
	
	NSString *errorString = nil;
	NSPropertyListFormat plistFormat = NSPropertyListXMLFormat_v1_0;
	id classInfoPlist = [NSPropertyListSerialization propertyListFromData:xmlData 
														 mutabilityOption:NSPropertyListImmutable 
																   format:&plistFormat 
														 errorDescription:&errorString];
	
	if(nil != classInfoPlist) {
		ComponentResult err = AudioUnitSetProperty([self audioUnit],
												   kAudioUnitProperty_ClassInfo, 
												   kAudioUnitScope_Global, 
												   0, 
												   &classInfoPlist, 
												   sizeof(classInfoPlist));
		if(noErr != err) {
			NSLog(@"SFBAudioUnitUI: AudioUnitSetProperty(kAudioUnitProperty_ClassInfo) failed: %i", err);
			return;
		}
		
		[self notifyAUListenersOfParameterChanges];
	}
	else
		NSLog(@"SFBAudioUnitUI: Unable to create property list for AU class info: %@", errorString);
}

- (void) saveCustomPresetToURL:(NSURL *)presetURL presetName:(NSString *)presetName
{
	NSParameterAssert(nil != presetURL);

	// First set the preset's name
	if(nil == presetName)
		presetName = [[[presetURL path] lastPathComponent] stringByDeletingPathExtension];
	
	AUPreset preset;
	preset.presetNumber = -1;
	preset.presetName = (CFStringRef)presetName;
	
	ComponentResult err = AudioUnitSetProperty([self audioUnit], 
											   kAudioUnitProperty_PresentPreset,
											   kAudioUnitScope_Global, 
											   0, 
											   &preset, 
											   sizeof(preset));
	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitSetProperty(kAudioUnitProperty_PresentPreset) failed: %i", err);
		return;
	}
	
	id classInfoPlist = NULL;
	UInt32 dataSize = sizeof(classInfoPlist);
	
	err = AudioUnitGetProperty([self audioUnit],
							   kAudioUnitProperty_ClassInfo, 
							   kAudioUnitScope_Global, 
							   0, 
							   &classInfoPlist, 
							   &dataSize);
	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_ClassInfo) failed: %i", err);
		return;
	}
	
	NSString *errorString = nil;
	NSData *xmlData = [NSPropertyListSerialization dataFromPropertyList:classInfoPlist format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorString];

	if(nil == xmlData) {
		NSLog(@"SFBAudioUnitUI: Unable to create property list from AU class info: %@", errorString);
		[errorString release];
		return;
	}
	
	// Create the directory structure if required
	NSString *presetPath = [[presetURL path] stringByDeletingLastPathComponent];
	if(![[NSFileManager defaultManager] fileExistsAtPath:presetPath]) {
		NSError *error = nil;
		BOOL dirStructureCreated = [[NSFileManager defaultManager] createDirectoryAtPath:presetPath withIntermediateDirectories:YES attributes:nil error:&error];
		if(!dirStructureCreated) {
			NSLog(@"SFBAudioUnitUI: Unable to create directories for %@ (%@)", presetURL, error);
			return;
		}
	}
	
	BOOL presetSaved = [xmlData writeToURL:presetURL atomically:YES];
	if(!presetSaved) {
		NSLog(@"SFBAudioUnitUI: Unable to save preset to %@", presetURL);
		return;
	}

	[self notifyAUListenersOfParameterChanges];
}

#pragma mark NSToolbar Delegate Methods

- (NSToolbarItem *) toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag 
{

#pragma unused(toolbar)
#pragma unused(flag)

    NSToolbarItem *toolbarItem = nil;
    
	NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
	
    if([itemIdentifier isEqualToString:PresetDrawerToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

		NSString *imagePath = [myBundle pathForResource:@"ToggleAUPresetDrawerToolbarImage" ofType:@"tiff"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];
		
		[toolbarItem setLabel:NSLocalizedString(@"Presets", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedString(@"Presets", @"")];
		[toolbarItem setToolTip:NSLocalizedString(@"Show or hide the presets drawer", @"")];
		[toolbarItem setImage:image];
		
		[toolbarItem setTarget:_presetsDrawer];
		[toolbarItem setAction:@selector(toggle:)];
	}
    else if([itemIdentifier isEqualToString:SavePresetToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

		NSString *imagePath = [myBundle pathForResource:@"SaveAUPresetToolbarImage" ofType:@"png"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];

		[toolbarItem setLabel:NSLocalizedString(@"Save Preset", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedString(@"Save Preset", @"")];
		[toolbarItem setToolTip:NSLocalizedString(@"Save the current settings as a preset", @"")];
		[toolbarItem setImage:image];

		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(savePreset:)];
	}
	else if([itemIdentifier isEqualToString:BypassEffectToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

		NSString *imagePath = [myBundle pathForResource:@"BypassAUToolbarImage" ofType:@"png"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];

		[toolbarItem setLabel:NSLocalizedString(@"Bypass", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedString(@"Bypass", @"")];
		[toolbarItem setToolTip:NSLocalizedString(@"Toggle whether the AudioUnit is bypassed", @"")];
		[toolbarItem setImage:image];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(toggleBypassEffect:)];
	}
	else if([itemIdentifier isEqualToString:ImportPresetToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

		NSString *imagePath = [myBundle pathForResource:@"ImportAUPresetToolbarImage" ofType:@"png"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];

		[toolbarItem setLabel:NSLocalizedString(@"Import Preset", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedString(@"Import Preset", @"")];
		[toolbarItem setToolTip:NSLocalizedString(@"Import settings from a preset file", @"")];
		[toolbarItem setImage:image];
		
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(loadPresetFromFile:)];
	}
    else if([itemIdentifier isEqualToString:ExportPresetToolbarItemIdentifier]) {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];

		NSString *imagePath = [myBundle pathForResource:@"ExportAUPresetToolbarImage" ofType:@"png"];
		NSImage *image = [[[NSImage alloc] initWithContentsOfFile:imagePath] autorelease];

		[toolbarItem setLabel:NSLocalizedString(@"Export Preset", @"")];
		[toolbarItem setPaletteLabel:NSLocalizedString(@"Export Preset", @"")];
		[toolbarItem setToolTip:NSLocalizedString(@"Export the current settings to a preset file", @"")];
		[toolbarItem setImage:image];

		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector(savePresetToFile:)];
	}
	
    return toolbarItem;
}

- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar 
{

#pragma unused(toolbar)

    return [NSArray arrayWithObjects:
			PresetDrawerToolbarItemIdentifier, 
			SavePresetToolbarItemIdentifier, 
			NSToolbarSpaceItemIdentifier, 
			BypassEffectToolbarItemIdentifier,
			NSToolbarFlexibleSpaceItemIdentifier,
			ImportPresetToolbarItemIdentifier, 
			ExportPresetToolbarItemIdentifier, 
			nil];
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *) toolbar 
{

#pragma unused(toolbar)

    return [NSArray arrayWithObjects:
			PresetDrawerToolbarItemIdentifier, 
			SavePresetToolbarItemIdentifier, 
			BypassEffectToolbarItemIdentifier,
			ImportPresetToolbarItemIdentifier, 
			ExportPresetToolbarItemIdentifier, 
			NSToolbarSeparatorItemIdentifier, 
			NSToolbarSpaceItemIdentifier, 
			NSToolbarFlexibleSpaceItemIdentifier,
			NSToolbarCustomizeToolbarItemIdentifier, 
			nil];
}

- (NSArray *) toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{

#pragma unused(toolbar)

    return [NSArray arrayWithObject:BypassEffectToolbarItemIdentifier];
}

#pragma mark NSOutlineView Data Source Methods

- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	
#pragma unused(outlineView)

	if(nil == item)
		return [_presetsTree objectAtIndex:index];
	else
		return [[item valueForKey:@"children"] objectAtIndex:index];
}

- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	
#pragma unused(outlineView)
	
	return (0 != [[item valueForKey:@"children"] count]);
}

- (NSInteger) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	
#pragma unused(outlineView)
	
	if(nil == item)
		return [_presetsTree count];
	else
		return [[item valueForKey:@"children"] count];
}

- (id) outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	
#pragma unused(outlineView)
	
	return [item valueForKey:[tableColumn identifier]];
}

#pragma mark NSOutlineView Delegate Methods

- (BOOL) outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	
#pragma unused(outlineView)
	
	return [_presetsTree containsObject:item];
}

- (BOOL) outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	
#pragma unused(outlineView)
	
	return ![_presetsTree containsObject:item];
}

@end

@implementation SFBAudioUnitUIWindowController (NotificationManagerMethods)

- (void) auViewFrameDidChange:(NSNotification *)notification
{
	NSParameterAssert(_auView == [notification object]);
	
	NSView		*view		= _auView;
	NSWindow	*window		= [self window];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self 
													name:NSViewFrameDidChangeNotification 
												  object:view];
	
	NSSize oldContentSize	= [window contentRectForFrameRect:[window frame]].size;
	NSSize newContentSize	= [view frame].size;
	NSRect windowFrame		= [window frame];
	
	float dy = oldContentSize.height - newContentSize.height;
	float dx = oldContentSize.width - newContentSize.width;
	
	windowFrame.origin.y		+= dy;
	windowFrame.origin.x		+= dx;
	windowFrame.size.height		-= dy;
	windowFrame.size.width		-= dx;
	
	[window setFrame:windowFrame display:YES];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(auViewFrameDidChange:) 
												 name:NSViewFrameDidChangeNotification 
											   object:view];
}

@end

@implementation SFBAudioUnitUIWindowController (PanelCallbacks)

- (void) savePresetToFileSavePanelDidEnd:(NSSavePanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{

#pragma unused(contextInfo)

	if(NSCancelButton == returnCode)
		return;

	[self saveCustomPresetToURL:[panel URL] presetName:nil];
}

- (void) loadPresetFromFileOpenPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{

#pragma unused(contextInfo)

	if(NSCancelButton == returnCode)
		return;
	
	[self loadCustomPresetFromURL:[[panel URLs] lastObject]];
}

- (void) savePresetSaveAUPresetSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	SFBAudioUnitUISaveAUPresetSheet *saveAUPresetSheet = (SFBAudioUnitUISaveAUPresetSheet *)contextInfo;
	
	[sheet orderOut:self];
	[saveAUPresetSheet autorelease];
	
	if(NSOKButton == returnCode) {
		int domain;
		switch([saveAUPresetSheet presetDomain]) {
			case kAudioUnitPresetDomain_User:		domain = kUserDomain;			break;
			case kAudioUnitPresetDomain_Local:		domain = kLocalDomain;			break;
			default:								domain = kUserDomain;			break;
		}
		
		FSRef presetFolderRef;
		OSErr err = FSFindFolder(domain, kAudioPresetsFolderType, kDontCreateFolder, &presetFolderRef);
		if(noErr != err)
			NSLog(@"SFBAudioUnitUI: FSFindFolder(kAudioPresetsFolderType) failed: %i", err);
		
		CFURLRef presetsFolderURL = CFURLCreateFromFSRef(kCFAllocatorSystemDefault, &presetFolderRef);
		if(nil == presetsFolderURL) {
			NSLog(@"SFBAudioUnitUI: CFURLCreateFromFSRef failed");
			return;
		}
		
		NSString *presetName = [saveAUPresetSheet presetName];
		NSArray *pathComponents = [NSArray arrayWithObjects:[(NSURL *)presetsFolderURL path], _auManufacturer, _auName, presetName, nil];
		NSString *auPresetPath = [[[NSString pathWithComponents:pathComponents] stringByAppendingPathExtension:@"aupreset"] stringByStandardizingPath];
		
		[self saveCustomPresetToURL:[NSURL fileURLWithPath:auPresetPath] presetName:presetName];
		
		[self scanPresets];
		
		CFRelease(presetsFolderURL), presetsFolderURL = nil;
	}
}

@end

@implementation SFBAudioUnitUIWindowController (Private)

- (void) updateAudioUnitNameAndManufacturer
{
	[_auNameAndManufacturer release], _auNameAndManufacturer = nil;
	[_auManufacturer release], _auManufacturer = nil;
	[_auName release], _auName = nil;
	
	ComponentDescription cd;
	Handle componentNameHandle = NewHandle(sizeof(void *));
	if(NULL == componentNameHandle) {
		NSLog(@"SFBAudioUnitUI: NewHandle failed");	
		return;
	}

	OSErr err = GetComponentInfo((Component)[self audioUnit], &cd, componentNameHandle, NULL, NULL);
	if(noErr == err) {
		_auNameAndManufacturer = (NSString *)CFStringCreateWithPascalString(kCFAllocatorDefault, (ConstStr255Param)(*componentNameHandle), kCFStringEncodingUTF8);
		NSUInteger colonIndex = [_auNameAndManufacturer rangeOfString:@":" options:NSLiteralSearch].location;
		if(NSNotFound != colonIndex) {
			_auManufacturer = [[_auNameAndManufacturer substringToIndex:colonIndex] copy];
			
			// Skip colon
			++colonIndex;
			
			// Skip whitespace
			NSCharacterSet *whitespaceCharacters = [NSCharacterSet whitespaceCharacterSet];
			while([whitespaceCharacters characterIsMember:[_auNameAndManufacturer characterAtIndex:colonIndex]])
				++colonIndex;
			
			_auName = [[_auNameAndManufacturer substringFromIndex:colonIndex] copy];			
		}
	}
	else
		NSLog(@"SFBAudioUnitUI: GetComponentInfo failed: %i", err);
	
	DisposeHandle(componentNameHandle);
}

- (void) scanPresets
{
	NSArray		*factoryPresets		= nil;
	UInt32		dataSize			= sizeof(factoryPresets);
	
	ComponentResult err = AudioUnitGetProperty([self audioUnit], 
											   kAudioUnitProperty_FactoryPresets,
											   kAudioUnitScope_Global, 
											   0, 
											   &factoryPresets, 
											   &dataSize);
	// Delay error checking
	
	[_presetsTree removeAllObjects];

	NSMutableArray *factoryPresetsArray = [NSMutableArray array];
	
	if(noErr == err) {
		for(NSUInteger i = 0; i < [factoryPresets count]; ++i) {
			AUPreset *preset = (AUPreset *)[factoryPresets objectAtIndex:i];
			NSNumber *presetNumber = [NSNumber numberWithInt:preset->presetNumber];
			NSString *presetName = [(NSString *)preset->presetName copy];
			
			[factoryPresetsArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:presetNumber, @"presetNumber", presetName, @"presetName", nil]];

			[presetName release];
		}
		
		NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"presetName" ascending:YES];
		[factoryPresetsArray sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
		[sortDescriptor release];
	}
	else
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_FactoryPresets) failed: %i", err);	

	if([factoryPresetsArray count])
		[_presetsTree addObject:[NSDictionary dictionaryWithObjectsAndKeys:factoryPresetsArray, @"children", NSLocalizedString(@"Factory", @""), @"presetName", nil]];
	
	NSArray *localPresetsArray = [self localPresets];
	if([localPresetsArray count])
		[_presetsTree addObject:[NSDictionary dictionaryWithObjectsAndKeys:localPresetsArray, @"children", NSLocalizedString(@"Local", @""), @"presetName", nil]];

	NSArray *userPresetsArray = [self userPresets];
	if([userPresetsArray count])
		[_presetsTree addObject:[NSDictionary dictionaryWithObjectsAndKeys:userPresetsArray, @"children", NSLocalizedString(@"User", @""), @"presetName", nil]];

	[_presetsOutlineView reloadData];
	
	[factoryPresets release];
}

- (NSArray *) localPresets
{
	return [self presetsForDomain:kLocalDomain];
}

- (NSArray *) userPresets
{
	return [self presetsForDomain:kUserDomain];
}

- (NSArray *) presetsForDomain:(short)domain
{
	FSRef presetFolderRef;
	OSErr err = FSFindFolder(domain, kAudioPresetsFolderType, kDontCreateFolder, &presetFolderRef);
	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: FSFindFolder(kAudioPresetsFolderType) failed: %i", err);	
		return nil;
	}
	
	CFURLRef presetsFolderURL = CFURLCreateFromFSRef(kCFAllocatorSystemDefault, &presetFolderRef);
	if(nil == presetsFolderURL) {
		NSLog(@"SFBAudioUnitUI: CFURLCreateFromFSRef failed");	
		return nil;
	}

	NSArray *pathComponents = [NSArray arrayWithObjects:[(NSURL *)presetsFolderURL path], _auManufacturer, _auName, nil];
	NSString *auPresetsPath = [[NSString pathWithComponents:pathComponents] stringByStandardizingPath];

	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:auPresetsPath];
	NSString *path = nil;
	NSMutableArray *result = [[NSMutableArray alloc] init];
	
	while((path = [enumerator nextObject])) {
		// Skip files that aren't AU presets
		if(NO == [[path pathExtension] isEqualToString:@"aupreset"])
			continue;
		
		NSNumber *presetNumber = [NSNumber numberWithInt:-1];
		NSString *presetName = [[path lastPathComponent] stringByDeletingPathExtension];
		NSString *presetPath = [auPresetsPath stringByAppendingPathComponent:path];
		
		[result addObject:[NSDictionary dictionaryWithObjectsAndKeys:presetNumber, @"presetNumber", presetName, @"presetName", presetPath, @"presetPath", nil]];
	}
	
	CFRelease(presetsFolderURL), presetsFolderURL = nil;
	
	NSSortDescriptor *sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"presetName" ascending:YES] autorelease];
	[result sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];

	return [result autorelease];
}

- (void) updatePresentPresetName
{
	AUPreset preset;
	UInt32 dataSize = sizeof(preset);
	
	ComponentResult err = AudioUnitGetProperty([self audioUnit], 
											   kAudioUnitProperty_PresentPreset,
											   kAudioUnitScope_Global, 
											   0, 
											   &preset,
											   &dataSize);
	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_PresentPreset) failed: %i", err);	
		return;
	}

	[self willChangeValueForKey:@"auPresentPresetName"];
	
	[_auPresentPresetName release];
	_auPresentPresetName = (NSString *)preset.presetName;
	
	[self didChangeValueForKey:@"auPresentPresetName"];
}

- (void) updateBypassEffectToolbarItem
{
	UInt32 bypassEffect = NO;
	UInt32 dataSize = sizeof(bypassEffect);
	
	ComponentResult err = AudioUnitGetProperty([self audioUnit], 
											   kAudioUnitProperty_BypassEffect,
											   kAudioUnitScope_Global, 
											   0, 
											   &bypassEffect,
											   &dataSize);
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_BypassEffect) failed: %i", err);	
		
	if(bypassEffect)
		[[[self window] toolbar] setSelectedItemIdentifier:BypassEffectToolbarItemIdentifier];
	else
		[[[self window] toolbar] setSelectedItemIdentifier:nil];
}

- (void) notifyAUListenersOfParameterChanges
{
	AudioUnitParameter changedUnit;
	changedUnit.mAudioUnit = [self audioUnit];
	changedUnit.mParameterID = kAUParameterListener_AnyParameter;

	OSStatus err = AUParameterListenerNotify(NULL, NULL, &changedUnit);
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUParameterListenerNotify failed: %i", err);
}

- (void) startListeningForParameterChangesOnAudioUnit:(AudioUnit)audioUnit
{
	NSParameterAssert(NULL != audioUnit);

	AudioUnitEvent propertyEvent;
    propertyEvent.mEventType = kAudioUnitEvent_PropertyChange;
    propertyEvent.mArgument.mProperty.mAudioUnit = audioUnit;
    propertyEvent.mArgument.mProperty.mPropertyID = kAudioUnitProperty_BypassEffect;
    propertyEvent.mArgument.mProperty.mScope = kAudioUnitScope_Global;
    propertyEvent.mArgument.mProperty.mElement = 0;
	
	OSStatus err = AUEventListenerAddEventType(_auEventListener, NULL, &propertyEvent);	
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUEventListenerAddEventType(kAudioUnitProperty_BypassEffect) failed: %i", err);	

    propertyEvent.mEventType = kAudioUnitEvent_PropertyChange;
    propertyEvent.mArgument.mProperty.mAudioUnit = audioUnit;
    propertyEvent.mArgument.mProperty.mPropertyID = kAudioUnitProperty_PresentPreset;
    propertyEvent.mArgument.mProperty.mScope = kAudioUnitScope_Global;
    propertyEvent.mArgument.mProperty.mElement = 0;
	
	err = AUEventListenerAddEventType(_auEventListener, NULL, &propertyEvent);	
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUEventListenerAddEventType(kAudioUnitProperty_PresentPreset) failed: %i", err);	
}

- (void) stopListeningForParameterChangesOnAudioUnit:(AudioUnit)audioUnit
{
	NSParameterAssert(NULL != audioUnit);

	AudioUnitEvent propertyEvent;
    propertyEvent.mEventType = kAudioUnitEvent_PropertyChange;
    propertyEvent.mArgument.mProperty.mAudioUnit = audioUnit;
    propertyEvent.mArgument.mProperty.mPropertyID = kAudioUnitProperty_BypassEffect;
    propertyEvent.mArgument.mProperty.mScope = kAudioUnitScope_Global;
    propertyEvent.mArgument.mProperty.mElement = 0;
	
	OSStatus err = AUEventListenerRemoveEventType(_auEventListener, NULL, &propertyEvent);	
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUEventListenerRemoveEventType(kAudioUnitProperty_BypassEffect) failed: %i", err);	
	
    propertyEvent.mEventType = kAudioUnitEvent_PropertyChange;
    propertyEvent.mArgument.mProperty.mAudioUnit = audioUnit;
    propertyEvent.mArgument.mProperty.mPropertyID = kAudioUnitProperty_PresentPreset;
    propertyEvent.mArgument.mProperty.mScope = kAudioUnitScope_Global;
    propertyEvent.mArgument.mProperty.mElement = 0;
	
	err = AUEventListenerRemoveEventType(_auEventListener, NULL, &propertyEvent);	
	if(noErr != err)
		NSLog(@"SFBAudioUnitUI: AUEventListenerRemoveEventType(kAudioUnitProperty_PresentPreset) failed: %i", err);	
}

- (BOOL) hasCocoaView
{
	UInt32 dataSize = 0;
	Boolean writable = 0;
	
	ComponentResult err = AudioUnitGetPropertyInfo([self audioUnit],
												   kAudioUnitProperty_CocoaUI, 
												   kAudioUnitScope_Global,
												   0, 
												   &dataSize, 
												   &writable);

	return (0 < dataSize && noErr == err);
}

- (NSView *) getCocoaView
{
	NSView *theView = nil;
	UInt32 dataSize = 0;
	Boolean writable = 0;

	ComponentResult err = AudioUnitGetPropertyInfo([self audioUnit],
												   kAudioUnitProperty_CocoaUI, 
												   kAudioUnitScope_Global, 
												   0,
												   &dataSize,
												   &writable);

	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitGetPropertyInfo(kAudioUnitProperty_CocoaUI) failed: %i", err);
		return nil;
	}

	// If we have the property, then allocate storage for it.
	AudioUnitCocoaViewInfo *cocoaViewInfo = (AudioUnitCocoaViewInfo*) malloc(dataSize);
	err = AudioUnitGetProperty([self audioUnit], 
							   kAudioUnitProperty_CocoaUI, 
							   kAudioUnitScope_Global, 
							   0, 
							   cocoaViewInfo, 
							   &dataSize);

	if(noErr != err) {
		NSLog(@"SFBAudioUnitUI: AudioUnitGetProperty(kAudioUnitProperty_CocoaUI) failed: %i", err);
		return nil;
	}
	
	// Extract useful data.
	unsigned	numberOfClasses		= (dataSize - sizeof(CFURLRef)) / sizeof(CFStringRef);
	NSString	*viewClassName		= (NSString *)(cocoaViewInfo->mCocoaAUViewClass[0]);
	CFStringRef	path				= CFURLCopyPath(cocoaViewInfo->mCocoaAUViewBundleLocation);
	NSBundle	*viewBundle			= [NSBundle bundleWithPath:(NSString *)path];
	Class		viewClass			= [viewBundle classNamed:viewClassName];

	CFRelease(path), path = nil;
	
	if([viewClass conformsToProtocol:@protocol(AUCocoaUIBase)]) {
		id factory = [[[viewClass alloc] init] autorelease];
		theView = [factory uiViewForAudioUnit:[self audioUnit] withSize:NSZeroSize];
	}

	// Delete the cocoa view info stuff.
	if(cocoaViewInfo) {
		for(unsigned i = 0; i < numberOfClasses; ++i)
			CFRelease(cocoaViewInfo->mCocoaAUViewClass[i]);

		CFRelease(cocoaViewInfo->mCocoaAUViewBundleLocation);
		free(cocoaViewInfo);
	}

	return theView;
}

- (void) presetDoubleClicked:(id)sender
{
	
#pragma unused(sender)
	
	NSIndexSet *selectedIndexes = [_presetsOutlineView selectedRowIndexes];
	id presetInfo = [_presetsOutlineView itemAtRow:[selectedIndexes firstIndex]];
	
	NSNumber *presetNumber = [presetInfo objectForKey:@"presetNumber"];
	NSString *presetName = [presetInfo objectForKey:@"presetName"];
	NSString *presetPath = [presetInfo objectForKey:@"presetPath"];
	
	[self selectPresetNumber:presetNumber presetName:presetName presetPath:presetPath];
}

- (void) selectPresetNumber:(NSNumber *)presetNumber presetName:(NSString *)presetName presetPath:(NSString *)presetPath
{
	// nil indicates a preset category that cannot be double-clicked
	if(nil == presetNumber) {
		NSBeep();
		return;
	}
	
	if(-1 == [presetNumber intValue])
		[self loadCustomPresetFromURL:[NSURL fileURLWithPath:presetPath]];
	else
		[self loadFactoryPresetNumber:presetNumber presetName:presetName];
}

@end
