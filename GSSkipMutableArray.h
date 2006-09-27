/**
   Copyright (C) 2006 Free Software Foundation, Inc.

   Written by:  Matt Rice <ratmice@yahoo.com>
   Date:        2006

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
   */
#include <Foundation/NSArray.h>
#include <GSIndexedSkipList.h>

/** 
  <p>A NSMutableArray subclass which uses a skip list variant for it's underlying
  data structure.</p>
  
  <p>while a skip list is typically sorted and represents a dictionary.
  the indexed skip list is sorted by index and maintains deltas to represent
  the distance between linked nodes.</p>

  <p><code>the underlying data structure looks much like the figure below:<br/>
index ->  HEAD   1    2    3    4    5    6    TAIL<br/>
           5| ---------------------> # ------>  #<br/>
           3| -----------> 2 ------> # ------>  #<br/>
           1| -> 1 -> 1 -> 1 -> 1 -> 1 -> # ->  #<br/></code></p>
  
  <p>where the numbers represent how many indexes it is to the next node
  of the appropriate level. The bottom level always points to the next node.</p>

  <p>finding a specific index starts at the top level, until the current 
  depth + the next nodes delta is larger than wanted index, then it goes down
  1 level, and repeats until it finds the wanted index.</p>
 
  <p>addition and removal of indexes requires an update of the deltas of nodes
  which begin before, and end after the wanted index,
  these are the places where it goes down a level.</p>
 
  <p>the rationale behind it was where a linked list based mutable array will
  quickly add and remove elements, it may perform poorly at accessing any
  random index (because it must traverse the entire list to get to the index).</p>

  <p>and while a c array based mutable array will perform good at random index
  access it may perform poorly at adding and removing indexes
  (because it must move all items after the altered index).</p>

  <p>so while a SkipMutableArray may not outperform a linked list or a c array
  mutable array at their specific strengths, it attempts to not suffer from
  either of their weaknesses, at the cost of additional memory overhead..</p>
 */
@interface SkipMutableArray : NSMutableArray
{
    GSISList l;
}

@end

