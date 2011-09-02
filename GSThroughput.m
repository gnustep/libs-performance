/* -*-objc-*- */

/** Implementation of GSThroughput for GNUStep
   Copyright (C) 2005 Free Software Foundation, Inc.
   
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

#import	<Foundation/NSArray.h>
#import	<Foundation/NSString.h>
#import	<Foundation/NSData.h>
#import	<Foundation/NSDate.h>
#import	<Foundation/NSCalendarDate.h>
#import	<Foundation/NSDictionary.h>
#import	<Foundation/NSEnumerator.h>
#import	<Foundation/NSException.h>
#import	<Foundation/NSNotification.h>
#import	<Foundation/NSHashTable.h>
#import	<Foundation/NSAutoreleasePool.h>
#import	<Foundation/NSDebug.h>
#import	<Foundation/NSThread.h>
#import	<Foundation/NSValue.h>

#import	"GSThroughput.h"
#import	"GSTicker.h"

NSString * const GSThroughputNotification = @"GSThroughputNotification";
NSString * const GSThroughputCountKey = @"Count";
NSString * const GSThroughputMaximumKey = @"Maximum";
NSString * const GSThroughputMinimumKey = @"Maximum";
NSString * const GSThroughputTimeKey = @"Time";
NSString * const GSThroughputTotalKey = @"Total";

#define	MAXDURATION	24.0*60.0*60.0

@class	GSThroughputThread;

static Class		NSDateClass = 0;
static SEL		tiSel = 0;
static NSTimeInterval	(*tiImp)(Class,SEL) = 0;

typedef	struct {
  unsigned		cnt;	// Number of events.
  unsigned		tick;	// Start time
} CountInfo;

typedef	struct {
  unsigned		cnt;	// Number of events.
  NSTimeInterval	max;	// Longest duration
  NSTimeInterval	min;	// Shortest duration
  NSTimeInterval	sum;	// Total (sum of durations for event)
  unsigned		tick;	// Start time
} DurationInfo;

typedef struct {
  void			*seconds;
  void			*minutes;
  void			*periods;
  void			*total;
  BOOL			supportDurations;
  BOOL                  notify;
  unsigned		numberOfPeriods;
  unsigned		minutesPerPeriod;
  unsigned		second;
  unsigned		minute;
  unsigned		period;
  unsigned		last;		// last tick used
  NSTimeInterval	started;	// When duration logging started.
  NSString		*event;		// Name of current event 
  NSString		*name;		// Name of this instance
  GSThroughputThread	*thread;	// Thread info
} Item;
#define	my	((Item*)_data)

#define	cseconds	((CountInfo*)my->seconds)
#define	cminutes	((CountInfo*)my->minutes)
#define	cperiods	((CountInfo*)my->periods)
#define	dseconds	((DurationInfo*)my->seconds)
#define	dminutes	((DurationInfo*)my->minutes)
#define	dperiods	((DurationInfo*)my->periods)



@interface	GSThroughputThread : NSObject
{
  @public
  NSHashTable		*instances;
}
@end

@interface	GSThroughput (Private)
+ (GSThroughputThread*) _threadInfo;
+ (void) newSecond: (GSThroughputThread*)t;
- (void) _detach;
- (void) _update;
@end



@implementation	GSThroughputThread
- (void) dealloc
{
  if (instances != 0)
    {
      NSHashEnumerator	e;
      GSThroughput	*i;

      e = NSEnumerateHashTable(instances);
      while ((i = (GSThroughput*)NSNextHashEnumeratorItem(&e)) != nil)
	{
	  [i _detach];
	}
      NSEndHashTableEnumeration(&e);
      NSFreeHashTable(instances);
      instances = 0;
    }
  [super dealloc];
}

- (id) init
{
  if (nil != (self = [super init]))
    {
      instances = NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
    }
  return self;
}

@end



@implementation	GSThroughput (Private)

+ (GSThroughputThread*) _threadInfo
{
  GSThroughputThread	*t;

  t = [[[NSThread currentThread] threadDictionary]
    objectForKey: @"GSThroughput"];
  if (t == nil)
    {
      t = [GSThroughputThread new];
      [[[NSThread currentThread] threadDictionary] setObject: t
       forKey: @"GSThroughput"];
      [t release];
    }
  return t;
}

+ (void) newSecond: (GSThroughputThread*)t
{
  NSHashEnumerator	e;
  GSThroughput		*i;

  e = NSEnumerateHashTable(t->instances);
  while ((i = (GSThroughput*)NSNextHashEnumeratorItem(&e)) != nil)
    {
      [i _update];
    }
  NSEndHashTableEnumeration(&e);
}

- (void) _detach
{
  my->thread = nil;
}

- (void) _update
{
  NSTimeInterval        base;
  unsigned	        tick;

  if (my->thread == nil)
    {
      return;
    }

  base = GSTickerTimeStart();
  tick = GSTickerTimeTick();
  if (my->numberOfPeriods > 0)
    {
      unsigned	i;

      if (my->supportDurations == YES)
	{
	  while (my->last < tick)
	    {
	      DurationInfo		*info;

	      if (my->second++ == 59)
		{
		  info = &dminutes[my->minute];
		  for (i = 0; i < 60; i++)
		    {
		      DurationInfo	*from = &dseconds[i];

		      info->cnt += from->cnt;
		      if (from->min < info->min)
			{
			  info->min = from->min;
			}
		      if (from->max > info->max)
			{
			  info->max = from->max;
			}
		      info->sum += from->sum;
		    }
                  if (my->notify == YES && my->last > 59)
                    {
                      if (info->min >= MAXDURATION)
                        {
                          info->min = -1.0;
                        }
                      [[NSNotificationCenter defaultCenter]
                        postNotificationName: GSThroughputNotification
                        object: self
                        userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithUnsignedInt: info->cnt],
                          GSThroughputCountKey,
                          [NSNumber numberWithDouble: info->max],
                          GSThroughputMaximumKey,
                          [NSNumber numberWithDouble: info->min],
                          GSThroughputMinimumKey,
                          [NSNumber numberWithDouble: info->sum],
                          GSThroughputTotalKey,
                          [NSDate dateWithTimeIntervalSinceReferenceDate:
                            base + my->last - 60],
                          GSThroughputTimeKey,
                          nil]];
                      if (info->min < 0.0)
                        {
                          info->min = MAXDURATION;
                        }
                    }
		  if (my->minute++ == my->minutesPerPeriod - 1)
		    {
		      info = &dperiods[my->period];
		      for (i = 0; i < my->minutesPerPeriod; i++)
			{
			  DurationInfo	*from = &dminutes[i];

			  info->cnt += from->cnt;
			  if (from->min > 0.0 && from->min < info->min)
			    {
			      info->min = from->min;
			    }
			  if (from->max > info->max)
			    {
			      info->max = from->max;
			    }
			  info->sum += from->sum;
			}
		      if (my->period++ == my->numberOfPeriods - 1)
			{
			  my->period = 0;
			}
		      info = &dperiods[my->period];
		      info->cnt = 0;
		      info->max = 0.0;
		      info->min = MAXDURATION;
		      info->sum = 0.0;
		      info->tick = my->last;
		      my->minute = 0;
		    }
		  info = &dminutes[my->minute];
		  info->cnt = 0;
		  info->max = 0.0;
		  info->min = MAXDURATION;
		  info->sum = 0.0;
		  info->tick = my->last;
		  my->second = 0;
		}
	      info = &dseconds[my->second];
	      info->cnt = 0;
	      info->max = 0.0;
	      info->min = MAXDURATION;
	      info->sum = 0.0;
	      info->tick = my->last;

	      my->last++;
	    }
	}
      else
	{
	  while (my->last < tick)
	    {
	      CountInfo		*info;

	      if (my->second++ == 59)
		{
		  info = &cminutes[my->minute];
		  for (i = 0; i < 60; i++)
		    {
		      info->cnt += cseconds[i].cnt;
		    }
                  if (my->notify == YES && my->last > 59)
                    {
                      [[NSNotificationCenter defaultCenter]
                        postNotificationName: GSThroughputNotification
                        object: self
                        userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithUnsignedInt: info->cnt],
                          GSThroughputCountKey,
                          [NSDate dateWithTimeIntervalSinceReferenceDate:
                            base + my->last - 60],
                          GSThroughputTimeKey,
                          nil]];
                    }
		  if (my->minute++ == my->minutesPerPeriod - 1)
		    {
		      info = &cperiods[my->period];
		      for (i = 0; i < my->minutesPerPeriod; i++)
			{
			  info->cnt += cminutes[i].cnt;
			}
		      if (my->period++ == my->numberOfPeriods - 1)
			{
			  my->period = 0;
			}
		      info = &cperiods[my->period];
		      info->cnt = 0;
		      info->tick = my->last;
		      my->minute = 0;
		    }
		  info = &cminutes[my->minute];
		  info->cnt = 0;
		  info->tick = my->last;
		  my->second = 0;
		}
	      info = &cseconds[my->second];
	      info->cnt = 0;
	      info->tick = my->last;

	      my->last++;
	    }
	}
    }
  else
    {
      while (my->last < tick)
        {
          if (my->second++ == 59)
            {
              my->second = 0;
              if (my->supportDurations == YES)
                {
                  DurationInfo		*info = &dseconds[1];

                  if (my->notify == YES && my->last > 59)
                    {
                      if (info->min == MAXDURATION)
                        {
                          info->min = -1.0;
                        }
                      [[NSNotificationCenter defaultCenter]
                        postNotificationName: GSThroughputNotification
                        object: self
                        userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithUnsignedInt: info->cnt],
                          GSThroughputCountKey,
                          [NSNumber numberWithDouble: info->max],
                          GSThroughputMaximumKey,
                          [NSNumber numberWithDouble: info->min],
                          GSThroughputMinimumKey,
                          [NSNumber numberWithDouble: info->sum],
                          GSThroughputTotalKey,
                          [NSDate dateWithTimeIntervalSinceReferenceDate:
                            base + my->last - 60],
                          GSThroughputTimeKey,
                          nil]];
                    }
                  info->cnt = 0;
                  info->max = 0.0;
                  info->min = MAXDURATION;
                  info->sum = 0.0;
                }
              else
                {
                  CountInfo		*info = &cseconds[1];

                  if (my->notify == YES && my->last > 59)
                    {
                      [[NSNotificationCenter defaultCenter]
                        postNotificationName: GSThroughputNotification
                        object: self
                        userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithUnsignedInt: info->cnt],
                          GSThroughputCountKey,
                          [NSDate dateWithTimeIntervalSinceReferenceDate:
                            base + my->last - 60],
                          GSThroughputTimeKey,
                          nil]];
                    }
                  info->cnt = 0;
                }
            }
          my->last++;
        }
    }
}

@end



@implementation	GSThroughput

+ (NSArray*) allInstances
{
  GSThroughputThread	*t;
  NSArray		*a;

  t = [[[NSThread currentThread] threadDictionary]
    objectForKey: @"GSThroughput"];
  if (t == nil)
    {
      a = nil;
    }
  else
    {
      a = NSAllHashTableObjects(t->instances);
    }
  return a;
}

+ (NSString*) description
{
  GSThroughputThread	*t;
  NSMutableString	*ms;

  ms = [NSMutableString stringWithString: [super description]];
  t = [[[NSThread currentThread] threadDictionary]
    objectForKey: @"GSThroughput"];
  if (t != nil)
    {
      NSArray		*a;
      NSEnumerator	*e;
      GSThroughput	*c;

      a = [NSAllHashTableObjects(t->instances) sortedArrayUsingSelector:
        @selector(compare:)];
      e = [a objectEnumerator];
      while ((c = (GSThroughput*)[e nextObject]) != nil)
	{
	  [ms appendFormat: @"\n%@", [c description]];
	}
    }
  return ms;
}

+ (void) initialize
{
  if (NSDateClass == 0)
    {
      NSDateClass = [NSDate class];
      tiSel = @selector(timeIntervalSinceReferenceDate);
      tiImp
	= (NSTimeInterval (*)(Class,SEL))[NSDateClass methodForSelector: tiSel];
    }
}

+ (void) setTick: (BOOL)aFlag
{
  if (aFlag == YES)
    {
      GSThroughputThread	*t = [self _threadInfo];

      [GSTicker registerObserver: (id<GSTicker>)self userInfo: t];
    }
  else
    {
      [GSTicker unregisterObserver: (id<GSTicker>)self];
    }
}

+ (void) tick
{
  [self newSecond: [self _threadInfo]];
}

- (void) add: (unsigned)count
{
  NSAssert(my->supportDurations == NO, @"configured for durations");
  if (my->numberOfPeriods == 0)
    {
      cseconds[0].cnt += count; // Total
      cseconds[1].cnt += count; // Current minute
    }
  else
    {
      cseconds[my->second].cnt += count;
    }
}

- (void) add: (unsigned)count duration: (NSTimeInterval)length
{
  NSAssert(my->supportDurations == YES, @"not configured for durations");

  if (count > 0)
    {
      NSTimeInterval	total = length;
      unsigned          from;
      unsigned          to;

      length /= count;
      if (my->numberOfPeriods == 0)
        {
          from = 0;     // total
          to = 1;       // current minute
        }
      else
        {
          from = my->second;
          to = from;
        }

      while (from <= to)
        {
          DurationInfo *info = &dseconds[from++];

          if (info->cnt == 0)
            {
              info->cnt = count;
              info->min = length;
              info->max = length;
              info->sum = total;
            }
          else
            {
              info->cnt += count;
              info->sum += total;
              if (length > info->max)
                {
                  info->max = length;
                }
              if (length < info->min)
                {
                  info->min = length;
                }
            }
        }
    }
}

- (void) addDuration: (NSTimeInterval)length
{
  unsigned      from;
  unsigned      to;

  NSAssert(my->supportDurations == YES, @"not configured for durations");
  if (my->numberOfPeriods == 0)
    {
      from = 0; // Total
      to = 1;   // Current minute
    }
  else
    {
      from = my->second;
      to = from;
    }
  while (from <= to)
    {
      DurationInfo     *info = &dseconds[from++];

      if (info->cnt++ == 0)
        {
          info->min = length;
          info->max = length;
          info->sum = length;
        }
      else
        {
          info->sum += length;
          if (length > info->max)
            {
              info->max = length;
            }
          if (length < info->min)
            {
              info->min = length;
            }
        }
    }
}

- (NSComparisonResult) compare: (id)other
{
  if ([other isKindOfClass: [GSThroughput class]] == YES)
    {
      NSString	*myName = [self name];
      NSString	*otherName = [other name];

      if (myName == nil)
        {
          myName = @"";
	}
      if (otherName == nil)
        {
          otherName = @"";
	}
      return [myName compare: otherName];
    }
  return NSOrderedAscending;
}

- (void) dealloc
{
  if (_data)
    {
      if (my->seconds != 0)
	{
	  NSZoneFree(NSDefaultMallocZone(), my->seconds);
	}
      [my->name release];
      if (my->thread != nil)
	{
	  NSHashRemove(my->thread->instances, (void*)self);
	  my->thread = nil;
	}
      NSZoneFree(NSDefaultMallocZone(), _data);
      _data = 0;
    }
  [super dealloc];
}

- (NSString*) description
{
  NSAutoreleasePool     *pool = [NSAutoreleasePool new];
  NSString		*n = my->name;
  NSMutableString	*m;
  unsigned		i;

  if (n == nil)
    {
      n = [super description];
    }
  m = [n mutableCopy];

  if (my->thread != nil)
    {
      NSTimeInterval	baseTime = GSTickerTimeStart();
      unsigned		tick;

      if (my->numberOfPeriods == 0)
	{
	  if (my->supportDurations == YES)
	    {
	      DurationInfo	*info = &dseconds[0];

	      [m appendFormat: @": cnt %u, max %g, min %g, avg %g",
		info->cnt, info->max,
		info->min == MAXDURATION ? 0.0 : info->min,
		info->cnt == 0 ? 0 : info->sum / info->cnt];
	    }
	  else
	    {
	      CountInfo	*info = &cseconds[0];

	      [m appendFormat: @": cnt %u", info->cnt];
	    }
	}
      else
	{
	  if (my->supportDurations == YES)
	    {
	      [m appendString: @"\nSeconds in current minute:\n"];
	      if (my->second > 0)
		{
		  tick = 0;
		  for (i = 0; i < my->second; i++)
		    {
		      DurationInfo		*info = &dseconds[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %g, %g, %g, %@\n",
			    info->cnt, info->max, info->min, info->sum,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}

	      [m appendString: @"\nPrevious minutes in current period:\n"];
	      if (my->minute > 0)
		{
		  tick = 0;
		  for (i = 0; i < my->minute; i++)
		    {
		      DurationInfo		*info = &dminutes[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %g, %g, %g, %@\n",
			    info->cnt, info->max, info->min, info->sum,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}

	      [m appendString: @"\nPrevious periods:\n"];
	      if (my->period > 0)
		{
		  tick = 0;
                  /* Periods from last cycle
                   */
		  for (i = my->period; i < my->numberOfPeriods; i++)
		    {
		      DurationInfo		*info = &dperiods[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %g, %g, %g, %@\n",
			    info->cnt, info->max, info->min, info->sum,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
                  /* Periods from current cycle
                   */
		  for (i = 0; i < my->period; i++)
		    {
		      DurationInfo		*info = &dperiods[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %g, %g, %g, %@\n",
			    info->cnt, info->max, info->min, info->sum,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}
	    }
	  else
	    {
	      [m appendString: @"\nSeconds in current minute:\n"];
	      if (my->second > 0)
		{
		  tick = 0;
		  for (i = 0; i < my->second; i++)
		    {
		      CountInfo		*info = &cseconds[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %@\n", info->cnt,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}

	      [m appendString: @"\nPrevious minutes in current period:\n"];
	      if (my->minute > 0)
		{
		  tick = 0;
		  for (i = 0; i < my->minute; i++)
		    {
		      CountInfo		*info = &cminutes[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %@\n", info->cnt,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}

	      [m appendString: @"\nPrevious periods:\n"];
	      if (my->period > 0)
		{
		  tick = 0;
                  /* Periods from last cycle
                   */
		  for (i = my->period; i < my->numberOfPeriods; i++)
                    {
		      CountInfo		*info = &cperiods[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %@\n", info->cnt,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
                    }
                  /* Periods from current cycle
                   */
		  for (i = 0; i < my->period; i++)
		    {
		      CountInfo		*info = &cperiods[i];
		      NSTimeInterval	ti = info->tick + baseTime;

		      if (info->tick != tick)
			{
			  tick = info->tick;
			  [m appendFormat: @"%u, %@\n", info->cnt,
			    [NSDate dateWithTimeIntervalSinceReferenceDate:
			      ti]];
			}
		    }
		}
	    }
	}
    }

  [pool release];
  return [m autorelease];
}

- (void) endDuration
{
  if (my->started > 0.0)
    {
      [self addDuration: (*tiImp)(NSDateClass, tiSel) - my->started];
      my->event = nil;
      my->started = 0.0;
    }
}

- (BOOL) enableNotifications: (BOOL)flag
{
  BOOL  old = my->notify;

  my->notify = flag;
  return old;
}

- (void) endDuration: (unsigned)count
{
  if (my->started > 0.0)
    {
      [self add: count duration: (*tiImp)(NSDateClass, tiSel) - my->started];
      my->event = nil;
      my->started = 0.0;
    }
}

- (id) init
{
  return [self initWithDurations: YES
		      forPeriods: 96
			ofLength: 15];
}

- (id) initWithDurations: (BOOL)aFlag
              forPeriods: (unsigned)numberOfPeriods
		ofLength: (unsigned)minutesPerPeriod
{
  if (nil != (self = [super init]))
    {
      NSCalendarDate	*c;	
      unsigned		i;

      _data = (Item*)NSZoneCalloc(NSDefaultMallocZone(), 1, sizeof(Item));

      /*
       * Add this instance to the current thread.
       */
      my->thread = [[self class] _threadInfo];
      NSHashInsert(my->thread->instances, (void*)self);

      my->supportDurations = aFlag;
      my->notify = NO;
      my->last = GSTickerTimeTick();

      c = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:
	GSTickerTimeLast()];

      my->second = [c secondOfMinute];
      i = [c hourOfDay] * 60 + [c minuteOfHour];

      if (numberOfPeriods < 1 || minutesPerPeriod < 1)
	{
	  /* If we are not using periods of N minutes, we must just be keeping
	   * a running total recorded second by second.
	   */
	  my->numberOfPeriods = 0;
	  my->minutesPerPeriod = 0;
	  my->minute = i;
	  my->period = 0;
	  if (my->supportDurations == YES)
	    {
	      DurationInfo	*ptr;

	      ptr = (DurationInfo*)NSZoneCalloc
		(NSDefaultMallocZone(), 2, sizeof(DurationInfo));
	      my->seconds = ptr;
	      my->minutes = 0;
	      my->periods = 0;
	      dseconds[0].tick = my->last;
	      dseconds[0].max = 0;
	      dseconds[0].min = MAXDURATION;
	      dseconds[0].sum = 0;
	      dseconds[0].cnt = 0;

	      dseconds[1].tick = my->last;
	      dseconds[1].max = 0;
	      dseconds[1].min = 0;
	      dseconds[1].sum = 0;
	      dseconds[1].cnt = 0;
	    }
	  else
	    {
	      CountInfo	*ptr;

	      ptr = (CountInfo*)NSZoneCalloc
		(NSDefaultMallocZone(), 2, sizeof(CountInfo));
	      my->seconds = ptr;
	      my->minutes = 0;
	      my->periods = 0;
	      cseconds[0].tick = my->last;
	      cseconds[0].cnt = 0;
	      cseconds[1].tick = my->last;
	      cseconds[1].cnt = 0;
	    }
	}
      else
	{
	  my->numberOfPeriods = numberOfPeriods;
	  my->minutesPerPeriod = minutesPerPeriod;

	  my->minute = i % minutesPerPeriod;
	  my->period = (i / minutesPerPeriod) % numberOfPeriods;

	  i = 60 + minutesPerPeriod + numberOfPeriods;
	  if (my->supportDurations == YES)
	    {
	      DurationInfo	*ptr;

	      ptr = (DurationInfo*)NSZoneCalloc
		(NSDefaultMallocZone(), i, sizeof(DurationInfo));
	      my->seconds = ptr;
	      my->minutes = ptr + 60;
	      my->periods = ptr + 60 + minutesPerPeriod;
	      dseconds[my->second].tick = my->last;
	      dminutes[my->minute].tick = my->last;
	      dperiods[my->period].tick = my->last;

	      for (i = 0; i < my->numberOfPeriods; i++)
		{
		  dperiods[i].min = MAXDURATION;
		}
	      for (i = 0; i < my->minutesPerPeriod; i++)
		{
		  dminutes[i].min = MAXDURATION;
		}
	      for (i = 0; i < 60; i++)
		{
		  dseconds[i].min = MAXDURATION;
		}
	    }
	  else
	    {
	      CountInfo	*ptr;

	      ptr = (CountInfo*)NSZoneCalloc
		(NSDefaultMallocZone(), i, sizeof(CountInfo));
	      my->seconds = ptr;
	      my->minutes = ptr + 60;
	      my->periods = ptr + 60 + minutesPerPeriod;
	      cseconds[my->second].tick = my->last;
	      cminutes[my->minute].tick = my->last;
	      cperiods[my->period].tick = my->last;
	    }
	}
      [c release];
    }
  return self;
}

- (NSString*) name
{
  return my->name;
}

- (void) setName: (NSString*)name
{
  [name retain];
  [my->name release];
  my->name = name;
}

- (void) startDuration: (NSString*)name
{
  NSAssert(my->supportDurations == YES && my->started == 0.0,
    NSInternalInconsistencyException);
  if (my->event != nil)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"-startDuration: for '%@' nested inside '%@'",
	my->event, name];
    }
  my->started = (*tiImp)(NSDateClass, tiSel);
  my->event = name;
}

@end

