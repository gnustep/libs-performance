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
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSZone.h>

@implementation	GSFIFO

- (void*) _cooperatingGetShouldBlock: (BOOL)block
{
  void	*item;
  BOOL	wasFull = NO;
  BOOL	isEmpty = NO;

  if (NO == block)
    {
      if (NO == [getLock tryLockWhenCondition: 1])
	{
	  return 0;
	}
    }
  else if (0 == timeout)
    {
      [getLock lockWhenCondition: 1];
    }
  else
    {
      NSDate	*d;

      d = [[NSDate alloc] initWithTimeIntervalSinceNow: 1000.0 * timeout];
      if (NO == [getLock lockWhenCondition: 1 beforeDate: d])
	{
	  [d release];
	  [NSException raise: NSGenericException
		      format: @"Timeout waiting for new data in FIFO"];
	}
      [d release];
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
  BOOL	wasEmpty = NO;
  BOOL	isFull = NO;

  if (NO == block)
    {
      if (NO == [putLock tryLockWhenCondition: 1])
	{
	  return NO;
	}
    }
  else if (0 == timeout)
    {
      [putLock lockWhenCondition: 1];
    }
  else
    {
      NSDate	*d;

      d = [[NSDate alloc] initWithTimeIntervalSinceNow: 1000.0 * timeout];
      if (NO == [putLock lockWhenCondition: 1 beforeDate: d])
	{
	  [d release];
	  [NSException raise: NSGenericException
		      format: @"Timeout waiting for space in FIFO"];
	}
      [d release];
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
  NSTimeInterval	sum;
  uint32_t		old;
  uint32_t		fib;
  
  if (nil == getLock)
    {
      if (_head > _tail)
	{
	  item = _items[_tail % _capacity];
	  _tail++;
	  return item;
	}
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
	  [getLock unlock];
	  return item;
	}
      emptyCount++;
    }

  old = 0;
  fib = 1;
  sum = 0.0;
  while (_head <= _tail)
    {
      uint32_t		tmp;
      NSTimeInterval	dly;

      if (timeout > 0 && sum * 1000 > timeout)
	{
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
  [getLock unlock];
  return item;
}

- (id) initWithCapacity: (uint32_t)c
	    granularity: (uint16_t)g
		timeout: (uint16_t)t
	  multiProducer: (BOOL)mp
	  multiConsumer: (BOOL)mc
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
  _items = (void*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(void*) * c);
  if (YES == mp) putLock = [[NSConditionLock alloc] initWithCondition: 1];
  if (YES == mc) getLock = [[NSConditionLock alloc] initWithCondition: 0];
  name = [n copy];
  return self;
}

- (void) put: (void*)item
{
  NSTimeInterval	sum;
  uint32_t		old;
  uint32_t		fib;

  if (nil == putLock)
    {
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  return;
	}
      fullCount++;
    }
  else if (nil != getLock)
    {
      [self _cooperatingPut: item shouldBlock: YES];
    }
  else
    {
      [putLock lock];
      if (_head - _tail < _capacity)
	{
	  _items[_head % _capacity] = item;
	  _head++;
	  [putLock unlock];
	  return;
	}
      fullCount++;
    }

  old = 0;
  fib = 1;
  sum = 0.0;
  while (_head - _tail >= _capacity)
    {
      uint32_t		tmp;
      NSTimeInterval	dly;

      if (timeout > 0 && sum * 1000 > timeout)
	{
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
  [putLock unlock];
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
	  return item;
	}
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
	  [getLock unlock];
	  return item;
	}
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
	  return YES;
	}
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
	  [putLock unlock];
	  return YES;
	}
      fullCount++;
      [putLock unlock];
    }
  return NO;
}

@end

