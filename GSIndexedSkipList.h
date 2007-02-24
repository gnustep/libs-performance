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

#import <Foundation/NSZone.h>
#define GSISLMaxNumberOfLevels 16
#define GSISLMaxLevel 15

/*
 * attempt at caching the previously looked up index
 * to reduce the search time required when wantedIndex > previousIndex
 * this didn't seem to provide any benefit, actually negatively impacting
 * performance though it was never thoroughly tested it
 */
#define GSISL_CACHE_OPT 0



typedef id GSISLValueType;
typedef struct GSISLNode_t *GSISLNode;
extern GSISLNode GSISLNil;

struct GSISLForward_t
{
  unsigned delta;
  GSISLNode next;
};

struct GSISLNode_t 
{
  GSISLValueType value;
  struct GSISLForward_t forward[1];
};

typedef struct GSIndexedSkipList
{
  int level;        /* Maximum level of the list 
		       (1 more than the number of levels in the list) */
  GSISLNode header; /* pointer to header */
  unsigned count;
  NSZone *zone;
#if GSISL_CACHE_OPT
  unsigned indexCache[GSISLMaxNumberOfLevels];
  GSISLNode nodeCache[GSISLMaxNumberOfLevels];
#endif
} * GSISList;

void GSISLInitialize();
void GSISLFreeList(GSISList l);
GSISList GSISLInitList(NSZone *zone);
void GSISLInsertItemAtIndex(GSISList l,
			GSISLValueType value,
			unsigned index);

GSISLValueType GSISLItemAtIndex(GSISList l, unsigned index);

GSISLValueType GSISLRemoveItemAtIndex(GSISList l,
				      unsigned index);

GSISLValueType GSISLReplaceItemAtIndex(GSISList l,
				       GSISLValueType newVal,
				       unsigned index);

