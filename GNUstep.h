/* GNUstep.h - macros to make easier to port gnustep apps to macos-x
   Copyright (C) 2001 Free Software Foundation, Inc.
 
   Written by: Nicola Pero
   Date: March, October 2001
 
   This file is part of GNUstep.
 
   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
 
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
 
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
 */

#ifndef Performance_GNUstep_h
#define Performance_GNUstep_h

#ifndef	RETAIN
/**
 *	Basic retain operation ... calls [NSObject-retain]<br />
 *	Does nothing when ARC is in use.
 */
#define	RETAIN(object)		[(id)(object) retain]
#endif

#ifndef	RELEASE
/**
 *	Basic release operation ... calls [NSObject-release]<br />
 *	Does nothing when ARC is in use.
 */
#define	RELEASE(object)		[(id)(object) release]
#endif

#ifndef	AUTORELEASE
/**
 *	Basic autorelease operation ... calls [NSObject-autorelease]<br />
 *	Does nothing when ARC is in use.
 */
#define	AUTORELEASE(object)	[(id)(object) autorelease]
#endif

#ifndef	TEST_RETAIN
/**
 *	Tested retain - only invoke the
 *	objective-c method if the receiver is not nil.<br />
 *	Does nothing when ARC is in use.
 */
#define	TEST_RETAIN(object)	({\
void *__object = (void*)(object);\
(__object != 0) ? [(id)__object retain] : nil; })
#endif

#ifndef	TEST_RELEASE
/**
 *	Tested release - only invoke the
 *	objective-c method if the receiver is not nil.<br />
 *	Does nothing when ARC is in use.
 */
#define	TEST_RELEASE(object)	({\
void *__object = (void*)(object);\
if (__object != 0) [(id)__object release]; })
#endif

#ifndef	TEST_AUTORELEASE
/**
 *	Tested autorelease - only invoke the
 *	objective-c method if the receiver is not nil.<br />
 *	Does nothing when ARC is in use.
 */
#define	TEST_AUTORELEASE(object)	({\
void *__object = (void*)(object);\
(__object != 0) ? [(id)__object autorelease] : nil; })
#endif

#ifndef	ASSIGN
/**
 *	ASSIGN(object,value) assigns the value to the object with
 *	appropriate retain and release operations.<br />
 *	Use this to avoid retain/release errors.
 */
#define	ASSIGN(object,value)	({\
void *__object = (void*)object; \
object = (__typeof__(object))[(value) retain]; \
[(id)__object release]; \
})
#endif

#ifndef	ASSIGNCOPY
/**
 *	ASSIGNCOPY(object,value) assigns a copy of the value to the object
 *	with release of the original.<br />
 *	Use this to avoid retain/release errors.
 */
#define	ASSIGNCOPY(object,value)	({\
void *__object = (void*)object; \
object = (__typeof__(object))[(value) copy];\
[(id)__object release]; \
})
#endif

#ifndef	ASSIGNMUTABLECOPY
/**
 *	ASSIGNMUTABLECOPY(object,value) assigns a mutable copy of the value
 *	to the object with release of the original.<br />
 *	Use this to avoid retain/release errors.
 */
#define	ASSIGNMUTABLECOPY(object,value)	({\
void *__object = (void*)object; \
object = (__typeof__(object))[(value) mutableCopy];\
[(id)__object release]; \
})
#endif

#ifndef	DESTROY
/**
 *	DESTROY() is a release operation which also sets the variable to be
 *	a nil pointer for tidiness - we can't accidentally use a DESTROYED
 *	object later.  It also makes sure to set the variable to nil before
 *	releasing the object - to avoid side-effects of the release trying
 *	to reference the object being released through the variable.
 */
#define	DESTROY(object) 	({ \
void *__o = (void*)object; \
object = nil; \
[(id)__o release]; \
})
#endif

#ifndef DEALLOC
/**
 *	DEALLOC calls the superclass implementation of dealloc, unless
 *	ARC is in use (in which case it does nothing).
 */
#define DEALLOC         [super dealloc];
#endif

#ifndef ENTER_POOL
/**
 *	ENTER_POOL creates an autorelease pool and places subsequent code
 *	in a block.<br />
 *	The block must be terminated with a corresponding LEAVE_POOL.<br />
 *	You should not break, continue, or return from such a block of code
 *	(to do so could leak an autorelease pool and give objects a longer
 *	lifetime than they ought to have.  If you wish to leave the block of
 *	code early, you should ensure that doing so causes the autorelease
 *	pool outside the block to be released promptly (since that will
 *	implicitly release the pool created at the start of the block too).
 */
#define ENTER_POOL      {NSAutoreleasePool *_lARP=[NSAutoreleasePool new];
#endif

#ifndef LEAVE_POOL
/**
 *	LEAVE_POOL terminates a block of code started with ENTER_POOL.
 */
#define LEAVE_POOL      [_lARP drain];}
#endif


#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef NS_CONSUMED
#if __has_feature(attribute_ns_consumed)
#define NS_CONSUMED __attribute__((ns_consumed))
#else
#define NS_CONSUMED
#endif
#endif



#endif
