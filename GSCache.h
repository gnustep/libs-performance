/** 
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

#ifndef	INCLUDED_GSCache_H
#define	INCLUDED_GSCache_H

#include	<Foundation/NSObject.h>
#include	<Foundation/NSArray.h>
#include	<Foundation/NSData.h>
#include	<Foundation/NSDate.h>
#include	<Foundation/NSString.h>

@class	NSMutableSet;

/**
 * The GSCache class is used to maintain a cache of objects in memory
 * for relatiovely rapid access.<br />
 * Typical usage might be to keep the results of a database query around
 * for a while in order to re-use them ... for instance when application
 * configuration is obtained from a database which might be updated while
 * the application is running.<br />
 * When the cache is full, old objects are removed to make room for new
 * ones on a least-recently-used basis.<br />
 * Cache sizes may be limited by the number of objects in the cache,
 * or by the memory used by the cache, or both.  Calculation of the
 * size of items in the cache is relatively expensive, so caches are
 * only limited by number of objects in the default case.<br />
 * Objects stored in the cache may be given a limited lifetime,
 * in which case an attempt to fetch an <em>expired</em> object
 * from the cache will cause it to be removed from the cache instead
 * (subject to control by the delegate).
 */
@interface	GSCache : NSObject
{
}

/**
 * Return all the current cache instances... useful if you want to do
 * something to all cache instances in your process.
 */
+ (NSArray*) allInstances;

/**
 * Return a report on all GSCache instances ... calls the [GSCache-description]
 * method of the individual cache instances to get a report on each one.
 */
+ (NSString*) description;

/**
 * Return the count of objects currently in the cache.
 */
- (unsigned) currentObjects;

/**
 * Return the total size of the objects currently in the cache.
 */
- (unsigned) currentSize;

/**
 * Return the delegate object previously set using the -setDelegate: method.
 */
- (id) delegate;

/**
 * Returns a string describing the status of the receiver for debug/reporting.
 */
- (NSString*) description;

/**
 * Return the default lifetime for items set in the cache.<br />
 * A value of zero means that items are not purged based on lifetime.
 */
- (unsigned) lifetime;

/**
 * Return the maximum number of items in the cache.<br />
 * A value of zero means there is no limit.
 */
- (unsigned) maxObjects;

/**
 * Return the maximum tital size of items in the cache.<br />
 * A value of zero means there is no limit.
 */
- (unsigned) maxSize;

/**
 * Return the name of this instance (as set using -setName:)
 */
- (NSString*) name;

/**
 * Return the cached value for the specified key, or nil if there
 * is no value in the cache.
 */
- (id) objectForKey: (NSString*)aKey;

/**
 * Remove all items whose lifetimes have passed
 * (if lifetimes are in use for the cache).<br />
 */
- (void) purge;

/**
 * Sets the delegate for the receiver.<br />
 * The delegate object is not retained.<br />
 * If a delegate it set, it must implement the methods in the
 * (GSCacheDelegate) protocol.
 */
- (void) setDelegate: (id)anObject;

/**
 * Sets the lifetime (seconds) for items added to the cache.  If this
 * is set to zero then items are not removed from the cache based on
 * lifetimes when the cache is full and an object is added, though
 * <em>expired</em> items are still removed when an attempt to retrieve
 * them is made.
 */
- (void) setLifetime: (unsigned)max;

/**
 * Sets the maximum number of objects in the cache.  If this is non-zero
 * then an attempt to set an object in a full cache will result in the
 * least recently used item in the cache being removed.
 */
- (void) setMaxObjects: (unsigned)max;

/**
 * Sets the maximum total size for objects in the cache.  If this is non-zero
 * then an attempt to set an object whose size would exceed the cache limit
 * will result in the least recently used items in the cache being removed.
 */
- (void) setMaxSize: (unsigned)max;

/**
 * Sets the name of this instance.
 */
- (void) setName: (NSString*)name;

/**
 * Sets (or replaces)the cached value for the specified key.
 */
- (void) setObject: (id)anObject forKey: (NSString*)aKey;

/**
 * Sets (or replaces)the cached value for the specified key, giving
 * the value the specified lifetime (in seconds).  A lifetime of zero
 * means that the item is not limited by lifetime.
 */
- (void) setObject: (id)anObject
	    forKey: (NSString*)aKey
	  lifetime: (unsigned)lifetime;

/**
 * Sets (or replaces)the cached value for the specified key, giving
 * the value the specified expiry date.  Calls -setObject:forKey:lifetime:
 * to do the real work ... this is just a convenience method to
 * handle working out the lifetime in seconds.<br />
 * If expires is nil or not in the future, this method simply removes the
 * cache entry for aKey.  If it is many years in the future, the item is
 * set in the cache so that it is not limited by lifetime.
 */
- (void) setObject: (id)anObject
	    forKey: (NSString*)aKey
	     until: (NSDate*)expires;

/**
 * Called by -setObject:forKey:lifetime: to make space for a new
 * object in the cache (also when the cache is resized).<br />
 * This will, if a lifetime is set (see the -setLifetime: method)
 * first purge all <em>expired</em> objects from the cache, then
 * (if necessary) remove objects from the cache until the number
 * of objects and size of cache meet the limits specified.<br />
 * If the objects argument is zero then all objects are removed from
 * the cache.<br />
 * The size argument is used <em>only</em> if a maximum size is set
 * for the cache.
 */
- (void) shrinkObjects: (unsigned)objects andSize: (unsigned)size; 
@end

/**
 * This protocol defines the messages which may be sent to a delegate
 * of a GSCache object.
 */
@protocol	GSCacheDelegate

/**
 * Asks the delegate to decide whether anObject, which was cached
 * using aKey and expired delay seconds ago should still be retained
 * in the cache.<br />
 * This is called when an attempt is made to access the cached value
 * for aKey and the object is found in the cache but it is no longer
 * valid (has expired).<br />
 * If the method returns YES, then anObject will not be removed as it
 * normally would.  This allows the delegate to change the cached item
 * or refresh it.<br />
 * For instance, the delegate could replace the object
 * in the cache before returning YES in order to update the cached value
 * when its lifetime has expired.<br />
 * Another possibility would be for the delegate to return YES (in order
 * to continue using the existing object) and queue an asynchronous
 * database query to update the cache later.
 */
- (BOOL) shouldKeepItem: (id)anObject
		withKey: (NSString*)aKey
		  after: (unsigned)delay;

@end


@interface	NSArray (SizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude;
@end

@interface	NSData (SizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude;
@end

@interface	NSObject (SizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude;
@end

@interface	NSString (SizeInBytes)
- (unsigned) sizeInBytes: (NSMutableSet*)exclude;
@end

#endif

