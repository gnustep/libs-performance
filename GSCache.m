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

#include <inttypes.h>

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
#import	<Foundation/NSString.h>
#import	<Foundation/NSThread.h>
#import	<Foundation/NSUserDefaults.h>
#import	<Foundation/NSValue.h>

#import	"GSCache.h"
#import	"GSTicker.h"

#if !defined(GNUSTEP)
#include <objc/objc-class.h>
#if (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
#define class_getInstanceSize(isa)  ((struct objc_class *)isa)->instance_size
#endif

#import "NSObject+GSExtensions.h"

#endif

@interface	GSCache (Private)
- (void) _useDefaults: (NSNotification*)n;
@end

@interface	GSCacheItem : NSObject
{
@public
  GSCacheItem	*next;
  GSCacheItem	*prev;
  unsigned	life;
  unsigned	warn;
  unsigned	when;
  NSUInteger	size;
  id	        key;
  id		object;
}
+ (GSCacheItem*) newWithObject: (id)anObject forKey: (id)aKey;
@end

@implementation	GSCacheItem
+ (GSCacheItem*) newWithObject: (id)anObject forKey: (id)aKey
{
  GSCacheItem	*i;

  i = (GSCacheItem*)NSAllocateObject(self, 0, NSDefaultMallocZone());
  i->object = [anObject retain];
  i->key = [aKey copy];
  return i;
}
- (void) dealloc
{
  [key release];
  [object release];
  [super dealloc];
}
- (NSUInteger) sizeInBytesExcluding: (NSHashTable*)exclude
{
  NSUInteger    bytes = [super sizeInBytesExcluding: exclude];

  if (bytes > 0)
    {
      bytes += [key sizeInBytesExcluding: exclude];
      bytes += [object sizeInBytesExcluding: exclude];
    }
  return bytes;
}
@end


@implementation	GSCache

static NSHashTable	*allCaches = 0;
static NSRecursiveLock	*allCachesLock = nil;
static int		itemOffset = 0;

typedef struct {
  id		delegate;
  void		(*refresh)(id, SEL, id, id, unsigned, unsigned);
  BOOL		(*replace)(id, SEL, id, id, unsigned, unsigned);
  unsigned	currentObjects;
  NSUInteger	currentSize;
  unsigned	lifetime;
  unsigned	maxObjects;
  NSUInteger	maxSize;
  unsigned	hits;
  unsigned	misses;
  NSMapTable	*contents;
  GSCacheItem	*first;
  NSString	*name;
  NSHashTable	*exclude;
  NSRecursiveLock	*lock;
  BOOL		useDefaults;
} Item;
#define	my	((Item*)((void*)self + itemOffset))

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

  [allCachesLock lock];
  a = NSAllHashTableObjects(allCaches);
  [allCachesLock unlock];
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
  return c;
}

+ (NSString*) description
{
  NSMutableString	*ms;
  NSHashEnumerator	e;
  GSCache		*c;

  ms = [NSMutableString stringWithString: [super description]];
  [allCachesLock lock];
  e = NSEnumerateHashTable(allCaches);
  while ((c = (GSCache*)NSNextHashEnumeratorItem(&e)) != nil)
    {
      [ms appendFormat: @"\n%@", [c description]];
    }
  NSEndHashTableEnumeration(&e);
  [allCachesLock unlock];
  return ms;
}

+ (void) initialize
{
  if (allCaches == 0)
    {
      itemOffset = class_getInstanceSize(self);
      allCaches = NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
      GSTickerTimeNow();
    }
}

- (unsigned) currentObjects
{
  return my->currentObjects;
}

- (NSUInteger) currentSize
{
  return my->currentSize;
}

- (void) dealloc
{
  if (my->useDefaults)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self
	name: NSUserDefaultsDidChangeNotification object: nil];
    }
  if (my->contents != 0)
    {
      [self shrinkObjects: 0 andSize: 0];
      NSFreeMapTable(my->contents);
    }
  [my->exclude release];
  [my->name release];
  [my->lock release];
  [super dealloc];
}

- (id) delegate
{
  return my->delegate;
}

- (NSString*) description
{
  NSString	*n;

  [my->lock lock];
  n = my->name;
  if (n == nil)
    {
      n = [super description];
    }
  n = [NSString stringWithFormat:
    @"  %@\n"
    @"    Items: %u(%u)\n"
    @"    Size:  %"PRIuPTR"(%"PRIuPTR")\n"
    @"    Life:  %u\n"
    @"    Hit:   %u\n"
    @"    Miss: %u\n",
    n,
    my->currentObjects, my->maxObjects,
    my->currentSize, my->maxSize,
    my->lifetime,
    my->hits,
    my->misses];
  [my->lock unlock];
  return n;
}

- (id) init
{
  if (nil != (self = [super init]))
    {
      my->lock = [NSRecursiveLock new];
      my->contents = NSCreateMapTable(NSObjectMapKeyCallBacks,
	NSObjectMapValueCallBacks, 0);
      [allCachesLock lock];
      NSHashInsert(allCaches, (void*)self);
      [allCachesLock unlock];
    }
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

- (NSUInteger) maxSize
{
  return my->maxSize;
}

- (NSString*) name
{
  NSString	*n;

  [my->lock lock];
  n = [my->name retain];
  [my->lock unlock];
  return [n autorelease];
}

- (id) objectForKey: (id)aKey
{
  id		object;
  GSCacheItem	*item;
  unsigned	when = GSTickerTimeTick();

  [my->lock lock];
  item = (GSCacheItem*)NSMapGet(my->contents, aKey);
  if (item == nil)
    {
      my->misses++;
      [my->lock unlock];
      return nil;
    }
  if (item->when > 0 && item->when < when)
    {
      BOOL	keep = NO;

      if (0 != my->replace)
	{
	  GSCacheItem	*orig = [item retain];

	  [my->lock unlock];
          keep = (*(my->replace))(my->delegate,
	    @selector(shouldKeepItem:withKey:lifetime:after:),
	    item->object,
	    aKey,
	    item->life,
	    when - item->when);
	  [my->lock lock];
	  if (keep == YES)
	    {
	      GSCacheItem	*current;

	      /* Refetch in case delegate changed it.
	       */
	      current = (GSCacheItem*)NSMapGet(my->contents, aKey);
	      if (current == nil)
		{
		  /* Delegate must have deleted the item even though
		   * it returned YES to say we should keep it ...
		   * we count this as a miss.
		   */
		  my->misses++;
		  [my->lock unlock];
		  [orig release];
		  return nil;
		}
	      else if (orig == current)
		{
		  /* Delegate told us to keep the original item so we
		   * update its expiry time.
		   */
		  item->when = when + item->life;
		  item->warn = when + item->life / 2;
		}
	      else
		{
		  /* Delegate replaced the item with another and told
		   * us to keep that one.
		   */
		  item = current;
		}
	    }
	  [orig release];
	}

      if (keep == NO)
	{
	  removeItem(item, &my->first);
	  my->currentObjects--;
	  if (my->maxSize > 0)
	    {
	      my->currentSize -= item->size;
	    }
	  NSMapRemove(my->contents, (void*)item->key);
	  my->misses++;
	  [my->lock unlock];
	  return nil;	// Lifetime expired.
	}
    }
  else if (item->warn > 0 && item->warn < when)
    {
      item->warn = 0;	// Don't warn again.
      if (0 != my->refresh)
	{
	  GSCacheItem	*orig = [item retain];
	  GSCacheItem	*current;

	  [my->lock unlock];
          (*(my->refresh))(my->delegate,
	    @selector(mayRefreshItem:withKey:lifetime:after:),
	    item->object,
	    aKey,
	    item->life,
	    when - item->when);
	  [my->lock lock];

	  /* Refetch in case delegate changed it.
	   */
	  current = (GSCacheItem*)NSMapGet(my->contents, aKey);
	  if (current == nil)
	    {
	      /* Delegate must have deleted the item!
	       * So we count this as a miss.
	       */
	      my->misses++;
	      [my->lock unlock];
	      [orig release];
	      return nil;
	    }
	  else
	    {
	      item = current;
	    }
	  [orig release];
	}
    }

  // Least recently used ... move to end of list.
  removeItem(item, &my->first);
  appendItem(item, &my->first);
  my->hits++;
  object = [item->object retain];
  [my->lock unlock];
  return [object autorelease];
}

- (void) purge
{
  if (my->contents != 0)
    {
      unsigned		when = GSTickerTimeTick();
      NSMapEnumerator	e;
      GSCacheItem	*i;
      id		k;

      [my->lock lock];
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
      [my->lock unlock];
    }
}

- (oneway void) release
{
  /* We lock the table while checking, to prevent
   * another thread from grabbing this object while we are
   * checking it.
   * If we are going to deallocate the object, we first remove
   * it from the table so that no other thread will find it
   * and try to use it while it is being deallocated.
   */
  [allCachesLock lock];
  if ([self retainCount] == 1
    && NSHashGet(allCaches, (void*)self) == self)
    {
      NSHashRemove(allCaches, (void*)self);
    }
  [super release];
  [allCachesLock unlock];
}

- (id) refreshObject: (id)anObject
              forKey: (id)aKey
            lifetime: (unsigned)lifetime
{
  id		object;
  GSCacheItem	*item;

  [my->lock lock];
  item = (GSCacheItem*)NSMapGet(my->contents, aKey);
  if (item == nil)
    {
      if (nil != anObject)
        {
          [self setObject: anObject
                   forKey: aKey
                 lifetime: lifetime];
        }
      [my->lock unlock];
      return anObject;
    }

  if (nil != anObject && NO == [anObject isEqual: item->object])
    {
      object = [anObject retain];
      [item->object release];
      item->object = object;
    }
  if (lifetime > 0)
    {
      unsigned	tick = GSTickerTimeTick();

      item->when = tick + lifetime;
      item->warn = tick + lifetime / 2;
    }
  item->life = lifetime;
  object = [[item->object retain] autorelease];
  [my->lock unlock];
  return object;
}

- (void) setDelegate: (id)anObject
{
  [my->lock lock];
  my->delegate = anObject;
  if ([my->delegate respondsToSelector:
    @selector(shouldKeepItem:withKey:lifetime:after:)])
    {
      my->replace = (BOOL (*)(id,SEL,id,id,unsigned,unsigned))
	[my->delegate methodForSelector:
	@selector(shouldKeepItem:withKey:lifetime:after:)];
    }
  else
    {
      my->replace = 0;
    }
  if ([my->delegate respondsToSelector:
    @selector(mayRefreshItem:withKey:lifetime:after:)])
    {
      my->refresh = (void (*)(id,SEL,id,id,unsigned,unsigned))
	[my->delegate methodForSelector:
	@selector(mayRefreshItem:withKey:lifetime:after:)];
    }
  else
    {
      my->refresh = 0;
    }
  [my->lock unlock];
}

- (void) setLifetime: (unsigned)max
{
  [my->lock lock];
  if (YES == my->useDefaults)
    {
      NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
      NSString          *n = (nil == my->name) ? @"" : my->name;
      NSString          *k = [@"GSCacheLifetime" stringByAppendingString: n];

      if (nil != [defs objectForKey: k])
        {
          max = (unsigned) [defs integerForKey: k];
        }
    }
  my->lifetime = max;
  [my->lock unlock];
}

- (void) setMaxObjects: (unsigned)max
{
  [my->lock lock];
  if (YES == my->useDefaults)
    {
      NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
      NSString          *n = (nil == my->name) ? @"" : my->name;
      NSString          *k = [@"GSCacheMaxObjects" stringByAppendingString: n];

      if (nil != [defs objectForKey: k])
        {
          max = (unsigned) [defs integerForKey: k];
        }
    }
  my->maxObjects = max;
  if (my->currentObjects > my->maxObjects)
    {
      [self shrinkObjects: my->maxObjects
                  andSize: my->maxSize];
    }
  [my->lock unlock];
}

- (void) setMaxSize: (NSUInteger)max
{
  [my->lock lock];
  if (YES == my->useDefaults)
    {
      NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
      NSString          *n = (nil == my->name) ? @"" : my->name;
      NSString          *k = [@"GSCacheMaxSize" stringByAppendingString: n];

      if (nil != [defs objectForKey: k])
        {
          max = (NSUInteger) [defs integerForKey: k];
        }
    }
  if (max > 0 && my->maxSize == 0)
    {
      NSMapEnumerator	e = NSEnumerateMapTable(my->contents);
      GSCacheItem	*i;
      id		k;
      NSUInteger	size = 0;

      if (nil == my->exclude)
        {
          my->exclude
            = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);
        }
      while (NSNextMapEnumeratorPair(&e, (void**)&k, (void**)&i) != 0)
        {
          if (i->size == 0)
            {
              i->size = [i->object sizeInBytesExcluding: my->exclude];
              [my->exclude removeAllObjects];
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
  [my->lock unlock];
}

- (void) setName: (NSString*)name forConfiguration: (BOOL)useDefaults
{
  NSString	*c;

  [my->lock lock];
  c = [name copy];
  [my->name release];
  my->name = c;
  useDefaults = (useDefaults ? YES : NO);	// Make sure this is a real bool
  if (my->useDefaults != useDefaults)
    {
      if (my->useDefaults)
	{
	  [[NSNotificationCenter defaultCenter] removeObserver: self
	    name: NSUserDefaultsDidChangeNotification object: nil];
	}
      my->useDefaults = useDefaults;
      if (my->useDefaults)
	{
	  [[NSNotificationCenter defaultCenter]
	    addObserver: self
	    selector: @selector(_useDefaults:)
	    name: NSUserDefaultsDidChangeNotification
	    object: nil];
	  [self _useDefaults: nil];
	}
    }
  [my->lock unlock];
}

- (void) setName: (NSString*)name
{
  [self setName: name forConfiguration: NO];
}

- (void) setObject: (id)anObject forKey: (id)aKey
{
  [self setObject: anObject forKey: aKey lifetime: my->lifetime];
}

- (void) setObject: (id)anObject
	    forKey: (id)aKey
	  lifetime: (unsigned)lifetime
{
  GSCacheItem	*item;
  unsigned	maxObjects;
  NSUInteger	maxSize;
  unsigned	addObjects = (anObject == nil ? 0 : 1);
  NSUInteger	addSize = 0;

  if (aKey == nil)
    {
      [NSException raise: NSInvalidArgumentException
                  format: @"Attempt to add nil key to cache"];
    }
  [my->lock lock];
  maxObjects = my->maxObjects;
  maxSize = my->maxSize;
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
          if (nil == my->exclude)
            {
              my->exclude
                = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);
            }
	  addSize = [anObject sizeInBytesExcluding: my->exclude];
	  [my->exclude removeAllObjects];
	  if (addSize > maxSize)
	    {
	      addObjects = 0;	// Object too big to cache.
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
	  unsigned	tick = GSTickerTimeTick();

	  item->when = tick + lifetime;
	  item->warn = tick + lifetime / 2;
	}
      item->life = lifetime;
      item->size = addSize;
      NSMapInsert(my->contents, (void*)item->key, (void*)item);
      appendItem(item, &my->first);
      my->currentObjects += addObjects;
      my->currentSize += addSize;
      [item release];
    }
  [my->lock unlock];
}

- (void) setObject: (id)anObject
            forKey: (id)aKey
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

- (void) shrinkObjects: (unsigned)objects andSize: (NSUInteger)size 
{
  NSUInteger	newSize;
  unsigned	newObjects;

  [my->lock lock];
  newSize = [self currentSize];
  newObjects = [self currentObjects];
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
  [my->lock unlock];
}

- (NSUInteger) sizeInBytesExcluding: (NSHashTable*)exclude
{
  NSUInteger    size;

  [my->lock lock];
  size = [super sizeInBytesExcluding: exclude];
  if (size > 0)
    {
      size += sizeof(Item)
        + [my->contents sizeInBytesExcluding: exclude]
        + [my->exclude sizeInBytesExcluding: exclude]
        + [my->name sizeInBytesExcluding: exclude]
        + [my->lock sizeInBytesExcluding: exclude];
    }
  [my->lock unlock];
  return size;
}

@end
@implementation	GSCache (Private)
- (void) _useDefaults: (NSNotification*)n
{
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSString		*conf = (nil == my->name ? @"" : my->name);
  NSString		*key;

  [my->lock lock];
  NS_DURING
    {
      if (YES == my->useDefaults)
	{
	  my->useDefaults = NO;
	  key = [@"GSCacheLifetime" stringByAppendingString: conf];
	  if (nil != [defs objectForKey: key])
	    {
	      [self setLifetime: (unsigned)[defs integerForKey: key]];
	    }
	  key = [@"GSCacheMaxObjects" stringByAppendingString: conf];
	  if (nil != [defs objectForKey: key])
	    {
	      [self setMaxObjects: (unsigned)[defs integerForKey: key]];
	    }
	  key = [@"GSCacheMaxSize" stringByAppendingString: conf];
	  if (nil != [defs objectForKey: key])
	    {
	      [self setMaxSize: (NSUInteger)[defs integerForKey: key]];
	    }
	  my->useDefaults = YES;
	}
      [my->lock unlock];
    }
  NS_HANDLER
    {
      my->useDefaults = YES;
      [my->lock unlock];
      [localException raise];
    }
  NS_ENDHANDLER
}
@end


