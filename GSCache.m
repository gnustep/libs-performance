/* -*-objc-*- */

/** Implementation of GSCache for GNUStep
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
#import	<Foundation/NSAutoreleasePool.h>
#import	<Foundation/NSData.h>
#import	<Foundation/NSDate.h>
#import	<Foundation/NSDebug.h>
#import	<Foundation/NSDictionary.h>
#import	<Foundation/NSEnumerator.h>
#import	<Foundation/NSException.h>
#import	<Foundation/NSHashTable.h>
#import	<Foundation/NSLock.h>
#import	<Foundation/NSMapTable.h>
#import	<Foundation/NSNotification.h>
#import	<Foundation/NSSet.h>
#import	<Foundation/NSString.h>
#import	<Foundation/NSTimer.h>
#import	<Foundation/NSValue.h>

#import	<GNUstepBase/GNUstep.h>

#import	"GSCache.h"
#import	"GSTicker.h"

#if NeXT_RUNTIME
#include <objc/objc-class.h>
#endif

@interface	GSCacheItem : NSObject
{
@public
  GSCacheItem	*next;
  GSCacheItem	*prev;
  unsigned	when;
  unsigned	size;
  NSString	*key;
  id		object;
}
+ (GSCacheItem*) newWithObject: (id)anObject forKey: (NSString*)aKey;
@end

@implementation	GSCacheItem
+ (GSCacheItem*) newWithObject: (id)anObject forKey: (NSString*)aKey
{
  GSCacheItem	*i;

  i = (GSCacheItem*)NSAllocateObject(self, 0, NSDefaultMallocZone());
  i->object = RETAIN(anObject);
  i->key = [aKey copy];
  return i;
}
- (void) dealloc
{
  RELEASE(key);
  RELEASE(object);
  [super dealloc];
}
@end


@implementation	GSCache

static NSHashTable	*GSCacheInstances = 0;
static NSLock		*GSCacheLock = nil;

typedef struct {
  id		delegate;
  unsigned	currentObjects;
  unsigned	currentSize;
  unsigned	lifetime;
  unsigned	maxObjects;
  unsigned	maxSize;
  unsigned	hits;
  unsigned	misses;
  NSMapTable	*contents;
  GSCacheItem	*first;
  NSString	*name;
  NSMutableSet	*exclude;
} Item;
#define	my	((Item*)&self[1])

/*
 * Add item to linked list starting at *first
 */
static void appendItem(GSCacheItem *item, GSCacheItem **first)
{
  if (*first == nil)
    {
      item->next = item->prev = item;
      *first = item;
    }
  else
    {
      (*first)->prev->next = item;
      item->prev = (*first)->prev;
      (*first)->prev = item;
      item->next = *first;
    }
}

/*
 * Remove item from linked list starting at *first
 */
static void removeItem(GSCacheItem *item, GSCacheItem **first)
{
  if (*first == item)
    {
      if (item->next == item)
	{
	  *first = nil; 
	}
      else
	{
	  *first = item->next;
	}
    }
  item->next->prev = item->prev;
  item->prev->next = item->next;
  item->prev = item->next = item;
}

+ (NSArray*) allInstances
{
  NSArray	*a;

  [GSCacheLock lock];
  a = NSAllHashTableObjects(GSCacheInstances);
  [GSCacheLock unlock];
  return a;
}

+ (id) alloc
{
  return [self allocWithZone: NSDefaultMallocZone()];
}

+ (id) allocWithZone: (NSZone*)z
{
  GSCache	*c;

  c = (GSCache*)NSAllocateObject(self, sizeof(Item), z);
  [GSCacheLock lock];
  NSHashInsert(GSCacheInstances, (void*)c);
  [GSCacheLock unlock];
  return c;
}

+ (NSString*) description
{
  NSMutableString	*ms;
  NSHashEnumerator	e;
  GSCache		*c;

  ms = [NSMutableString stringWithString: [super description]];
  [GSCacheLock lock];
  e = NSEnumerateHashTable(GSCacheInstances);
  while ((c = (GSCache*)NSNextHashEnumeratorItem(&e)) != nil)
    {
      [ms appendFormat: @"\n%@", [c description]];
    }
  NSEndHashTableEnumeration(&e);
  [GSCacheLock unlock];
  return ms;
}

+ (void) initialize
{
  if (GSCacheInstances == 0)
    {
      GSCacheLock = [NSLock new];
      GSCacheInstances
	= NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
      GSTickerTimeNow();
    }
}

- (unsigned) currentObjects
{
  return my->currentObjects;
}

- (unsigned) currentSize
{
  return my->currentSize;
}

- (void) dealloc
{
  [GSCacheLock lock];
  NSHashRemove(GSCacheInstances, (void*)self);
  [GSCacheLock unlock];
  if (my->contents != 0)
    {
      [self shrinkObjects: 0 andSize: 0];
      NSFreeMapTable(my->contents);
    }
  RELEASE(my->exclude);
  RELEASE(my->name);
  [super dealloc];
}

- (id) delegate
{
  return my->delegate;
}

- (NSString*) description
{
  NSString	*n = my->name;

  if (n == nil)
    {
      n = [super description];
    }
  return [NSString stringWithFormat:
    @"  %@\n"
    @"    Items: %u(%u)\n"
    @"    Size:  %u(%u)\n"
    @"    Life:  %u\n"
    @"    Hit:   %u\n"
    @"    Miss: %u\n",
    n,
    my->currentObjects, my->maxObjects,
    my->currentSize, my->maxSize,
    my->lifetime,
    my->hits,
    my->misses];
}

- (id) init
{
  my->contents = NSCreateMapTable(NSObjectMapKeyCallBacks,
    NSObjectMapValueCallBacks, 0);
  return self;
}

- (unsigned) lifetime
{
  return my->lifetime;
}

- (unsigned) maxObjects
{
  return my->maxObjects;
}

- (unsigned) maxSize
{
  return my->maxSize;
}

- (NSString*) name
{
  return my->name;
}

- (id) objectForKey: (NSString*)aKey
{
  GSCacheItem	*item;
  unsigned	when = GSTickerTimeTick();

  item = (GSCacheItem*)NSMapGet(my->contents, aKey);
  if (item == nil)
    {
      my->misses++;
      return nil;
    }
  if (item->when > 0 && item->when < when)
    {
      if ([my->delegate shouldKeepItem: item->object
			       withKey: aKey
				 after: when - item->when] == YES)
	{
	  // Refetch in case delegate changed it.
	  item = (GSCacheItem*)NSMapGet(my->contents, aKey);
	  if (item == nil)
	    {
	      my->misses++;
	      return nil;
	    }
	}
      else
	{
	  removeItem(item, &my->first);
	  my->currentObjects--;
	  if (my->maxSize > 0)
	    {
	      my->currentSize -= item->size;
	    }
	  NSMapRemove(my->contents, (void*)item->key);
	  my->misses++;
	  return nil;	// Lifetime expired.
	}
    }

  // Least recently used ... move to end of list.
  removeItem(item, &my->first);
  appendItem(item, &my->first);
  my->hits++;
  return item->object;
}

- (void) purge
{
  unsigned	when = GSTickerTimeTick();

  if (my->contents != 0)
    {
      NSMapEnumerator	e;
      GSCacheItem		*i;
      NSString		*k;

      e = NSEnumerateMapTable(my->contents);
      while (NSNextMapEnumeratorPair(&e, (void**)&k, (void**)&i) != 0)
	{
	  if (i->when > 0 && i->when < when)
	    {
	      removeItem(i, &my->first);
	      my->currentObjects--;
	      if (my->maxSize > 0)
		{
		  my->currentSize -= i->size;
		}
	      NSMapRemove(my->contents, (void*)i->key);
	    }
	}
      NSEndMapTableEnumeration(&e);
    }
}

- (void) release
{
  /* We lock the table while checking, to prevent
   * another thread from grabbing this object while we are
   * checking it.
   * If we are going to deallocate the object, we first remove
   * it from the table so that no other thread will find it
   * and try to use it while it is being deallocated.
   */
  [GSCacheLock lock];
  if (NSDecrementExtraRefCountWasZero(self))
    {
      NSHashRemove(GSCacheInstances, (void*)self);
      [GSCacheLock unlock];
      [self dealloc];
    }
  else
    {
      [GSCacheLock unlock];
    }
}

- (void) setDelegate: (id)anObject
{
  my->delegate = anObject;
}

- (void) setLifetime: (unsigned)max
{
  my->lifetime = max;
}

- (void) setMaxObjects: (unsigned)max
{
  my->maxObjects = max;
  if (my->currentObjects > my->maxObjects)
    {
      [self shrinkObjects: my->maxObjects
		  andSize: my->maxSize];
    }
}

- (void) setMaxSize: (unsigned)max
{
  if (max > 0 && my->maxSize == 0)
    {
      NSMapEnumerator	e = NSEnumerateMapTable(my->contents);
      GSCacheItem		*i;
      NSString		*k;
      unsigned		size = 0;

      if (my->exclude == nil)
	{
	  my->exclude = [NSMutableSet new];
	}
      while (NSNextMapEnumeratorPair(&e, (void**)&k, (void**)&i) != 0)
	{
	  if (i->size == 0)
	    {
	      [my->exclude removeAllObjects];
	      i->size = [i->object sizeInBytes: my->exclude];
	    }
	  if (i->size > max)
	    {
	      /*
	       * Item in cache is too big for new size limit ...
	       * Remove it.
	       */
	      removeItem(i, &my->first);
	      NSMapRemove(my->contents, (void*)i->key);
	      my->currentObjects--;
	      continue;
	    }
	  size += i->size;
	}
      NSEndMapTableEnumeration(&e);
      my->currentSize = size;
    }
  else if (max == 0)
    {
      my->currentSize = 0;
    }
  my->maxSize = max;
  if (my->currentSize > my->maxSize)
    {
      [self shrinkObjects: my->maxObjects
		  andSize: my->maxSize];
    }
}

- (void) setName: (NSString*)name
{
  ASSIGN(my->name, name);
}

- (void) setObject: (id)anObject forKey: (NSString*)aKey
{
  [self setObject: anObject forKey: aKey lifetime: my->lifetime];
}

- (void) setObject: (id)anObject
	    forKey: (NSString*)aKey
	  lifetime: (unsigned)lifetime
{
  GSCacheItem	*item;
  unsigned	maxObjects = my->maxObjects;
  unsigned	maxSize = my->maxSize;
  unsigned	addObjects = (anObject == nil ? 0 : 1);
  unsigned	addSize = 0;

  item = (GSCacheItem*)NSMapGet(my->contents, aKey);
  if (item != nil)
    {
      removeItem(item, &my->first);
      my->currentObjects--;
      if (my->maxSize > 0)
	{
	  my->currentSize -= item->size;
	}
      NSMapRemove(my->contents, (void*)aKey);
    }

  if (addObjects > 0 && (maxSize > 0 || maxObjects > 0))
    {
      if (maxSize > 0)
	{
	  if (my->exclude == nil)
	    {
	      my->exclude = [NSMutableSet new];
	    }
	  [my->exclude removeAllObjects];
	  addSize = [anObject sizeInBytes: my->exclude];
	  if (addSize > maxSize)
	    {
	      return;	// Object too big to cache.
	    }
	}
    }

  if (addObjects > 0)
    {
      /*
       * Make room for new object.
       */
      [self shrinkObjects: maxObjects - addObjects
		  andSize: maxSize - addSize];
      item = [GSCacheItem newWithObject: anObject forKey: aKey];
      if (lifetime > 0)
	{
	  item->when = GSTickerTimeTick() + lifetime;
	}
      item->size = addSize;
      NSMapInsert(my->contents, (void*)item->key, (void*)item);
      appendItem(item, &my->first);
      my->currentObjects += addObjects;
      my->currentSize += addSize;
      RELEASE(item);
    }
}

- (void) setObject: (id)anObject
            forKey: (NSString*)aKey
	     until: (NSDate*)expires
{
  NSTimeInterval	 i;

  i = (expires == nil) ? 0.0 : [expires timeIntervalSinceReferenceDate];
  i -= GSTickerTimeNow();
  if (i <= 0.0)
    {
      [self setObject: nil forKey: aKey];	// Already expired
    }
  else
    {
      unsigned	limit;

      if (i > 2415919103.0)
        {
	  limit = 0;	// Limit in far future.
	}
      else
	{
	  limit = (unsigned)i;
	}
      [self setObject: anObject
	       forKey: aKey
	     lifetime: limit];
    }
}

- (void) shrinkObjects: (unsigned)objects andSize: (unsigned)size 
{
  unsigned	newSize = [self currentSize];
  unsigned	newObjects = [self currentObjects];

  if (newObjects > objects || (my->maxSize > 0 && newSize > size))
    {
      [self purge];
      newSize = [self currentSize];
      newObjects = [self currentObjects];
      while (newObjects > objects || (my->maxSize > 0 && newSize > size))
	{
	  GSCacheItem	*item;

	  item = my->first;
	  removeItem(item, &my->first);
	  newObjects--;
	  if (my->maxSize > 0)
	    {
	      newSize -= item->size;
	    }
	  NSMapRemove(my->contents, (void*)item->key);
	}
      my->currentObjects = newObjects;
      my->currentSize = newSize;
    }
}
@end

@implementation	NSArray (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      unsigned	count = [self count];

      size += count*sizeof(void*);
      while (count-- > 0)
	{
	  size += [[self objectAtIndex: count] sizeInBytes: exclude];
	}
    }
  return size;
}
@end

@implementation	NSData (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      size += [self length];
    }
  return size;
}
@end

@implementation	NSDictionary (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      unsigned	count = [self count];

      size += 3 * sizeof(void*) * count;
      if (count > 0)
        {
	  CREATE_AUTORELEASE_POOL(pool);
	  NSEnumerator	*enumerator = [self keyEnumerator];
	  NSObject	*k;

	  while ((k = [enumerator nextObject]) != nil)
	    {
	      NSObject	*o = [self objectForKey: k];

	      size += [k sizeInBytes: exclude] + [o sizeInBytes: exclude];
	    }
	  RELEASE(pool);
	}
    }
  return size;
}
@end

@implementation	NSObject (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  if ([exclude member: self] != nil)
    {
      return 0;
    }
  [exclude addObject: self];
  return isa->instance_size;
}
@end

@implementation	NSSet (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      unsigned	count = [self count];

      size += 3 * sizeof(void*) * count;
      if (count > 0)
        {
	  CREATE_AUTORELEASE_POOL(pool);
	  NSEnumerator	*enumerator = [self objectEnumerator];
	  NSObject	*o;

	  while ((o = [enumerator nextObject]) != nil)
	    {
	      size += [o sizeInBytes: exclude];
	    }
	  RELEASE(pool);
	}
    }
  return size;
}
@end

@implementation	NSString (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  if ([exclude member: self] != nil)
    {
      return 0;
    }
  else
    {
      return [super sizeInBytes: exclude] + sizeof(unichar) * [self length];
    }
}
@end

#if	defined(GNUSTEP_BASE_LIBRARY)

#include	<GNUstepBase/GSMime.h>

@implementation	GSMimeDocument (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      size += [content sizeInBytes: exclude]; + [headers sizeInBytes: exclude];
    }
  return size;
}
@end

@implementation	GSMimeHeader (GSCacheSizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude
{
  unsigned	size = [super sizeInBytes: exclude];

  if (size > 0)
    {
      size += [name sizeInBytes: exclude]
        + [value sizeInBytes: exclude]
        + [objects sizeInBytes: exclude]
        + [params sizeInBytes: exclude];
    }
  return size;
}
@end

#endif

