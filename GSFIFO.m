/**
   Copyright (C) 2011 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:        April 2011

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
   */
#import "GSFIFO.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSZone.h>

@implementation	GSFIFO

static NSLock		*classLock = nil;
static NSMapTable	*allFIFOs = nil;
static NSArray		*defaultBoundaries = nil;
static Class		NSDateClass = 0;
static SEL		tiSel = 0;
static NSTimeInterval	(*tiImp)(Class, SEL) = 0;

#define	NOW	((*tiImp)(NSDateClass, tiSel))

#define	START	if (boundsCount > 0) ti = NOW;

#define	ENDGET	if (boundsCount > 0 && ti > 0.0) {\
ti = NOW - ti; getWaitTotal += ti; \
stats(ti, boundsCount, waitBoundaries, getWaitCounts); }

#define	ENDPUT	if (boundsCount > 0 && ti > 0.0) {\
ti = NOW - ti; putWaitTotal += ti; \
stats(ti, boundsCount, waitBoundaries, putWaitCounts); }

static void
stats(NSTimeInterval ti, uint32_t max, NSTimeInterval *bounds, uint64_t *bands)
{
  if (ti > bounds[max - 1])
    {
      bands[max]++;
    }
  else
    {
      uint32_t	min = 0;
      uint32_t	pos = max / 2;

      while (max > min)
	{
	  if (ti <= bounds[pos])
	    {
	      max = pos;
	    }
	  else
	    {
	      min = pos + 1;
	    }
	  pos = (max + min)/2;
	}
      bands[pos]++;
    }
}

+ (void) initialize
{
  if (nil == defaultBoundaries)
    {
      classLock = [NSLock new];
      allFIFOs = NSCreateMapTable(NSObjectMapKeyCallBacks,
	NSNonRetainedObjectMapValueCallBacks, 0);
      defaultBoundaries = [[NSArray alloc] initWithObjects:
	[NSNumber numberWithDouble: 0.1],
	[NSNumber numberWithDouble: 0.2],
	[NSNumber numberWithDouble: 0.5],
	[NSNumber numberWithDouble: 1.0],
	[NSNumber numberWithDouble: 2.0],
	[NSNumber numberWithDouble: 5.0],
	[NSNumber numberWithDouble: 10.0],
	[NSNumber numberWithDouble: 20.0],
	[NSNumber numberWithDouble: 50.0],
	nil];
      NSDateClass = [NSDate class];
      tiSel = @selector(timeIntervalSinceReferenceDate);
      tiImp
	= (NSTimeInterval (*)(Class,SEL))[NSDateClass methodForSelector: tiSel];
    }
}

+ (NSString*) stats
{
  NSMutableString	*m = [NSMutableString stringWithCapacity: 1024];
  NSString		*k;
  GSFIFO		*f;
  NSMapEnumerator	e;

  [classLock lock];
  e = NSEnumerateMapTable(allFIFOs);
  while (NSNextMapEnumeratorPair(&e, (void**)&k, (void**)&f) != 0)
    {
      [m appendString: [f stats]];
    }
  NSEndMapTableEnumeration(&e);
  [classLock unlock];
  return m;
}

- (unsigned) _cooperatingGet: (void**)buf
		       count: (unsigned)count
		 shouldBlock: (BOOL)block
{
  NSTimeInterval	ti;
  unsigned		index;
  BOOL			wasFull;

  [condition lock];
  if (_head - _tail == 0)
    {
      emptyCount++;
      _getTryFailure++;
      if (NO == block)
	{
	  [condition unlock];
	  return 0;
	}

      START
      if (0 == timeout)
	{
	  while (_head - _tail == 0)
	    {
	      [condition wait];
	    }
	}
      else
	{
	  NSDate	*d;

	  d = [[NSDateClass alloc]
	    initWithTimeIntervalSinceNow: 1000.0 * timeout];
	  while (_head - _tail == 0)
	    {
	      if (NO == [condition waitUntilDate: d])
		{
		  [d release];
		  ENDGET
		  [condition broadcast];
		  [condition unlock];
		  [NSException raise: NSGenericException
			      format: @"Timeout waiting for new data in FIFO"];
		}
	    }
	  [d release];
	  ENDGET
	}
    }
  else
    {
      _getTrySuccess++;
    }

  if (_head - _tail == _capacity)
    {
      wasFull = YES;
    }
  else
    {
      wasFull = NO;
    }
  for (index = 0; index < count && (_head - _tail) != 0; index++)
    {
      buf[index] = _items[_tail % _capacity];
      _tail++;
    }
  if (YES == wasFull)
    {
      [condition broadcast];
    }
  [condition unlock];

  return index;
}

- (unsigned) _cooperatingPut: (void**)buf
		       count: (unsigned)count
		 shouldBlock: (BOOL)block
{
  NSTimeInterval	ti;
  unsigned		index;
  BOOL			wasEmpty;

  [condition lock];
  if (_head - _tail == _capacity)
    {
      _putTryFailure++;
      fullCount++;
      if (NO == block)
	{
	  [condition unlock];
	  return 0;
	}

      START
      if (0 == timeout)
	{
	  while (_head - _tail == _capacity)
	    {
	      [condition wait];
	    }
	}
      else
	{
	  NSDate	*d;

	  d = [[NSDateClass alloc]
	    initWithTimeIntervalSinceNow: 1000.0 * timeout];
	  while (_head - _tail == _capacity)
	    {
	      if (NO == [condition waitUntilDate: d])
		{
		  [d release];
		  ENDPUT
		  [condition broadcast];
		  [condition unlock];
		  [NSException raise: NSGenericException
			      format: @"Timeout waiting for space in FIFO"];
		}
	    }
	  [d release];
	}
      ENDPUT
    }
  else
    {
      _putTrySuccess++;
    }

  if (_head - _tail == 0)
    {
      wasEmpty = YES;
    }
  else
    {
      wasEmpty = NO;
    }
  for (index = 0; index < count && (_head - _tail < _capacity); index++)
    {
      _items[_head % _capacity] = buf[index];
      _head++;
    }
  if (YES == wasEmpty)
    {
      [condition broadcast];
    }
  [condition unlock];
  return index;
}

- (void) dealloc
{
  [classLock lock];
  if (NSMapGet(allFIFOs, name) == self)
    {
      NSMapRemove(allFIFOs, name);
    }
  [classLock unlock];

  [name release];
  [condition release];
  if (0 != _items)
    {
      NSZoneFree(NSDefaultMallocZone(), _items);
    }
  if (0 != waitBoundaries)
    {
      NSZoneFree(NSDefaultMallocZone(), waitBoundaries);
    }
  if (0 != getWaitCounts)
    {
      NSZoneFree(NSDefaultMallocZone(), getWaitCounts);
    }
  if (0 != putWaitCounts)
    {
      NSZoneFree(NSDefaultMallocZone(), putWaitCounts);
    }
  [super dealloc];
}

- (NSUInteger) count
{
  return (NSUInteger)(_head - _tail);
}

- (NSString*) description
{
  return [NSString stringWithFormat:
    @"%@ (%@) get:%llu put:%llu empty:%llu full:%llu",
    [super description], name,
    (unsigned long long)_tail,
    (unsigned long long)_head,
    (unsigned long long)emptyCount,
    (unsigned long long)fullCount];
}

- (unsigned) get: (void**)buf count: (unsigned)count shouldBlock: (BOOL)block
{
  unsigned		index;
  NSTimeInterval	ti;
  NSTimeInterval	sum;
  uint32_t		old;
  uint32_t		fib;
  
  if (0 == count) return 0;

  if (nil != condition)
    {
      return [self _cooperatingGet: buf count: count shouldBlock: block];
    }

  if (nil == getThread)
    {
      getThread = [NSThread currentThread];
    }
  if (_head > _tail)
    {
      for (index = 0; index < count && _head > _tail; index++)
	{
	  buf[index] = _items[_tail % _capacity];
	  _tail++;
	  _getTrySuccess++;
	}
      return index;
    }
  _getTryFailure++;
  emptyCount++;
  if (NO == block)
    {
      return 0;
    }

  START
  old = 0;
  fib = 1;
  sum = 0.0;
  while (_head <= _tail)
    {
      uint32_t		tmp;
      NSTimeInterval	dly;

      if (timeout > 0 && sum * 1000 > timeout)
	{
	  ENDGET
	  [NSException raise: NSGenericException
		      format: @"Timeout waiting for new data in FIFO"];
	}
      tmp = fib + old;
      old = fib;
      fib = tmp;
      if (granularity > 0 && fib > granularity)
	{
	  fib = granularity;
	}
      dly = ((NSTimeInterval)fib) / 1000.0;
      [NSThread sleepForTimeInterval: dly];
      sum += dly;
    }
  ENDGET
  for (index = 0; index < count && _head > _tail; index++)
    {
      buf[index] = _items[_tail % _capacity];
      _tail++;
    }
  return index;
}

- (void*) get
{
  void	*item = 0;

  while (0 == [self get: &item count: 1 shouldBlock: YES])
    ;
  return item;
}

- (id) initWithCapacity: (uint32_t)c
	    granularity: (uint16_t)g
		timeout: (uint16_t)t
	  multiProducer: (BOOL)mp
	  multiConsumer: (BOOL)mc
	     boundaries: (NSArray*)a
		   name: (NSString*)n
{
  if (c < 1 || c > 1000000)
    {
      [self release];
      return nil;
    }
  _capacity = c;
  granularity = g;
  timeout = t;
  _items = (void*)NSAllocateCollectable(c * sizeof(void*), NSScannedOption);
  if (YES == mp || YES == mc)
    {
      condition = [NSCondition new];
    }
  name = [n copy];
  if (nil == a)
    {
      a = defaultBoundaries;
    }
  if ((c = [a count]) > 0)
    {
      NSTimeInterval	l;
      NSNumber		*n;

      waitBoundaries
	= (NSTimeInterval*)NSAllocateCollectable(c * sizeof(NSTimeInterval), 0);
      boundsCount = c++;
      getWaitCounts
	= (uint64_t*)NSAllocateCollectable(c * sizeof(uint64_t), 0);
      putWaitCounts
	= (uint64_t*)NSAllocateCollectable(c * sizeof(uint64_t), 0);

      n = [a lastObject];
      if (NO == [n isKindOfClass: [NSNumber class]]
	|| (l = [n doubleValue]) <= 0.0)
	{
	  [self release];
	  [NSException raise: NSInvalidArgumentException
		      format: @"Bad boundaries"];
	}
      c = boundsCount;
      waitBoundaries[--c] = l;
      while (c-- > 0)
	{
	  NSTimeInterval	t;

	  n = [a objectAtIndex: c];
	  if (NO == [n isKindOfClass: [NSNumber class]]
	    || (t = [n doubleValue]) <= 0.0 || t >= l)
	    {
	      [self release];
	      [NSException raise: NSInvalidArgumentException
			  format: @"Bad boundaries"];
	    }
	  waitBoundaries[c] = t;
	  l = t;
	}
    }
  [classLock lock];
  if (nil != NSMapGet(allFIFOs, n))
    {
      [classLock unlock];
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"GSFIFO ... name (%@) already in use", n];
    }
  NSMapInsert(allFIFOs, name, self);
  [classLock unlock];
  return self;
}

- (id) initWithCapacity: (uint32_t)c
		   name: (NSString*)n
{
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSString		*key;
  uint16_t		g;
  uint16_t		t;
  BOOL			mc;
  BOOL			mp;
  NSArray		*b;

  key = [NSString stringWithFormat: @"GSFIFOCapacity%@", n];
  if ([defs integerForKey: key] > 0)
    {
      c = [defs integerForKey: key];
    }
  key = [NSString stringWithFormat: @"GSFIFOGranularity%@", n];
  g = [defs integerForKey: key];
  key = [NSString stringWithFormat: @"GSFIFOTimeout%@", n];
  t = [defs integerForKey: key];
  key = [NSString stringWithFormat: @"GSFIFOSingleConsumer%@", n];
  mc = (YES == [defs boolForKey: key]) ? NO : YES;
  key = [NSString stringWithFormat: @"GSFIFOSingleProducer%@", n];
  mp = (YES == [defs boolForKey: key]) ? NO : YES;
  key = [NSString stringWithFormat: @"GSFIFOBoundaries%@", n];
  b = [defs arrayForKey: key];

  return [self initWithCapacity: c
		    granularity: g
			timeout: t
		  multiProducer: mp
		  multiConsumer: mc
		     boundaries: b
			   name: n];
}

- (id) initWithName: (NSString*)n
{
  return [self initWithCapacity: 10000 name: n];
}

- (unsigned) put: (void**)buf count: (unsigned)count shouldBlock: (BOOL)block
{
  NSTimeInterval	sum;
  unsigned		index;
  NSTimeInterval	ti = 0.0;
  uint32_t		old;
  uint32_t		fib;

  if (0 == count)
    {
      return 0;
    }

  if (nil != condition)
    {
      return [self _cooperatingPut: buf count: count shouldBlock: block];
    }

  if (nil == putThread)
    {
      putThread = [NSThread currentThread];
    }
  if (_head - _tail < _capacity)
    {
      for (index = 0; index < count && _head - _tail < _capacity; index++)
	{
	  _items[_head % _capacity] = buf[index];
	  _head++;
	}
      _putTrySuccess++;
      return index;
    }
  _putTryFailure++;
  fullCount++;
  if (NO == block)
    {
      return 0;
    }

  START
  old = 0;
  fib = 1;
  sum = 0.0;
  while (_head - _tail >= _capacity)
    {
      uint32_t		tmp;
      NSTimeInterval	dly;

      if (timeout > 0 && sum * 1000 > timeout)
	{
	  ENDPUT
	  [NSException raise: NSGenericException
		      format: @"Timeout waiting for space in FIFO"];
	}
      tmp = fib + old;
      old = fib;
      fib = tmp;
      if (granularity > 0 && fib > granularity)
	{
	  fib = granularity;
	}
      dly = ((NSTimeInterval)fib) / 1000.0;
      [NSThread sleepForTimeInterval: dly];
      sum += dly;
    }
  ENDPUT
  for (index = 0; index < count && _head - _tail < _capacity; index++)
    {
      _items[_head % _capacity] = buf[index];
      _head++;
    }
  return index;
}

- (void) put: (void*)item
{
  while (0 == [self put: &item count: 1 shouldBlock: YES])
    ;
}

- (void) _getStats: (NSMutableString*)s
{
  [s appendFormat: @"  empty:%llu failures:%llu successes:%llu\n",
    (unsigned long long)emptyCount,
    (unsigned long long)_getTryFailure,
    (unsigned long long)_getTrySuccess];
  if (boundsCount > 0)
    {
      unsigned	i;

      [s appendFormat: @"  blocked total:%g average:%g perfail:%g\n",
	getWaitTotal,
        (_getTryFailure+_getTrySuccess > 0)
	? getWaitTotal / (_getTryFailure+_getTrySuccess) : 0.0,
        (_getTryFailure > 0)
	? getWaitTotal / _getTryFailure : 0.0];
      for (i = 0; i < boundsCount; i++)
	{
          [s appendFormat: @"    up to %g: %llu\n",
	    waitBoundaries[i], getWaitCounts[i]];
	}
      [s appendFormat: @"    above %g: %llu\n",
	waitBoundaries[boundsCount-1], getWaitCounts[boundsCount]];
    }
}

- (void) _putStats: (NSMutableString*)s
{
  [s appendFormat: @"  full:%llu failures:%llu successes:%llu\n",
    (unsigned long long)fullCount,
    (unsigned long long)_putTryFailure,
    (unsigned long long)_putTrySuccess];
  if (boundsCount > 0)
    {
      unsigned	i;

      [s appendFormat: @"  blocked total:%g average:%g perfail:%g\n",
	putWaitTotal,
        (_putTryFailure+_putTrySuccess > 0)
	? putWaitTotal / (_putTryFailure+_putTrySuccess) : 0.0,
        (_putTryFailure > 0)
	? putWaitTotal / _putTryFailure : 0.0];
      for (i = 0; i < boundsCount; i++)
	{
          [s appendFormat: @"    up to %g: %llu\n",
	    waitBoundaries[i], putWaitCounts[i]];
	}
      [s appendFormat: @"    above %g: %llu\n",
	waitBoundaries[boundsCount-1], putWaitCounts[boundsCount]];
    }
}

- (NSString*) stats
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 100];

  [s appendFormat: @"%@ (%@)\n", [super description], name];
  if (nil != condition || [NSThread currentThread] == getThread)
    {
      [condition lock];
      [self _getStats: s];
      [condition unlock];
    }
  if (nil != condition || [NSThread currentThread] == putThread)
    {
      [condition lock];
      [self _putStats: s];
      [condition unlock];
    }
  return s;
}

- (NSString*) statsGet
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 100];

  if (nil == condition)
    {
      if ([NSThread currentThread] != getThread)
	{
	  if (nil == getThread)
	    {
	      getThread = [NSThread currentThread];
	    }
	  else
	    {
	      [NSException raise: NSInternalInconsistencyException
			  format: @"[%@-%@] called from wrong thread for %@",
		NSStringFromClass([self class]), NSStringFromSelector(_cmd),
		name];
	    }
	}
    }

  [condition lock];
  [s appendFormat: @"%@ (%@)\n", [super description], name];
  [self _getStats: s];
  [condition unlock];

  return s;
}

- (NSString*) statsPut
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 100];

  if (nil == condition)
    {
      if ([NSThread currentThread] != putThread)
	{
	  if (nil == putThread)
	    {
	      putThread = [NSThread currentThread];
	    }
	  else
	    {
	      [NSException raise: NSInternalInconsistencyException
			  format: @"[%@-%@] called from wrong thread for %@",
		NSStringFromClass([self class]), NSStringFromSelector(_cmd),
		name];
	    }
	}
    }

  [condition lock];
  [s appendFormat: @"%@ (%@)\n", [super description], name];
  [self _putStats: s];
  [condition unlock];

  return s;
}

- (void*) tryGet
{
  void	*item = nil;
  
  [self get: &item count: 1 shouldBlock: NO];
  return item;
}

- (BOOL) tryPut: (void*)item
{
  if (1 == [self put: &item count: 1 shouldBlock: NO])
    {
      return YES;
    }
  return NO;
}

@end

