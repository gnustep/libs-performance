/** 
   Copyright (C) 2005-2008 Free Software Foundation, Inc.
   
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:	October 2005
   
   This file is part of the Performance Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

   $Date$ $Revision$
   */ 

#ifndef	INCLUDED_GSThroughput_H
#define	INCLUDED_GSThroughput_H

#import	<Foundation/NSObject.h>

@class	NSArray;
@class	NSString;

extern NSString * const GSThroughputNotification;
extern NSString * const GSThroughputCountKey;
extern NSString * const GSThroughputMaximumKey;
extern NSString * const GSThroughputMinimumKey;
extern NSString * const GSThroughputTimeKey;
extern NSString * const GSThroughputTotalKey;

/**
 * <p>The GSThroughput class is used maintain statistics about the number
 * of events or the duration of operations in your software.
 * </p>
 * <p>For performance reasons, the class avoids locking and you must ensure
 * that an instance of the class is only ever used by a single thread
 * (the one in which it was created).  You are responsible for ensuring
 * that a run loop runs in each thread in which you use an instance, so that
 * stats can be updated for that thread every second.
 * </p>
 * <p>You create an instance of the class for each event/operation that you
 * are interested in monitoring, and you call the -add: or -addDuration:
 * method to record events.<br />
 * For duration logging, you may also use the -startDuration: and
 * -endDuration methods to handle adding of the amount of time taken between
 * the two calls.
 * </p>
 * <p>To dump a record of the gathered statistics, you may call the
 * -description method of an instance or the class +description method
 * to dump statistics for all instances in the current thread.<br />
 * If you need to gather a record for all the threads you use, you must
 * generate a dump in each thread and combine the results.
 * </p>
 * <p>To be notified of statistics at the end of each minute, you may call
 * the -enableNotifications: method for an instance.  The notifications are
 * generated in the thread that instance belongs to.
 * </p>
 */
@interface	GSThroughput : NSObject
{
  void	*_data;
}

/**
 * Return all the current throughput measuring objects in the current thread.
 * NB. This does not return instances from other threads.
 */
+ (NSArray*) allInstances;

/**
 * Return a report on all GSThroughput instances in the current thread...<br />
 * This calls the [GSThroughput-description] method of the individual instances
 * to get a report on each one.<br />
 * The results are ordered alphabetically by name of the instances (an
 * instance without a name is treated as having an empty string as a name).
 */
+ (NSString*) description;

/**
 * Instructs the monitoring system to use a timer at the start of each second
 * for keeping its idea of the current time up to date.  This timer is used
 * to call the +tick method in the current thread.<br />
 * Passing a value of NO for aFlag will turn off the timer for the current
 * thread.<br />
 * For the timer to work, the thread's runloop must be running.<br />
 * Keeping the notion of the current time up to date is important for
 * instances configured to record stats broken down over a number of periods,
 * since the periodic breakdown must be adjusted each second.
 */
+ (void) setTick: (BOOL)aFlag;

/**
 * Updates the monitoring system's notion of the current time for all
 * instances associated with the current thread.<br />
 * This should be called at the start of each second (or more often) if
 * you want an accurate breakdown of monitoring by the second.<br />
 * If you don't want to call this yourself, you can call +setTick: to
 * have it called automatically.<br />
 * If you are not using any instances of the class configured to maintain
 * a breakdown of stats by periods, you do not need to call this method.
 */
+ (void) tick;

/**
 * Add to the count of the number of transactions for the receiver.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned off.
 */
- (void) add: (unsigned)count;

/**
 * Adds a record for multiple events of the specified
 * <em>total</em> duration.<br />
 * This is useful where you know a lot of similar events have completed
 * in a particular period of time, but can't afford to measure the
 * duration of the individual events because the timing overheads
 * would be too great.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned on.
 */
- (void) add: (unsigned)count duration: (NSTimeInterval)length;

/**
 * Adds a record for a single event of the specified duration.<br />
 * You may use this method only if the receiver was initialised with
 * duration logging turned on.
 */
- (void) addDuration: (NSTimeInterval)length;

/**
 * Returns a string describing the status of the receiver.<br />
 * For an instance configured to maintain a periodic breakdown of stats,
 * this reports information for the current second, all seconds in the
 * current minute, all minutes in the current period, and all periods
 * in the configured number of periods.<br />
 * For an instance configured with no periodic breakdown, this produces
 * a short summary of the total count of events and, where durations are used,
 * the maximum, minimum and average duration of events.
 */
- (NSString*) description;

/** Sets a flag to say whether the receiver will send GSThroughputNotification
 * at the end of each minute to provide information about statistics.<br />
 * The method returnes the previous setting. The initial setting is NO.<br />
 * The notification object is the reciever, and the user info dictionary
 * contains some or all of the following keys depending on how the receiver
 * was configured:
 * <deflist>
 *   <term>GSThroughputCountKey</term>
 *   <desc>The number of events recorded (unsigned integer number)</desc>
 *   <term>GSThroughputMaximumKey</term>
 *   <desc>The maximum event duration (double floating point number)</desc>
 *   <term>GSThroughputMinimumKey</term>
 *   <desc>The minimum event duration (double floating point number)
 *   or -1.0 if no events occurred during the minute.</desc>
 *   <term>GSThroughputTimeKey</term>
 *   <desc>The time of the start of the minute (an NSDate)</desc>
 *   <term>GSThroughputTotalKey</term>
 *   <desc>The sum of event durations (double floating point number)</desc>
 * </deflist>
 */
- (BOOL) enableNotifications: (BOOL)flag;

/**
 * Ends duration recording for the current event started by a matching
 * call to the -startDuration: method.<br />
 * Calls to this method without a matching call to -startDuration: are
 * quietly ignored.  This is useful if you wish to time a function or
 * method by starting/ending timing before/after calling it, but also
 * want the function/method to be able to end timing of itsself before
 * it calls another function/method.
 */
- (void) endDuration;

/**
 * Acts like -endDuration but records the duration as a total for
 * count events (if count is zero then this ends the interval started
 * by the corresponding -startDuration: call, but nothing is logged).<br />
 * This can be used when recording multiple events where the overhead of
 * timing each event individually would be too great.
 */
- (void) endDuration: (unsigned)count;

/**
 * Initialises the receiver for duration logging (in the current thread only)
 * for fifteen minute periods over the last twentyfour hours.
 */
- (id) init;

/** <init />
 * <p>Initialises the receiver to maintain stats (for the current thread only)
 * over a particular time range, specifying whether duration statistics are
 * to be maintained, or just event/transaction counts.
 * </p>
 * <p>If the specified numberOfPeriods or minutesPerPeriod is zero, only a
 * running total is maintained rather than a per-second breakdown for the
 * current minute and per minute breakdown for the current period and
 * period breakdown for the number of periods.
 * </p>
 * <p>If all instances in a thread are initialised with numberOfPeriods or
 * minutesPerPeriod of zero, the +tick method does not need to be called and
 * +setTick: should not be used.
 * </p>
 */
- (id) initWithDurations: (BOOL)aFlag
	      forPeriods: (unsigned)numberOfPeriods
		ofLength: (unsigned)minutesPerPeriod;

/**
 * Return the name of this instance (as set using -setName:).<br />
 * This is used in the -description method and for ordering instances
 * in the +description method.
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
 * duration logging turned on.<br />
 * Use of this method if the reciever does not support duration logging
 * or if the method has already been called without a matching call to
 * -endDuration will cause an exception to be raised.
 */
- (void) startDuration: (NSString*)name;

@end

#endif

