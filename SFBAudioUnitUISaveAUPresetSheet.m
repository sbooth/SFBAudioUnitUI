/*
 *  Copyright (C) 2007 - 2009 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "SFBAudioUnitUISaveAUPresetSheet.h"

@implementation SFBAudioUnitUISaveAUPresetSheet

- (id) init
{
	if((self = [super init])) {
		BOOL result = [NSBundle loadNibNamed:@"SFBAudioUnitUISaveAUPresetSheet" owner:self];
		if(NO == result) {
			NSLog(@"Missing resource: \"SFBAudioUnitUISaveAUPresetSheet.nib\".");
			[self release];
			return nil;
		}		
	}
	return self;
}

- (void) dealloc
{
	[_presetName release], _presetName = nil;
	
	[super dealloc];
}

- (NSWindow *) sheet
{
	return [[_sheet retain] autorelease];
}

- (IBAction) ok:(id)sender
{
    [[NSApplication sharedApplication] endSheet:[self sheet] returnCode:NSOKButton];
}

- (IBAction) cancel:(id)sender
{
    [[NSApplication sharedApplication] endSheet:[self sheet] returnCode:NSCancelButton];
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
