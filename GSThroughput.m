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
#import	<Foundation/NSLock.h>
#import	<Foundation/NSDebug.h>
#import	<Foundation/NSThread.h>
#import	<Foundation/NSValue.h>

#import	"GSThroughput.h"
#import	"GSTicker.h"

#if !defined (GNUSTEP)
#import  "GNUstep.h"
#endif


NSString * const GSThroughputNotification = @"GSThroughputNotification";
NSString * const GSThroughputCountKey = @"Count";
NSString * const GSThroughputMaximumKey = @"Maximum";
NSString * const GSThroughputMinimumKey = @"Maximum";
NSString * const GSThroughputTimeKey = @"Time";
NSString * const GSThroughputTotalKey = @"Total";

#define	MAXDURATION	24.0*60.0*60.0

static NSLock		*classLock = nil;
static NSHashTable	*allObjects = nil;

@class	GSThroughputThread;

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
  NSRecursiveLock	*lock;
} Item;
#define	my	((Item*)_data)

#define	cseconds	((CountInfo*)my->seconds)
#define	cminutes	((CountInfo*)my->minutes)
#define	cperiods	((CountInfo*)my->periods)
#define	dseconds	((DurationInfo*)my->seconds)
#define	dminutes	((DurationInfo*)my->minutes)
#define	dperiods	((DurationInfo*)my->periods)

static SEL	lSel;
static void (*lImp)(NSRecursiveLock*, SEL);
static SEL	uSel;
static void (*uImp)(NSRecursiveLock*, SEL);

#define	DOLOCK() \
{ \
  (*lImp)(my->lock, lSel); \
}

#define	UNLOCK() \
{ \
  (*uImp)(my->lock, uSel); \
}



@implementation	GSThroughput (Private)

+ (void) newSecond: (id)userInfo
{
  NSArray	*a = [self allInstances];
  NSEnumerator	*e = [a objectEnumerator];
  GSThroughput	*i;

  while ((i = (GSThroughput*)[e nextObject]) != nil)
    {
      [i _update];
    }
}

- (void) _update
{
  NSTimeInterval        base;
  unsigned	        tick;

  DOLOCK()
  base = GSTickerTimeStart();
  tick = GSTickerTimeTick();
  if (my->numberOfPeriods > 0)
    {
      unsigned	i;

      if (my->supportDurations)
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
              if (my->supportDurations)
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
  UNLOCK()
}

@end



@implementation	GSThroughput

+ (NSArray*) allInstances
{
  NSArray	*a;

  [classLock lock];
  a = NSAllHashTableObjects(allObjects);
  [classLock unlock];
  return a;
}

+ (NSString*) description
{
  NSMutableString	*ms;
  NSArray		*a;
  NSEnumerator		*e;
  GSThroughput		*c;

  a = [[self allInstances] sortedArrayUsingSelector: @selector(compare:)];
  ms = [NSMutableString stringWithString: [super description]];
  e = [a objectEnumerator];
  while ((c = (GSThroughput*)[e nextObject]) != nil)
    {
      [ms appendFormat: @"\n%@", [c description]];
    }
  return ms;
}

+ (void) initialize
{
  if (nil == classLock)
    {
      classLock = [NSLock new];
      ASSIGN(allObjects, [NSHashTable weakObjectsHashTable]); 
      lSel = @selector(lock);
      lImp = (void (*)(id,SEL))[NSRecursiveLock
	instanceMethodForSelector: lSel];
      uSel = @selector(unlock);
      uImp = (void (*)(id,SEL))[NSRecursiveLock
	instanceMethodForSelector: uSel];
    }
}

+ (void) setTick: (BOOL)aFlag
{
  if (aFlag)
    {
      [GSTicker registerObserver: (id<GSTicker>)self userInfo: nil];
    }
  else
    {
      [GSTicker unregisterObserver: (id<GSTicker>)self];
    }
}

+ (void) tick
{
  [self newSecond: nil];
}

- (void) add: (unsigned)count
{
  if (my->supportDurations)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"-add: called when set for durations"];
    }
  DOLOCK()
  if (my->numberOfPeriods == 0)
    {
      cseconds[0].cnt += count; // Total
      cseconds[1].cnt += count; // Current minute
    }
  else
    {
      cseconds[my->second].cnt += count;
    }
  UNLOCK()
}

- (void) add: (unsigned)count duration: (NSTimeInterval)length
{
  if (NO == my->supportDurations)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"-add:duration: called when not set for durations"];
    }

  DOLOCK()
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
  UNLOCK()
}

- (void) addDuration: (NSTimeInterval)length
{
  unsigned      from;
  unsigned      to;

  if (NO == my->supportDurations)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"-addDuration: called when not set for durations"];
    }

  DOLOCK()
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
  UNLOCK()
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
      RELEASE(my->name);
      RELEASE(my->lock);
      NSZoneFree(NSDefaultMallocZone(), _data);
      _data = 0;
    }
  DEALLOC
}

static void 
appendCountInfo(CountInfo *info, NSMutableString *m, NSTimeInterval base)
{
  NSDate	*d = [NSDate alloc];

  d = [d initWithTimeIntervalSinceReferenceDate: info->tick + base];
  [m appendFormat: @"%u, %@\n", info->cnt, d];
  RELEASE(d);
}

static void 
appendDurationInfo(DurationInfo *info, NSMutableString *m, NSTimeInterval base)
{
  NSDate	*d = [NSDate alloc];

  d = [d initWithTimeIntervalSinceReferenceDate: info->tick + base];
  if (info->cnt)
    {
      [m appendFormat: @"%u, %g, %g, %g, %@\n",
	info->cnt, info->max, info->min, info->sum, d];
    }
  else
    {
      [m appendFormat: @"0, -, -, -, %@\n", d];
    }
  RELEASE(d);
}

- (NSString*) description
{
  NSMutableString	*m;

  ENTER_POOL
  NSTimeInterval	baseTime = GSTickerTimeStart();
  unsigned		tick;
  NSString		*n;
  unsigned		i;

  DOLOCK()
  if ((n = my->name) == nil)
    {
      n = [super description];
    }
  m = [n mutableCopy];

  if (my->numberOfPeriods == 0)
    {
      if (my->supportDurations)
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
      if (my->supportDurations)
	{
	  [m appendString: @"\nSeconds in current minute:\n"];
	  if (my->second > 0)
	    {
	      tick = 0;
	      for (i = 0; i < my->second; i++)
		{
		  DurationInfo	*info = &dseconds[i];

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendDurationInfo(info, m, baseTime);
		    }
		}
	    }

	  [m appendString: @"\nPrevious minutes in current period:\n"];
	  if (my->minute > 0)
	    {
	      tick = 0;
	      for (i = 0; i < my->minute; i++)
		{
		  DurationInfo	*info = &dminutes[i];

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendDurationInfo(info, m, baseTime);
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
		  DurationInfo	*info = &dperiods[i];

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendDurationInfo(info, m, baseTime);
		    }
		}
	      /* Periods from current cycle
	       */
	      for (i = 0; i < my->period; i++)
		{
		  DurationInfo	*info = &dperiods[i];

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendDurationInfo(info, m, baseTime);
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

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendCountInfo(info, m, baseTime);
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

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendCountInfo(info, m, baseTime);
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

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendCountInfo(info, m, baseTime);
		    }
		}
	      /* Periods from current cycle
	       */
	      for (i = 0; i < my->period; i++)
		{
		  CountInfo		*info = &cperiods[i];

		  if (info->tick != tick)
		    {
		      tick = info->tick;
		      appendCountInfo(info, m, baseTime);
		    }
		}
	    }
	}
    }
  UNLOCK()
  LEAVE_POOL
  return AUTORELEASE(m);
}

- (NSTimeInterval) endDuration
{
  NSTimeInterval    ti;

  DOLOCK()
  if (my->started > 0.0)
    {
      ti = GSTickerTimeNow() - my->started;
      my->event = nil;
      my->started = 0.0;
      [self addDuration: ti];
    }
  else
    {
      ti = 0.0;
    }
  UNLOCK()
  return ti;
}

- (BOOL) enableNotifications: (BOOL)flag
{
  BOOL  old;

  DOLOCK()
  old = my->notify;
  my->notify = flag;
  UNLOCK()
  return old;
}

- (NSTimeInterval) endDuration: (unsigned)count
{
  NSTimeInterval    ti;

  DOLOCK()
  if (my->started > 0.0)
    {
      ti = GSTickerTimeNow() - my->started;
      [self add: count duration: ti];
      my->event = nil;
      my->started = 0.0;
    }
  else
    {
      ti = 0.0;
    }
  UNLOCK()
  return ti;
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

      my->lock = [NSRecursiveLock new];
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
      [classLock lock];
      [allObjects addObject: self];
      [classLock unlock];
    }
  return self;
}

- (NSString*) name
{
  NSString	*name;

  DOLOCK()
  name = RETAIN(my->name);
  UNLOCK()
  return AUTORELEASE(name);
}

- (void) setName: (NSString*)name
{
  DOLOCK()
  [name retain];
  [my->name release];
  my->name = name;
  UNLOCK()
}

- (void) startDuration: (NSString*)name
{
  if (NO == my->supportDurations)
    {
      [NSException raise: NSInternalInconsistencyException
        format: @"-startDuration: for '%@' when not set for durations", name];
    }
  DOLOCK()
  if (0.0 != my->started)
    {
      UNLOCK()
      [NSException raise: NSInternalInconsistencyException
        format: @"-startDuration: for '%@' when already started", name];
    }
  if (my->event != nil)
    {
      NSString	*e = AUTORELEASE(RETAIN(my->event));

      UNLOCK()
      [NSException raise: NSInternalInconsistencyException
        format: @"-startDuration: for '%@' nested inside '%@'",
	e, name];
    }
  my->started = GSTickerTimeNow();
  my->event = name;
  UNLOCK()
}

@end

