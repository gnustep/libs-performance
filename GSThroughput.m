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
  NSTimeInterval	max;	// Longest duration
  NSTimeInterval	min;	// Shortest duration
  NSTimeInterval	sum;	// Total (sum of durations for event)
  unsigned		tick;
} Info;

typedef struct {
  Info		seconds[60];
  Info		minutes[60];
  Info		hours[24];
  unsigned	second;
  unsigned	minute;
  unsigned	hour;
  unsigned	last;		// last tick used
  NSString	*name;
} Item;
#define	my	((Item*)&self[1])

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
  my->seconds[my->second].cnt += count;
}

- (void) addDuration: (NSTimeInterval)length
{
  if (my->seconds[my->second].cnt++ == 0)
    {
      my->seconds[my->second].min = length;
      my->seconds[my->second].max = length;
      my->seconds[my->second].sum = length;
    }
  else
    {
      my->seconds[my->second].sum += length;
      if (length > my->seconds[my->second].max)
	{
	  my->seconds[my->second].max = length;
	}
      if (length < my->seconds[my->second].min)
	{
	  my->seconds[my->second].min = length;
	}
    }
}


- (void) dealloc
{
  [GSThroughputLock lock];
  RELEASE(my->name);
  NSHashRemove(GSThroughputInstances, (void*)self);
  NSDeallocateObject(self);
  [GSThroughputLock unlock];
}

- (NSString*) description
{
  NSString		*n = my->name;
  NSMutableString	*m;
  unsigned		i;

  if (n == nil)
    {
      n = [super description];
    }
  m = [n mutableCopy];
  if (my->second > 0)
    {
      [m appendString: @"\nCurrent minute:\n"];
      for (i = 0; i < my->second; i++)
	{
	  Info			*info = &my->seconds[i];
	  NSTimeInterval	ti = info->tick + baseTime;

	  [m appendFormat: @"%u, %g, %g, %g, %@\n",
	    info->cnt, info->max, info->min, info->sum,
	    [NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	}
    }

  if (my->minute > 0)
    {
      [m appendString: @"\nCurrent hour:\n"];
      for (i = 0; i < my->minute; i++)
	{
	  Info			*info = &my->minutes[i];
	  NSTimeInterval	ti = info->tick + baseTime;

	  [m appendFormat: @"%u, %g, %g, %g, %@\n",
	    info->cnt, info->max, info->min, info->sum,
	    [NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	}
    }

  if (my->hour > 0)
    {
      [m appendString: @"\nCurrent day:\n"];
      for (i = 0; i < my->hour; i++)
	{
	  Info			*info = &my->hours[i];
	  NSTimeInterval	ti = info->tick + baseTime;

	  [m appendFormat: @"%u, %g, %g, %g, %@\n",
	    info->cnt, info->max, info->min, info->sum,
	    [NSDate dateWithTimeIntervalSinceReferenceDate: ti]];
	}
    }

  return AUTORELEASE(m);
}

- (id) init
{
  NSCalendarDate	*c;	
  unsigned		i;

  for (i = 0; i < 24; i++)
    {
      my->hours[i].min = MAXDURATION;
    }
  for (i = 0; i < 60; i++)
    {
      my->seconds[i].min = MAXDURATION;
      my->minutes[i].min = MAXDURATION;
    }
  my->last = GSThroughputTimeTick() - 1;
  c = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate: lastTime];
  my->second = [c secondOfMinute];
  my->minute = [c minuteOfHour];
  my->hour = [c hourOfDay];
  RELEASE(c);
  my->seconds[my->second].tick = my->last;
  my->minutes[my->minute].tick = my->last;
  my->hours[my->hour].tick = my->last;
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

- (void) update
{
  unsigned	tick = GSThroughputTimeTick();

  while (my->last < tick)
    {
      Info	*info;
      unsigned	i;

      if (my->second++ == 59)
	{
	  info = &my->minutes[my->minute];
	  for (i = 0; i < 60; i++)
	    {
	      Info	*from = &my->seconds[i];

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
	  if (my->minute++ == 59)
	    {
	      info = &my->hours[my->hour];
	      for (i = 0; i < 60; i++)
		{
		  Info	*from = &my->minutes[i];

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
	      if (my->hour++ == 23)
		{
		}
	      info = &my->hours[my->hour];
	      info->cnt = 0;
	      info->max = 0.0;
	      info->min = MAXDURATION;
	      info->sum = 0.0;
	      info->tick = tick;
	    }
	  info = &my->minutes[my->minute];
	  info->cnt = 0;
	  info->max = 0.0;
	  info->min = MAXDURATION;
	  info->sum = 0.0;
	  info->tick = tick;
	}
      info = &my->seconds[my->second];
      info->cnt = 0;
      info->max = 0.0;
      info->min = MAXDURATION;
      info->sum = 0.0;
      info->tick = tick;

      my->last++;
    }
}
@end

