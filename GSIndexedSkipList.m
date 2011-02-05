/**
   Copyright (C) 2006 Free Software Foundation, Inc.

   Written by:  Matt Rice <ratmice@yahoo.com>
   Date:        2006

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

#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "GSIndexedSkipList.h"

/* This no longer seems to be needed/correct
#if	defined(__MINGW32__)
#include <cstdlib.h>	// declares rand()
#endif
 */

#define PrettyErr(x) do { fprintf(stderr, "%s:%i: %s\n",__FILE__, __LINE__, x); exit(EXIT_FAILURE); } while (0)

GSISLNode GSISLNil;

GSISLNode GSISLNewNodeOfLevel(int l, NSZone *zone)
{
  GSISLNode ret = (GSISLNode) NSZoneMalloc(zone, sizeof(struct GSISLNode_t)
		  		     + ((l) * sizeof(struct GSISLForward_t)));
  
  if (ret == NULL)
    {
      PrettyErr(strerror(errno)); 
    }
  
  do 
    {
      ret->forward[l].delta = 0;
    } while (--l >= 0);

  return ret;
}

void GSISLInitialize()
{ 
  if (GSISLNil != NULL) return;
  
  GSISLNil = GSISLNewNodeOfLevel(0, NSDefaultMallocZone());
  GSISLNil->forward[0].delta = UINT_MAX;
  GSISLNil->value = nil;
  GSISLNil->forward[0].next = NULL;
}

GSISList GSISLInitList(NSZone *zone)
{
  GSISList l;
  int i;
  
  l = (GSISList)NSZoneMalloc(zone, sizeof(struct GSIndexedSkipList));
  if (l == NULL)
    {
      PrettyErr(strerror(errno));
    }
  l->zone = zone;
  l->level = 0;
  l->count = 0;
  l->header = GSISLNewNodeOfLevel(GSISLMaxNumberOfLevels, l->zone);
  l->header->value = nil;
   
  for (i=0; i < GSISLMaxNumberOfLevels; i++)
    {
      l->header->forward[0].delta = 0;
      l->header->forward[0].next = GSISLNil;
#if GSISL_CACHE_OPT
      l->indexCache[i] = 0;
      l->nodeCache[i] = l->header;
#endif
    }
  return(l);
} 

void GSISLFreeList(GSISList l) 
{
  GSISLNode p,q;
  
  p = l->header;
  do
    {
      q = p->forward[0].next;
      NSZoneFree(l->zone,p);
      p = q;
    } while (p != GSISLNil);
  
  NSZoneFree(l->zone, l);
};

int GSISLRandomLevel()
{
  int level = 0;
  static int p = RAND_MAX / 4;

  while (rand() < p && level < GSISLMaxLevel)
    {
      level++;
    }
  return level;
}

void GSISLInsertItemAtIndex(GSISList l, GSISLValueType value,
 	 	 	    unsigned index) 
{
  int k, i;
  GSISLNode update[GSISLMaxNumberOfLevels];
  unsigned updateIndexes[GSISLMaxNumberOfLevels];
  GSISLNode p,q;
  unsigned depth;
  depth = 0;
  k = l->level;
#if GSISL_CACHE_OPT

  if (l->indexCache[k] < index)
    {
      p = l->nodeCache[k];
      depth = l->indexCache[k];
    }
  else 
    {
      p = l->header;
    }
#else
  p = l->header;
#endif
  do
    {
      while (q = p->forward[k].next,
	q != GSISLNil && depth + p->forward[k].delta < index + 1)
	{
	  depth += p->forward[k].delta;
	  p = q;
	}
      updateIndexes[k] = depth;
      update[k] = p;
    } while(--k >= 0);
    
  k = GSISLRandomLevel();
  q = GSISLNewNodeOfLevel(k, l->zone);
    
  if (k > l->level)
    {
      /*  we are creating a new level that looks like
       *  header ---> new node ---> tail
       */
      k = l->level;
      l->level++;
#if GSISL_CACHE_OPT
      l->nodeCache[l->level] = l->header;
      l->indexCache[l->level] = 0;
#endif
      l->header->forward[l->level].delta = index + 1;
      l->header->forward[l->level].next = q;
      q->forward[l->level].delta = 0;
      q->forward[l->level].next = GSISLNil;
    }
  else
    {
      /* if there are higher nodes than this nodes level.
         increment the deltas in the update, as we are inserting
         a node inbetween their starting point and their ending
       */
      for (i = k + 1; i <= l->level; i++)
        {
          if (update[i]->forward[i].delta != 0)
            update[i]->forward[i].delta++;
#if GSISL_CACHE_OPT
	  l->nodeCache[i] = update[i];
	  l->indexCache[i] = updateIndexes[i];
#endif
        }
    }
  
  q->value = value;
  do
    {
      /* update from the nodes highest level down to level 0
       * on all the levels already existing in the list
       */
      p = update[k];
	
      if (p->forward[k].delta)
        q->forward[k].delta = updateIndexes[k] + p->forward[k].delta - depth;
	
      p->forward[k].delta = depth + 1 - updateIndexes[k];
      q->forward[k].next = p->forward[k].next;
      p->forward[k].next = q;
#if GSISL_CACHE_OPT
      l->indexCache[k] = updateIndexes[k];
      l->nodeCache[k] = update[k];
#endif
    } while(--k >= 0);
  l->count++;
}

GSISLValueType GSISLRemoveItemAtIndex(GSISList l, unsigned index) 
{
  int k,m;
  GSISLNode update[GSISLMaxNumberOfLevels];
  unsigned updateIndexes[GSISLMaxNumberOfLevels];
  GSISLNode p,q;
  unsigned depth = 0;
  GSISLValueType ret;
  
  k = m = l->level;
#if GSISL_CACHE_OPT 
  if (l->indexCache[k] < index)
    {
      p = l->nodeCache[k];
      depth = l->indexCache[k];
    }
  else
    {
      p = l->header;
    }
#else
  p = l->header;
#endif
  do
    {
      while (q = p->forward[k].next,
	q != GSISLNil && depth + p->forward[k].delta < index + 1)
        {
          depth += p->forward[k].delta;
          p = q;
        }
      update[k] = p;
      updateIndexes[k] = depth;
    } while(--k >= 0);
  
  for (k = 0; k <= m; k++)
    {
      p = update[k];
#if GSISL_CACHE_OPT
      l->indexCache[k] = updateIndexes[k];
      l->nodeCache[k] = update[k];
#endif
      if (p->forward[k].next == q)
        {
          p->forward[k].delta
	    = (q->forward[k].next == GSISLNil) ? 0 
	    : p->forward[k].delta + q->forward[k].delta - 1;
	  	
          p->forward[k].next = q->forward[k].next;
        }
      else if (p->forward[k].next != GSISLNil)
        {
          p->forward[k].delta--;
        }
      else
	{
	  p->forward[k].delta = 0;
	} 
    }
  
  ret = q->value; 
  NSZoneFree(l->zone,q); 
  
  /* if header points to nil, decrement the list level */
  while (l->header->forward[m].next == GSISLNil && m > 0 )
    {
      l->header->forward[m].delta = 0;
      m--;
    }
  l->level = m;
  l->count--;
  return ret;
}

GSISLValueType GSISLItemAtIndex(GSISList l, unsigned index)
{
  int k;
  unsigned depth = 0;
  GSISLNode p,q;

  k = l->level;
#if GSISL_CACHE_OPT 
  if (l->indexCache[k] < index)
    {
      p = l->nodeCache[k];
      depth = l->indexCache[k];
    }
  else
    {
      p = l->header;
    }
#else
  p = l->header;
#endif
  
  do
    {
      while (q = p->forward[k].next,
	q != GSISLNil && depth + p->forward[k].delta < index + 1)
        {
          depth += p->forward[k].delta;
          p = q;
        }
#if GSISL_CACHE_OPT
      l->nodeCache[k] = p;
      l->indexCache[k] = depth;
#endif
    } while(--k >= 0);
    
  return(q->value);
}

GSISLValueType
GSISLReplaceItemAtIndex(GSISList l, GSISLValueType newVal, unsigned index)
{
  int k;
  unsigned depth = 0;
  GSISLNode p,q;
  GSISLValueType ret;

  k = l->level;

#if GSISL_CACHE_OPT
  if (l->indexCache[k] < index)
    {
      p = l->nodeCache[k];
      depth = l->indexCache[k];
    }
  else
    {
      p = l->header;
    }
#else
  p = l->header;
#endif
 
  do
    {
      while (q = p->forward[k].next,
	q != GSISLNil && depth + p->forward[k].delta < index + 1)
        {
          depth += p->forward[k].delta;
          p = q;
        }
#if GSISL_CACHE_OPT
      l->indexCache[k] = depth;
      l->nodeCache[k] = p;
#endif
    } while(--k >= 0);
  
  ret = q->value;
  q->value = newVal;
  return ret;
}
