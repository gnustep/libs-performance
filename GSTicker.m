/* -*-objc-*- */

/** Implementation of GSTicker for GNUStep
   Copyright (C) 2005 Free Software Foundation, Inc.
   
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:	November 2005
   
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

#import	<Foundation/NSArray.h>
#import	<Foundation/NSDate.h>
#import	<Foundation/NSDictionary.h>
#import	<Foundation/NSThread.h>
#import	<Foundation/NSString.h>
#import	<Foundation/NSTimer.h>

#import	<GNUstepBase/GNUstep.h>

#import	"GSTicker.h"

static Class		NSDateClass = 0;
static SEL		tiSel = 0;
static NSTimeInterval	(*tiImp)(Class,SEL) = 0;

static NSTimeInterval	baseTime = 0;
static NSTimeInterval	lastTime = 0;
static NSDate		*startDate = nil;

@interface	GSTickerObservation : NSObject
{
  @public
  id<GSTicker>	observer;
  id		userInfo;
}
- (void) fire: (NSArray*)live;
@end

@implementation	GSTickerObservation
- (void) fire: (NSArray*)live
{
  if ([live indexOfObjectIdenticalTo: self] != NSNotFound)
    {
      [observer newSecond: userInfo];
    }
}
@end


@interface	GSTickerThread : NSObject
{
  @public
  NSTimer		*theTimer;
  NSMutableArray	*observers;
}
@end

@implementation	GSTickerThread
- (void) dealloc
{
  [theTimer invalidate];
  theTimer = nil;
  DESTROY(observers);
  [super dealloc];
}
- (id) init
{
  NSTimeInterval	ti = GSTickerTimeNow();

  observers = [NSMutableArray new];
  theTimer = [NSTimer scheduledTimerWithTimeInterval: ti - (int)ti
					      target: [GSTicker class]
					    selector: @selector(_tick:)
					    userInfo: self
					     repeats: NO];
  return self;
}
@end

@interface	GSTicker (Private)
+ (void) _tick: (NSTimer*)t;
@end

inline NSTimeInterval	GSTickerTimeLast()
{
  return lastTime;
}

inline NSTimeInterval	GSTickerTimeStart()
{
  if (baseTime == 0)
    {
      return GSTickerTimeNow();
    }
  return baseTime;
}

inline unsigned	GSTickerTimeTick()
{
  NSTimeInterval	start = GSTickerTimeStart();

  return (GSTickerTimeLast() - start) + 1;
}


NSTimeInterval	GSTickerTimeNow()
{
  if (baseTime == 0)
    {
      NSDateClass = [NSDate class];
      tiSel = @selector(timeIntervalSinceReferenceDate);
      tiImp
	= (NSTimeInterval (*)(Class,SEL))[NSDateClass methodForSelector: tiSel];
      baseTime = lastTime = (*tiImp)(NSDateClass, tiSel);
      return baseTime;
    }
  else
    {
      NSTimeInterval	now;

      /*
       * If the clock has been reset so that time has gone backwards,
       * we adjust the baseTime so that lastTime >= baseTime is true.
       */
      now = (*tiImp)(NSDateClass, tiSel);
      if (now < lastTime)
	{
	  baseTime -= (lastTime - now);
	}
      lastTime = now;
      return lastTime;
    }
}

@implementation	GSTicker

+ (NSDate*) last
{
  return [NSDateClass dateWithTimeIntervalSinceReferenceDate:
    GSTickerTimeLast()];
}

+ (void) newSecond: (id)userInfo
{
}

+ (NSDate*) now
{
  return [NSDateClass dateWithTimeIntervalSinceReferenceDate:
    GSTickerTimeNow()];
}

+ (void) registerObserver: (id<GSTicker>)anObject
		 userInfo: (id)userInfo
{
  GSTickerThread	*tt;
  GSTickerObservation	*to;
  unsigned		count;

  tt = [[[NSThread currentThread] threadDictionary]
    objectForKey: @"GSTickerThread"];
  if (tt == nil)
    {
      tt = [GSTickerThread new];
      [[[NSThread currentThread] threadDictionary]
	setObject: tt forKey: @"GSTickerThread"];
      RELEASE(tt);
    }
  count = [tt->observers count];
  while (count-- > 0)
    {
      to = [tt->observers objectAtIndex: count];

      if (to->observer == anObject)
	{
	  return;	// Already registered.
	}
    }
  to = [GSTickerObservation new];
  to->observer = anObject;
  to->userInfo = userInfo;
  [tt->observers addObject: to];
  RELEASE(to);
}

+ (NSDate*) start
{
  if (startDate == nil)
    {
      startDate = [NSDateClass alloc];
      startDate = [startDate initWithTimeIntervalSinceReferenceDate:
	GSTickerTimeStart()];
    }
  return startDate;
}

+ (unsigned) tick
{
  return GSTickerTimeTick();
}

+ (void) unregisterObserver: (id<GSTicker>)anObject
{
  GSTickerThread	*tt;

  tt = [[[NSThread currentThread] threadDictionary]
    objectForKey: @"GSTickerThread"];
  if (tt != nil)
    {
      GSTickerObservation	*to;
      unsigned			count = [tt->observers count];

      while (count-- > 0)
	{
	  to = [tt->observers objectAtIndex: count];
	  if (to->observer == anObject)
	    {
	      [tt->observers removeObjectAtIndex: count];
	      break;
	    }
	}
    }
}

+ (void) update
{
  GSTickerTimeNow();
}


- (NSDate*) last
{
  return [NSDateClass dateWithTimeIntervalSinceReferenceDate:
    GSTickerTimeLast()];
}

- (void) newSecond: (id)userInfo
{
}

- (NSDate*) now
{
  return [NSDateClass dateWithTimeIntervalSinceReferenceDate:
    GSTickerTimeNow()];
}

- (NSDate*) start
{
  if (startDate == nil)
    {
      startDate = [NSDateClass alloc];
      startDate = [startDate initWithTimeIntervalSinceReferenceDate:
	GSTickerTimeStart()];
    }
  return startDate;
}

- (unsigned) tick
{
  return GSTickerTimeTick();
}

- (void) update
{
  GSTickerTimeNow();
}

@end

@implementation	GSTicker (Private)
+ (void) _tick: (NSTimer*)t
{
  GSTickerThread	*tt = [t userInfo];

  if (tt == nil)
    {
      tt = [[[NSThread currentThread] threadDictionary]
	objectForKey: @"GSTickerThread"];
    }
  if (tt != nil && [tt->observers count] > 0)
    {
      NSTimeInterval	ti;

      if (tt->theTimer != t)
	{
	  [tt->theTimer invalidate];
	  tt->theTimer = nil;
	}

      if ([tt->observers count] > 0)
        {
          NSArray	*a = [tt->observers copy];

          GSTickerTimeNow();
          [a makeObjectsPerformSelector: @selector(fire:)
                             withObject: tt->observers];
          RELEASE(a);
        }

      ti = GSTickerTimeNow();
      tt->theTimer = [NSTimer scheduledTimerWithTimeInterval: ti - (int)ti
						      target: self
						    selector: @selector(_tick:)
						    userInfo: tt
						     repeats: NO];
    }
  else
    {
      [[[NSThread currentThread] threadDictionary]
	removeObjectForKey: @"GSTickerThread"];
    }
}
@end

