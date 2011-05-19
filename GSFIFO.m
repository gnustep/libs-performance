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

- (id) get
{
  id			obj;
  NSTimeInterval	sum;
  uint32_t		old;
  uint32_t		fib;
  
  if (nil == getLock)
    {
      if (_head > _tail)
	{
	  obj = _items[_tail % _capacity];
	  _tail++;
	  return obj;
	}
      emptyCount++;
    }
  else
    {
      [getLock lock];
      if (_head > _tail)
	{
	  obj = _items[_tail % _capacity];
	  _tail++;
	  [getLock unlock];
	  return obj;
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
		      format: @"Timout waiting for new data in FIFO"];
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
  obj = _items[_tail % _capacity];
  _tail++;
  [getLock unlock];
  return obj;
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
  _items = (id*)NSZoneMalloc(NSDefaultMallocZone(), sizeof(id) * c);
  if (YES == mp) putLock = [NSLock new];
  if (YES == mc) getLock = [NSLock new];
  name = [n copy];
  return self;
}

- (void) put: (id)item
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
		      format: @"Timout waiting for space in FIFO"];
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

- (id) tryGet
{
  id	obj;
  
  if (nil == getLock)
    {
      if (_head > _tail)
	{
	  obj = _items[_tail % _capacity];
	  _tail++;
	  return obj;
	}
      emptyCount++;
    }
  else
    {
      [getLock lock];
      if (_head > _tail)
	{
	  obj = _items[_tail % _capacity];
	  _tail++;
	  [getLock unlock];
	  return obj;
	}
      emptyCount++;
      [getLock unlock];
    }
  return nil;
}

- (BOOL) tryPut: (id)item
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

