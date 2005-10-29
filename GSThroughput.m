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

#include	<Foundation/NSArray.h>
#include	<Foundation/NSString.h>
#include	<Foundation/NSData.h>
#include	<Foundation/NSDate.h>
#include	<Foundation/NSCalendarDate.h>
#include	<Foundation/NSException.h>
#include	<Foundation/NSNotification.h>
#include	<Foundation/NSHashTable.h>
#include	<Foundation/NSMapTable.h>
#include	<Foundation/NSLock.h>
#include	<Foundation/NSAutoreleasePool.h>
#include	<Foundation/NSValue.h>
#include	<Foundation/NSDebug.h>
#include	<Foundation/NSSet.h>
#include	<Foundation/NSTimer.h>

#include	"GSThroughput.h"

#define	MAXDURATION	24.0*60.0*60.0

static Class		NSDateClass = 0;
static SEL		tiSel = 0;
static NSTimeInterval	(*tiImp)(Class,SEL) = 0;

static NSTimer		*theTimer = nil;
static NSTimeInterval	baseTime = 0;
static NSTimeInterval	lastTime = 0;

inline unsigned	GSThroughputTimeTick()
{
  return (lastTime - baseTime) + 1;
}


@implementation	GSThroughput

static NSHashTable	*GSThroughputInstances = 0;
static NSLock		*GSThroughputLock = nil;

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
  BOOL			supportDurations;
  unsigned		numberOfPeriods;
  unsigned		minutesPerPeriod;
  unsigned		second;
  unsigned		minute;
  unsigned		period;
  unsigned		last;		// last tick used
  NSTimeInterval	started;	// When duration logging started.
  NSString		*name;
} Item;
#define	my	((Item*)&self[1])

#define	cseconds	((CInfo*)my->seconds)
#define	cminutes	((CInfo*)my->minutes)
#define	cperiods	((CInfo*)my->periods)
#define	dseconds	((DInfo*)my->seconds)
#define	dminutes	((DInfo*)my->minutes)
#define	dperiods	((DInfo*)my->periods)

+ (NSArray*) allInstances
{
  NSArray	*a;

  [GSThroughputLock lock];
  a = NSAllHashTableObjects(GSThroughputInstances);
  [GSThroughputLock unlock];
  return a;
}

+ (id) alloc
{
  return [self allocWithZone: NSDefaultMallocZone()];
}

+ (id) allocWithZone: (NSZone*)z
{
  GSThroughput	*c;

  c = (GSThroughput*)NSAllocateObject(self, sizeof(Item), z);
  [GSThroughputLock lock];
  NSHashInsert(GSThroughputInstances, (void*)c);
  [GSThroughputLock unlock];
  return c;
}

+ (NSString*) description
{
  NSMutableString	*ms;
  NSHashEnumerator	e;
  GSThroughput		*c;

  ms = [NSMutableString stringWithString: [super description]];
  [GSThroughputLock lock];
  e = NSEnumerateHashTable(GSThroughputInstances);
  while ((c = (GSThroughput*)NSNextHashEnumeratorItem(&e)) != nil)
    {
      [ms appendFormat: @"\n%@", [c description]];
    }
  NSEndHashTableEnumeration(&e);
  [GSThroughputLock unlock];
  return ms;
}

+ (void) initialize
{
  if (GSThroughputInstances == 0)
    {
      NSDateClass = [NSDate class];
      tiSel = @selector(timeIntervalSinceReferenceDate);
      tiImp
	= (NSTimeInterval (*)(Class,SEL))[NSDateClass methodForSelector: tiSel];
      baseTime = lastTime = (*tiImp)(NSDateClass, tiSel);
      GSThroughputLock = [NSLock new];
      GSThroughputInstances
	= NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
      [self setTick: 1.0];
    }
}

+ (void) setTick: (NSTimeInterval)interval
{
  [GSThroughputLock lock];
  if (theTimer != nil)
    {
      [theTimer invalidate];
      theTimer = nil;
    }
  if (interval > 0.0)
    {
      theTimer = [NSTimer scheduledTimerWithTimeInterval: interval
						  target: self
						selector: @selector(tick)
						userInfo: 0
						 repeats: YES];
    }
  [GSThroughputLock unlock];
}

+ (void) tick
{
  NSTimeInterval	now;
  NSHashEnumerator	e;
  GSThroughput		*i;

  [GSThroughputLock lock];
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
  e = NSEnumerateHashTable(GSThroughputInstances);
  while ((i = (GSThroughput*)NSNextHashEnumeratorItem(&e)) != nil)
    {
      [i update];
    }
  NSEndHashTableEnumeration(&e);

  [GSThroughputLock unlock];
}

- (void) add: (unsigned)count
{
  NSAssert(my->supportDurations == NO, @"configured for durations");
  cseconds[my->second].cnt += count;
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

- (void) dealloc
{
  [GSThroughputLock lock];
  if (my->seconds != 0)
    {
      NSZoneFree(NSDefaultMallocZone(), my->seconds);
    }
  RELEASE(my->name);
  NSHashRemove(GSThroughputInstances, (void*)self);
  NSDeallocateObject(self);
  [GSThroughputLock unlock];
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

  if (my->supportDurations == YES)
    {
      if (my->second > 0)
	{
	  [m appendString: @"\nCurrent minute:\n"];
	  for (i = 0; i < my->second; i++)
	    {
	      DInfo		*info = &dseconds[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %g, %g, %g, %@\n",
		info->cnt, info->max, info->min, info->sum,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}

      if (my->minute > 0)
	{
	  [m appendString: @"\nCurrent period:\n"];
	  for (i = 0; i < my->minute; i++)
	    {
	      DInfo		*info = &dminutes[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %g, %g, %g, %@\n",
		info->cnt, info->max, info->min, info->sum,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}

      if (my->period > 0)
	{
	  [m appendString: @"\nPrevious periods:\n"];
	  for (i = 0; i < my->period; i++)
	    {
	      DInfo		*info = &dperiods[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %g, %g, %g, %@\n",
		info->cnt, info->max, info->min, info->sum,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}
    }
  else
    {
      if (my->second > 0)
	{
	  [m appendString: @"\nCurrent minute:\n"];
	  for (i = 0; i < my->second; i++)
	    {
	      CInfo		*info = &cseconds[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %@\n", info->cnt,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}

      if (my->minute > 0)
	{
	  [m appendString: @"\nCurrent period:\n"];
	  for (i = 0; i < my->minute; i++)
	    {
	      CInfo		*info = &cminutes[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %@\n", info->cnt,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}

      if (my->period > 0)
	{
	  [m appendString: @"\nPrevious periods:\n"];
	  for (i = 0; i < my->period; i++)
	    {
	      CInfo		*info = &cperiods[i];
	      NSTimeInterval	ti = info->tick + baseTime;

	      [m appendFormat: @"%u, %@\n", info->cnt,
		[NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	    }
	}
    }

  DESTROY(pool);
  return AUTORELEASE(m);
}

- (void) endDuration
{
  NSAssert(my->started > 0.0, NSInternalInconsistencyException);
  [self addDuration: (*tiImp)(NSDateClass, tiSel) - my->started];
  my->started = 0.0;
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
  NSCalendarDate	*c;	
  unsigned		i;

  if (numberOfPeriods < 1 || minutesPerPeriod < 1)
    {
      DESTROY(self);
      return nil;
    }
  my->supportDurations = aFlag;
  my->numberOfPeriods = numberOfPeriods;
  my->minutesPerPeriod = minutesPerPeriod;
  my->last = GSThroughputTimeTick() - 1;
  c = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate: lastTime];
  my->second = [c secondOfMinute];
  i = [c hourOfDay] * 60 + [c minuteOfHour];
  my->minute = i % minutesPerPeriod;
  my->period = i / minutesPerPeriod;
  RELEASE(c);

  i = 60 + minutesPerPeriod + numberOfPeriods;
  if (my->supportDurations == YES)
    {
      DInfo	*ptr;

      ptr = (DInfo*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(DInfo) * i);
      memset(ptr, '\0', sizeof(DInfo) * i);
      my->seconds = ptr;
      my->minutes = &ptr[60];
      my->periods = &ptr[60 + minutesPerPeriod];
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
      my->minutes = &ptr[60];
      my->periods = &ptr[60 + minutesPerPeriod];
      dseconds[my->second].tick = my->last;
      dminutes[my->minute].tick = my->last;
      dperiods[my->period].tick = my->last;
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

- (void) startDuration
{
  NSAssert(my->supportDurations == YES && my->started == 0.0,
    NSInternalInconsistencyException);
  my->started = (*tiImp)(NSDateClass, tiSel);
}

- (void) update
{
  unsigned	tick = GSThroughputTimeTick();
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
	      if (my->minute++ == my->minutesPerPeriod)
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
		  if (my->period++ == my->numberOfPeriods)
		    {
		      my->period = 0;
		    }
		  info = &dperiods[my->period];
		  info->cnt = 0;
		  info->max = 0.0;
		  info->min = MAXDURATION;
		  info->sum = 0.0;
		  info->tick = tick;
		  my->minute = 0;
		}
	      info = &dminutes[my->minute];
	      info->cnt = 0;
	      info->max = 0.0;
	      info->min = MAXDURATION;
	      info->sum = 0.0;
	      info->tick = tick;
	      my->second = 0;
	    }
	  info = &dseconds[my->second];
	  info->cnt = 0;
	  info->max = 0.0;
	  info->min = MAXDURATION;
	  info->sum = 0.0;
	  info->tick = tick;

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
	      if (my->minute++ == my->minutesPerPeriod)
		{
		  info = &cperiods[my->period];
		  for (i = 0; i < my->minutesPerPeriod; i++)
		    {
		      info->cnt += cminutes[i].cnt;
		    }
		  if (my->period++ == my->numberOfPeriods)
		    {
		      my->period = 0;
		    }
		  info = &cperiods[my->period];
		  info->cnt = 0;
		  info->tick = tick;
		  my->minute = 0;
		}
	      info = &cminutes[my->minute];
	      info->cnt = 0;
	      info->tick = tick;
	      my->second = 0;
	    }
	  info = &cseconds[my->second];
	  info->cnt = 0;
	  info->tick = tick;

	  my->last++;
	}
    }
}
@end

