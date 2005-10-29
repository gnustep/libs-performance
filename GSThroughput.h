/** 
   Copyright (C) 2005 Free Software Foundation, Inc.
   
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:	October 2005
   
   This file is part of the Performance Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

   $Date$ $Revision$
   */ 

#ifndef	INCLUDED_GSThroughput_H
#define	INCLUDED_GSThroughput_H

#include	<Foundation/NSObject.h>
#include	<Foundation/NSArray.h>

/**
 * The GSThroughput class is used maintain statistics about the number
 * of events or the duration of operations in your software.<br />
 * For performance reasons, the class avoids locking and you must ensure
 * that an instance of the class is only ever used by a single thread
 * (the one in which it was created).
 */
@interface	GSThroughput : NSObject
{
}

/**
 * Return all the current throughput measuring objects in the current thread...
 */
+ (NSArray*) allInstances;

/**
 * Return a report on all GSThroughput instances in the current thread...
 * calls the [GSThroughput-description] method of the individual instances
 * to get a report on each one.
 */
+ (NSString*) description;

/**
 * Instructs the monitoring system to use a timer at the specified interval
 * for keeping its idea of the current time up to date.  This timer is used
 * by all instances associated with the current thread.
 */
+ (void) setTick: (NSTimeInterval)interval;

/**
 * Updates the monitoring system's notion of the current time for all
 * instances associated with the current thread.<br />
 * This should be called at the start of each second (or more often) if
 * you want accurate monitoring by the second.
 */
+ (void) tick;

/**
 * Add to the count of the number of transactions in the current second.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned off.
 */
- (void) add: (unsigned)count;

/**
 * Adds a record for a single event of the specified duration.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned on.
 */
- (void) addDuration: (NSTimeInterval)length;

/**
 * Returns a string describing the status of the receiver for debug/reporting.
 */
- (NSString*) description;

/**
 * Ends duration recording for the current event started by a matching
 * call to the -startDuration: method.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned on.
 */
- (void) endDuration;

/**
 * Initialises the receiver for duration logging (in the current thread only)
 * for fifteen minute periods over the last twentyfour hours.
 */
- (id) init;

/** <init />
 * Initialises the receiver to maintain stats (for the current thread only)
 * over a particular time range, specifying whether duration statistics are
 * to be maintained, or just event/transaction counts.
 */
- (id) initWithDurations: (BOOL)aFlag
	      forPeriods: (unsigned)numberOfPeriods
		ofLength: (unsigned)minutesPerPeriod;

/**
 * Return the name of this instance (as set using -setName:)
 */
- (NSString*) name;

/**
 * Sets the name of this instance.
 */
- (void) setName: (NSString*)name;

/**
 * Starts recording the duration of an event.  This must be followed by
 * a matching call to the -endDuration method.<br />
 * The name argument is used to identify the location of the call for
 * debugging/logging purposes, and you must ensure that the string
 * continues to exist up to the point where -endDuration is called,
 * as the receiver will not retain it.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned on.
 */
- (void) startDuration: (NSString*)name;

@end

#endif

