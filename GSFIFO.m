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
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSZone.h>

@implementation	GSFIFO

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

- (void*) _cooperatingGetShouldBlock: (BOOL)block
{
  NSTimeInterval	ti;
  void			*item;
  BOOL			wasFull = NO;
  BOOL			isEmpty = NO;

  if (NO == [getLock tryLockWhenCondition: 1])
    {
      _getTryFailure++;
      if (NO == block)
	{
	  return 0;
	}

      START
      if (0 == timeout)
	{
	  [getLock lockWhenCondition: 1];
	}
      else
	{
	  NSDate	*d;

	  d = [[NSDateClass alloc]
	    initWithTimeIntervalSinceNow: 1000.0 * timeout];
	  if (NO == [getLock lockWhenCondition: 1 beforeDate: d])
	    {
	      [d release];
	      ENDGET
	      [NSException raise: NSGenericException
			  format: @"Timeout waiting for new data in FIFO"];
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
  item = _items[_tail % _capacity];
  _tail++;
  if (_head - _tail == 0)
    {
      isEmpty = YES;
    }
  if (YES == wasFull)
    {
      [putLock lock];
      [putLock unlockWithCondition: 1];
    }
  [getLock unlockWithCondition: isEmpty ? 0 : 1];
  return item;
}

- (BOOL) _cooperatingPut: (void*)item shouldBlock: (BOOL)block
{
  NSTimeInterval	ti;
  BOOL			wasEmpty = NO;
  BOOL			isFull = NO;

  if (NO == [putLock tryLockWhenCondition: 1])
    {
      _putTryFailure++;
      if (NO == block)
	{
	  return NO;
	}

      START
      if (0 == timeout)
	{
	  [putLock lockWhenCondition: 1];
	}
      else
	{
	  NSDate	*d;

	  d = [[NSDateClass alloc]
	    initWithTimeIntervalSinceNow: 1000.0 * timeout];
	  if (NO == [putLock lockWhenCondition: 1 beforeDate: d])
	    {
	      [d release];
	      ENDPUT
	      [NSException raise: NSGenericException
			  format: @"Timeout waiting for space in FIFO"];
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
  _items[_head % _capacity] = item;
  _head++;
  if (_head - _tail == _capacity)
    {
      isFull = YES;
    }
  if (YES == wasEmpty)
    {
      [getLock lock];
      [getLock unlockWithCondition: 1];
    }
  [putLock unlockWithCondition: isFull ? 0 : 1];
  return YES;
}

- (void) dealloc
{
  [name release];
  [getLock release];
  [putLock release];
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

- (void*) get
{
  void			*item;
  NSTimeInterval	ti;
  NSTimeInterval	sum;
  uint32_t		old;
  uint32_t		fib;
  
  if (nil == getLock)
    {
      if (_head > _tail)
	{
	  item = _items[_tail % _capacity];
	  _tail++;
	  _getTrySuccess++;
	  return item;
	}
      _getTryFailure++;
      emptyCount++;
    }
  else if (nil != putLock)
    {
      return [self _cooperatingGetShouldBlock: YES];
    }
  else
    {
      [getLock lock];
      if (_head > _tail)
	{
	  item = _items[_tail % _capacity];
	  _tail++;
	  _getTrySuccess++;
	  [getLock unlock];
	  return item;
	}
      _getTryFailure++;
      emptyCount++;
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
	  [getLock unlock];
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
  item = _items[_tail % _capacity];
  _tail++;
  ENDGET
  [getLock unlock];
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
  if (c < 1)
    {
      [self release];
      return nil;
    }
  _capacity = c;
  granularity = g;
  timeout = t;
  _items = (void*)NSAllocateCollectable(c * sizeof(void*), NSScannedOption);
  if (YES == mp) putLock = [[NSConditionLock alloc] initWithCondition: 1];
  if (YES == mc) getLock = [[NSConditionLock alloc] initWithCondition: 0];
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
  return self;
}

- (void) put: (void*)item
{
  NSTimeInterval	sum;
  NSTimeInterval	ti = 0.0;
  uint32_t		old;
  uint32_t		fib;

  if (nil == putLock)
    {
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  _putTrySuccess++;
	  return;
	}
      _putTryFailure++;
      fullCount++;
    }
  else if (nil != getLock)
    {
      [self _cooperatingPut: item shouldBlock: YES];
      return;
    }
  else
    {
      [putLock lock];
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  _putTrySuccess++;
	  [putLock unlock];
	  return;
	}
      _putTryFailure++;
      fullCount++;
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
	  [putLock unlock];
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
  _items[_head % _capacity] = item;
  _head++;
  ENDPUT
  [putLock unlock];
}

- (NSString*) statsGet
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 100];

  if (nil != getLock)
    {
      [getLock lock];
    }
  [s appendFormat: @"%@ (%@) empty:%llu failures:%llu successes:%llu\n",
    [super description], name,
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
          [s appendFormat: @"  up to %g: %llu\n",
	    waitBoundaries[i], getWaitCounts[i]];
	}
      [s appendFormat: @"  above %g: %llu\n",
	waitBoundaries[boundsCount-1], getWaitCounts[boundsCount]];
    }
  if (nil != getLock)
    {
      [getLock unlockWithCondition: [getLock condition]];
    }

  return s;
}

- (NSString*) statsPut
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 100];

  if (nil != putLock)
    {
      [putLock lock];
    }
  [s appendFormat: @"%@ (%@) empty:%llu failures:%llu successes:%llu",
    [super description], name,
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
          [s appendFormat: @"  up to %g: %llu\n",
	    waitBoundaries[i], putWaitCounts[i]];
	}
      [s appendFormat: @"  above %g: %llu\n",
	waitBoundaries[boundsCount-1], putWaitCounts[boundsCount]];
    }

  if (nil != putLock)
    {
      [putLock unlockWithCondition: [putLock condition]];
    }
  return s;
}

- (void*) tryGet
{
  void	*item;
  
  if (nil == getLock)
    {
      if (_head > _tail)
	{
	  item = _items[_tail % _capacity];
	  _tail++;
	  _getTrySuccess++;
	  return item;
	}
      _getTryFailure++;
      emptyCount++;
    }
  else if (nil != putLock)
    {
      return [self _cooperatingGetShouldBlock: NO];
    }
  else
    {
      [getLock lock];
      if (_head > _tail)
	{
	  item = _items[_tail % _capacity];
	  _tail++;
	  _getTrySuccess++;
	  [getLock unlock];
	  return item;
	}
      _getTryFailure++;
      emptyCount++;
      [getLock unlock];
    }
  return NULL;
}

- (BOOL) tryPut: (void*)item
{
  if (nil == putLock)
    {
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  _putTrySuccess++;
	  return YES;
	}
      _putTryFailure++;
      fullCount++;
    }
  else if (nil != getLock)
    {
      return [self _cooperatingPut: item shouldBlock: NO];
    }
  else
    {
      [putLock lock];
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  _putTrySuccess++;
	  [putLock unlock];
	  return YES;
	}
      _putTryFailure++;
      fullCount++;
      [putLock unlock];
    }
  return NO;
}

@end

