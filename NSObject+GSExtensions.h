/** Declaration of extension methods for base additions

   Copyright (C) 2003-2010 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   and:         Adam Fedor <fedor@gnu.org>

   This file is part of the GNUstep Base Library.

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
   Boston, MA 02111 USA.

*/

#import <Foundation/NSObject.h>

@interface      NSObject(MemoryFootprint)
/* This method returns the memory usage of the receiver, excluding any
 * objects already present in the exclude table.<br />
 * The argument is a hash table configured to hold non-retained pointer
 * objects and is used to inform the receiver that its size should not
 * be counted again if it's already in the table.<br />
 * The NSObject implementation returns zero if the receiver is in the
 * table, but otherwise adds itself to the table and returns its memory
 * footprint (the sum of all of its instance variables, but not any
 * memory pointed to by those variables).<br />
 * Subclasses should override this method by calling the superclass
 * implementation, and either return the result (if it was zero) or
 * return that value plus the sizes of any memory owned by the receiver
 * (eg found by calling the same method on objects pointed to by the
 * receiver's instance variables).
 */
- (NSUInteger) sizeInBytesExcluding: (NSHashTable*)exclude;
@end
