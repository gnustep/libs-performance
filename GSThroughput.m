/* -*-objc-*- */

/** Implementation of GSThroughput for GNUStep
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

#import	<Foundation/NSArray.h>
#import	<Foundation/NSString.h>
#import	<Foundation/NSData.h>
#import	<Foundation/NSDate.h>
#import	<Foundation/NSCalendarDate.h>
#import	<Foundation/NSException.h>
#import	<Foundation/NSNotification.h>
#import	<Foundation/NSHashTable.h>
#import	<Foundation/NSAutoreleasePool.h>
#import	<Foundation/NSDebug.h>
#import	<Foundation/NSTimer.h>
#import	<Foundation/NSThread.h>

#import	"GSThroughput.h"
#import	"GSTicker.h"

#define	MAXDURATION	24.0*60.0*60.0

@class	GSThroughputThread;

static Class		NSDateClass = 0;
static SEL		tiSel = 0;
static NSTimeInterval	(*tiImp)(Class,SEL) = 0;

typedef	struct {
  unsigned		cnt;	// Number of events.
  unsigned		tick;	// Start time
} CInfo;

typedef	struct {
  unsigned		cnt;	// Number of events.
  NSTimeInterval	max;	// Longest duration
  NSTimeInterval	min;	// Shortest duration
  NSTimeInterval	sum;	// Total (sum of durations for event)
  unsigned		tick;	// Start time
} DInfo;

typedef struct {
  void			*seconds;
  void			*minutes;
  void			*periods;
  void			*total;
  BOOL			supportDurations;
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

#define	cseconds	((CInfo*)my->seconds)
#define	cminutes	((CInfo*)my->minutes)
#define	cperiods	((CInfo*)my->periods)
#define	dseconds	((DInfo*)my->seconds)
#define	dminutes	((DInfo*)my->minutes)
#define	dperiods	((DInfo*)my->periods)



@interface	GSThroughputThread : NSObject
{
  @public
  NSTimer		*theTimer;
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
  instances = NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
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
      RELEASE(t);
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
  if (my->thread != nil && my->numberOfPeriods > 0)
    {
      unsigned	tick = GSTickerTimeTick();
      unsigned	i;

      if (my->supportDurations == YES)
	{
	  while (my->last < tick)
	    {
	      DInfo		*info;

	      if (my->second++ == 59)
		{
		  info = &dminutes[my->minute];
		  for (i = 0; i < 60; i++)
		    {
		      DInfo	*from = &dseconds[i];

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
		  if (my->minute++ == my->minutesPerPeriod - 1)
		    {
		      info = &dperiods[my->period];
		      for (i = 0; i < my->minutesPerPeriod; i++)
			{
			  DInfo	*from = &dminutes[i];

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
	      CInfo		*info;

	      if (my->second++ == 59)
		{
		  info = &cminutes[my->minute];
		  for (i = 0; i < 60; i++)
		    {
		      info->cnt += cseconds[i].cnt;
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
  cseconds[my->second].cnt += count;
}

- (void) add: (unsigned)count duration: (NSTimeInterval)length
{
  NSAssert(my->supportDurations == YES, @"not configured for durations");

  if (count > 0)
    {
      NSTimeInterval	total = length;
      DInfo		*info;

      info = &dseconds[my->second];
      length /= count;
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

- (void) addDuration: (NSTimeInterval)length
{
  DInfo	*info;

  NSAssert(my->supportDurations == YES, @"not configured for durations");
  info = &dseconds[my->second];
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
  CREATE_AUTORELEASE_POOL(pool);
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
	      DInfo	*info = &dseconds[0];

	      [m appendFormat: @": cnt %u, max %g, min %g, avg %g",
		info->cnt, info->max,
		info->min == MAXDURATION ? 0.0 : info->min,
		info->cnt == 0 ? 0 : info->sum / info->cnt];
	    }
	  else
	    {
	      CInfo	*info = &cseconds[0];

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
		      DInfo		*info = &dseconds[i];
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
		      DInfo		*info = &dminutes[i];
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
		  for (i = 0; i < my->period; i++)
		    {
		      DInfo		*info = &dperiods[i];
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
		      CInfo		*info = &cseconds[i];
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
		      CInfo		*info = &cminutes[i];
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
		  for (i = 0; i < my->period; i++)
		    {
		      CInfo		*info = &cperiods[i];
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

  DESTROY(pool);
  return AUTORELEASE(m);
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
  _data = (Item*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(Item));
  memset(_data, '\0', sizeof(Item));

  /*
   * Add this instance to the current thread.
   */
  my->thread = [[self class] _threadInfo];
  NSHashInsert(my->thread->instances, (void*)self);

  my->supportDurations = aFlag;
  my->last = GSTickerTimeTick();

  if (numberOfPeriods < 1 || minutesPerPeriod < 1)
    {
      /* If we are not using periods of N minutes, we must just be keeping
       * a running total recorded second by second.
       */
      my->numberOfPeriods = 0;
      my->minutesPerPeriod = 0;
      my->second = 0;
      my->minute = 0;
      my->period = 0;
      if (my->supportDurations == YES)
        {
	  DInfo	*ptr;

	  ptr = (DInfo*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(DInfo));
	  memset(ptr, '\0', sizeof(DInfo));
	  my->seconds = ptr;
	  my->minutes = 0;
	  my->periods = 0;
	  dseconds[0].tick = my->last;
	  dseconds[0].min = MAXDURATION;
	}
      else
        {
	  CInfo	*ptr;

	  ptr = (CInfo*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(CInfo));
	  memset(ptr, '\0', sizeof(CInfo));
	  my->seconds = ptr;
	  my->minutes = 0;
	  my->periods = 0;
	  cseconds[0].tick = my->last;
	}
    }
  else
    {
      NSCalendarDate	*c;	
      unsigned		i;

      c = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:
	GSTickerTimeLast()];

      my->numberOfPeriods = numberOfPeriods;
      my->minutesPerPeriod = minutesPerPeriod;
      my->second = [c secondOfMinute];
      i = [c hourOfDay] * 60 + [c minuteOfHour];
      my->minute = i % minutesPerPeriod;
      my->period = (i / minutesPerPeriod) % numberOfPeriods;
      RELEASE(c);

      i = 60 + minutesPerPeriod + numberOfPeriods;
      if (my->supportDurations == YES)
	{
	  DInfo	*ptr;

	  ptr = (DInfo*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(DInfo) * i);
	  memset(ptr, '\0', sizeof(DInfo) * i);
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
	  CInfo	*ptr;

	  ptr = (CInfo*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(CInfo) * i);
	  memset(ptr, '\0', sizeof(CInfo) * i);
	  my->seconds = ptr;
	  my->minutes = ptr + 60;
	  my->periods = ptr + 60 + minutesPerPeriod;
	  cseconds[my->second].tick = my->last;
	  cminutes[my->minute].tick = my->last;
	  cperiods[my->period].tick = my->last;
	}
    }
  return self;
}

- (NSString*) name
{
  return my->name;
}

- (void) setName: (NSString*)name
{
  ASSIGN(my->name, name);
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

