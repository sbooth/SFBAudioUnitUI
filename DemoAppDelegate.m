/*
 *  Copyright (C) 2009 - 2011 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "DemoAppDelegate.h"
#import "SFBAudioUnitUIWindowController.h"

#include <AudioUnit/AudioUnit.h>

@implementation DemoAppDelegate

- (id) init
{
	if((self = [super init])) {
		// Set up the AUGraph
		OSStatus err = NewAUGraph(&_graph);
		if(noErr != err) {
			[self release];
			return nil;
		}
		
		// The graph will look like:
		// Generator -> Peak Limiter -> Output
		AudioComponentDescription desc;
		
		// Set up the generator node
		desc.componentType			= kAudioUnitType_Generator;
		desc.componentSubType		= kAudioUnitSubType_ScheduledSoundPlayer;
		desc.componentManufacturer	= kAudioUnitManufacturer_Apple;
		desc.componentFlags			= 0;
		desc.componentFlagsMask		= 0;
		
		AUNode generator;
		err = AUGraphAddNode(_graph, &desc, &generator);
		if(noErr != err) {
			[self release];
			return nil;
		}
		
		// Set up the peak limiter node
		desc.componentType			= kAudioUnitType_Effect;
		desc.componentSubType		= kAudioUnitSubType_GraphicEQ;
		desc.componentManufacturer	= kAudioUnitManufacturer_Apple;
		desc.componentFlags			= 0;
		desc.componentFlagsMask		= 0;
		
		AUNode limiter;
		err = AUGraphAddNode(_graph, &desc, &limiter);
		if(noErr != err) {
			[self release];
			return nil;
		}
		
		// Set up the output node
		desc.componentType			= kAudioUnitType_Output;
		desc.componentSubType		= kAudioUnitSubType_DefaultOutput;
		desc.componentManufacturer	= kAudioUnitManufacturer_Apple;
		desc.componentFlags			= 0;
		desc.componentFlagsMask		= 0;

		AUNode output;
		err = AUGraphAddNode(_graph, &desc, &output);
		if(noErr != err) {
			[self release];
			return nil;
		}
		
		// Open, initialize and start the graph
		err = AUGraphOpen(_graph);
		if(noErr != err) {
			[self release];
			return nil;
		}
		
		err = AUGraphInitialize(_graph);
		if(noErr != err) {
			[self release];
			return nil;
		}

		// Get the node info for the UI
		err = AUGraphNodeInfo(_graph, limiter, NULL, &_au);
		if(noErr != err)
			if(noErr != err) {
				[self release];
				return nil;
			}
	}
	return self;
}

- (void) dealloc
{
	OSStatus err = AUGraphClose(_graph);
//	if(noErr != err)
//		return err;
	
	err = DisposeAUGraph(_graph);
//	if(noErr != err)
//		return err;
	
	_graph = NULL;
	_au = NULL;

	[super dealloc];
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
	SFBAudioUnitUIWindowController *wc = [[SFBAudioUnitUIWindowController alloc] init];
	
	[wc setAudioUnit:_au];
	[wc showWindow:self];
}

@end
