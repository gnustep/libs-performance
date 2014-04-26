#if	!defined(INCLUDED_GSUNIQUED)
#define	INCLUDED_GSUNIQUED	1
/**
   Copyright (C) 2014 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:        April 2014

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
#import <Foundation/NSObject.h>

/** Class used to unique other objects.<br />
 * <p>The point of this class is to lower the memory footprint and speed
 * up comparisons (pointer equality) in cases where an application
 * stores multiple copies of the same object in various maps.<br />
 * Since uniquing is performed by storing an immutable copy of the
 * original object in a map until there are no further references
 * to that object, it's pointless to use this uniquing unless the
 * application would be storing at least two copies of the object.<br />
 * Also, since this is thread-safe there is a lock management
 * overhead wherever a uniqued object is released, so performance
 * gains are to be expected only if the uniqued object has a
 * relatively long lifetime and is tested for equality with other
 * instances frequently.<br />
 * In short, use with care; while uniquing can have a big performance
 * advantage for some programs, this is actually quite rare.
 * </p>
 * <p>The internal implementation of the uniquing works by taking
 * immutable copies of the objects to be uniqued, storing those copies
 * in a hash table, and swizzling their class pointers to a sub-class 
 * which will automatically remove the instance from the hash table
 * before it is deallocated.<br />
 * Access to the hash table is protected by locks so that uniqued
 * objects may be used freely in multiple threads.<br />
 * The name of the subclass used is the name of the original class
 * with 'GSUniqued' added as a prefix.
 * </p>
 */
@interface      GSUniqued : NSObject

/** This method returns a copy of its argument, uniqued so that other
 * such copies of equal objects will be the same instance.<br />
 * The argument must respond to -copyWithZone: by returning an instance
 * of class of immutable objects (ie where the -hash and -isEqual:
 * methods are stable for that instance).
 */
+ (id) copyUniqued: (id<NSObject,NSCopying>)anObject;

@end

/** Category for uniquing any copyable object.<br />
 * NB.  This must only be used by classes for which -copyWithZone: 
 * produces an instance of an immutable class.
 */
@interface NSObject (GSUniqued)

/** This method returns a copy of the receiver uniqued so that other
 * such copies of equal objects content will be the same instance.
 */
- (id) copyUniqued;

@end

#endif

