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

#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSSet.h>
#import <GNUstepBase/GSObjCRuntime.h>
#import "GSUniqued.h"


static Class                    GSUniquedClass = Nil;
static NSLock                   *uniquedObjectsLock;
static IMP                      iLock;
static IMP                      iUnlock;
static NSHashTable              *uniquedObjects;
static NSLock                   *classLock;
static NSMutableDictionary      *classMap;

/* Deallocate a uniqued object ... we must remove it from the uniqued
 * objects table and then call the real -dealloc method.
 */
static void
uDealloc(id self, SEL _cmd)
{
  Class c;
  IMP   i;

  NSHashRemove(uniquedObjects, self);
  c = object_getClass(self);
  c = class_getSuperclass(c);
  i = class_getMethodImplementation(c, _cmd);
  (*i)(self, _cmd);
}

/* Release a uniqued object ... we must obtain a lock in case the uniqued
 * objects table has to be modified by removal of this instance on
 * deallocation.
 */
static void
uRelease(id self, SEL _cmd)
{
  Class c;
  IMP   i;

  c = object_getClass(self);
  c = class_getSuperclass(c);
  i = class_getMethodImplementation(c, _cmd);
  (*iLock)(uniquedObjectsLock, @selector(lock));
  (*i)(self, _cmd);
  (*iUnlock)(uniquedObjectsLock, @selector(unlock));
}

@implementation GSUniqued

static Class    NSObjectClass;

+ (void) initialize
{
  if (Nil == GSUniquedClass)
    {
      classLock = [NSLock new];
      classMap = [NSMutableDictionary new];
      uniquedObjectsLock = [NSLock new];
      iLock = [uniquedObjectsLock methodForSelector: @selector(lock)];
      iUnlock = [uniquedObjectsLock methodForSelector: @selector(unlock)];
      uniquedObjects = NSCreateHashTable(
        NSNonRetainedObjectHashCallBacks, 10000);
      NSObjectClass = [NSObject class];
      GSUniquedClass = [GSUniqued class];
    }
}

+ (id) allocWithZone: (NSZone*)z
{
  [NSException raise: NSInvalidArgumentException
              format: @"Attempt to allocate instance of GSUniqued"];
  return nil;
}

+ (id) copyUniqued: (id<NSObject,NSCopying>)anObject
{
  NSObject      *found;

  NSAssert(nil != anObject, NSInvalidArgumentException);
  (*iLock)(uniquedObjectsLock, @selector(lock));
  found = [(NSObject*)NSHashGet(uniquedObjects, anObject) retain];
  (*iUnlock)(uniquedObjectsLock, @selector(unlock));

  if (nil == found)
    {
      NSObject  *aCopy;
      Class     c;
      Class     u;

      aCopy = [anObject copyWithZone: NSDefaultMallocZone()];
      if (aCopy == anObject)
        {
          /* Unable to make a copy ... that probably means the object
           * is already unique and we can just return it.
           */
          if (NO == [aCopy isKindOfClass: [NSString class]])
            {
              return aCopy;
            }
          else
            {
              NSMutableString   *m;

              /* We have different subclasses of NSString and we can't swizzle
               * a constant string, so in that case we need to work with another
               * type of string.
               */
              m = [aCopy mutableCopy];
              [aCopy release];
              aCopy = [m copy];
              [m release];
            }
        }
      c = object_getClass(aCopy);

      [classLock lock];
      u = [classMap objectForKey: (id<NSCopying>)c];
      if (Nil == u)
        {
          const char    *cn = class_getName(c);
          char          name[strlen(cn) + 20];
          Method        method;

          sprintf(name, "GSUniqued%s", cn);
          u = objc_allocateClassPair(c, name, 0);

          method = class_getInstanceMethod(NSObjectClass,
            @selector(dealloc));
          class_addMethod(u, @selector(dealloc),
            (IMP)uDealloc, method_getTypeEncoding(method));

          method = class_getInstanceMethod(NSObjectClass,
            @selector(release));
          class_addMethod(u, @selector(release),
            (IMP)uRelease, method_getTypeEncoding(method));

          method = class_getInstanceMethod(GSUniquedClass,
            @selector(copyUniqued));
          class_addMethod(u, @selector(copyUniqued),
            class_getMethodImplementation(GSUniquedClass,
            @selector(copyUniqued)),
            method_getTypeEncoding(method));

          objc_registerClassPair(u);
          [classMap setObject: u forKey: (id<NSCopying>)c];
        }
      [classLock unlock];

      (*iLock)(uniquedObjectsLock, @selector(lock));
      found = [(NSObject*)NSHashGet(uniquedObjects, anObject) retain];
      if (nil == found)
        {
          found = aCopy;
#if defined(GNUSTEP)
          GSClassSwizzle(found, u);
#else
          object_setClass(found, u);
#endif
          NSHashInsert(uniquedObjects, found);
        }
      else
        {
          [aCopy release];      // Already uniqued by another thread
        }
      (*iUnlock)(uniquedObjectsLock, @selector(unlock));
    }
  return found;
}

- (id) copyUniqued
{
  return [self retain];
}
@end

@implementation NSObject (GSUniqued)

- (id) copyUniqued
{
  if (Nil == GSUniquedClass) [GSUniqued class];
  return [GSUniquedClass copyUniqued: (id<NSObject,NSCopying>)self];
}

@end

