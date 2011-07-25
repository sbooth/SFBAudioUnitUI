/*
 *  Copyright (C) 2007 - 2011 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SFBAudioUnitUISaveAUPresetSheet.h"

@implementation SFBAudioUnitUISaveAUPresetSheet

- (id) init
{
	return [super initWithWindowNibName:@"SFBAudioUnitUISaveAUPresetSheet"];
}

- (void) dealloc
{
	[_presetName release], _presetName = nil;
	
	[super dealloc];
}

- (IBAction) ok:(id)sender
{

#pragma unused(sender)

    [[NSApplication sharedApplication] endSheet:[self window] returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{

#pragma unused(sender)

    [[NSApplication sharedApplication] endSheet:[self window] returnCode:NSCancelButton];
}

- (NSString *) presetName
{
	return [[_presetName retain] autorelease];
}

- (void) setPresetName:(NSString *)presetName
{
	[_presetName release];
	_presetName = [presetName copy];
}

- (int) presetDomain
{
	return _presetDomain;
}

- (void) setPresetDomain:(int)presetDomain
{
	_presetDomain = presetDomain;
}

@end
