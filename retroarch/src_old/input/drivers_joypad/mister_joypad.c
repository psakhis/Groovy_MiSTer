/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *  Copyright (C) 2014-2017 - Higor Euripedes
 *  Copyright (C)      2023 - Carlo Refice
 *
 *  RetroArch is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Found-
 *  ation, either version 3 of the License, or (at your option) any later version.
 *
 *  RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 *  PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with RetroArch.
 *  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdint.h>

#include <compat/strl.h>

#include <mister/groovymister_wrapper.h>

#include "../input_driver.h"

#include "../../tasks/tasks_internal.h"
#include "../../verbosity.h"

#define MAX_USERS_MISTER 2

typedef struct _mister_joypad
{
   uint16_t map;
   unsigned num_axes;
   unsigned num_buttons;
   unsigned num_hats;
} mister_joypad_t;

/* TODO/FIXME - static globals */
static mister_joypad_t mister_pads[MAX_USERS_MISTER];

static const char *mister_joypad_name(unsigned pad)
{
   if (pad >= MAX_USERS_MISTER)
      return NULL;
   
   return "MiSTer";     
}

static int32_t mister_pad_get_button(mister_joypad_t *pad, uint16_t joykey)
{	 
  switch(joykey)
  {  
      case RETRO_DEVICE_ID_JOYPAD_UP:
         return (int32_t)(pad->map & GMW_JOY_UP);
      case RETRO_DEVICE_ID_JOYPAD_DOWN:
         return (int32_t)(pad->map & GMW_JOY_DOWN);
      case RETRO_DEVICE_ID_JOYPAD_LEFT:
         return (int32_t)(pad->map & GMW_JOY_LEFT);
      case RETRO_DEVICE_ID_JOYPAD_RIGHT:
         return (int32_t)(pad->map & GMW_JOY_RIGHT);  	
      case RETRO_DEVICE_ID_JOYPAD_B:
         return (int32_t)(pad->map & GMW_JOY_B1);
      case RETRO_DEVICE_ID_JOYPAD_A:
         return (int32_t)(pad->map & GMW_JOY_B2);
      case RETRO_DEVICE_ID_JOYPAD_Y:
         return (int32_t)(pad->map & GMW_JOY_B3);   
      case RETRO_DEVICE_ID_JOYPAD_X:         
         return (int32_t)(pad->map & GMW_JOY_B4);   
      case RETRO_DEVICE_ID_JOYPAD_SELECT:
         return (int32_t)(pad->map & GMW_JOY_B5);
      case RETRO_DEVICE_ID_JOYPAD_START:
         return (int32_t)(pad->map & GMW_JOY_B6);
      case RETRO_DEVICE_ID_JOYPAD_L:
         return (int32_t)(pad->map & GMW_JOY_B7);
      case RETRO_DEVICE_ID_JOYPAD_R:
         return (int32_t)(pad->map & GMW_JOY_B8);      
      case RETRO_DEVICE_ID_JOYPAD_L2:
         return (int32_t)(pad->map & GMW_JOY_B9);
      case RETRO_DEVICE_ID_JOYPAD_R2:
         return (int32_t)(pad->map & GMW_JOY_B10);         
  }	
  return 0;
}

static void mister_pad_connect(unsigned id)
{
   mister_joypad_t *pad       = (mister_joypad_t*)&mister_pads[id];  
   int32_t product            = 0x9999;
   int32_t vendor             = 0x9999;

   input_autoconfigure_connect(
         mister_joypad_name(id),
         NULL,       
         mister_joypad.ident,
         id,
         vendor,
         product);

   pad->num_axes    = 0;
   pad->num_buttons = 10;
   pad->num_hats    = 1;   
}

static void mister_pad_disconnect(unsigned id)
{
   input_autoconfigure_disconnect(id, mister_joypad_name(id));
   memset(&mister_pads[id], 0, sizeof(mister_pads[id]));
}

static void mister_joypad_destroy(void)
{
   unsigned i;
   for (i = 0; i < MAX_USERS_MISTER; i++)
      mister_pad_disconnect(i);

   memset(mister_pads, 0, sizeof(mister_pads));
}

static void *mister_joypad_init(void *data)
{
   unsigned i, num_sticks;
   memset(mister_pads, 0, sizeof(mister_pads));
   
   if (config_get_ptr()->bools.video_mister_enable)
   {    
   	gmw_bindInputs(config_get_ptr()->arrays.mister_ip);   		   
   	num_sticks = MAX_USERS_MISTER;   
   	for (i = 0; i < num_sticks; i++)
      	   mister_pad_connect(i);	
   } 
     
   return (void*)-1;  
}

static int32_t mister_joypad_button_state(
      mister_joypad_t *pad,
      unsigned port, uint16_t joykey)
{
   return mister_pad_get_button(pad, joykey);  
}

static int32_t mister_joypad_button(unsigned port, uint16_t joykey)
{
   mister_joypad_t *pad                = (mister_joypad_t*)&mister_pads[port];
   if (!pad || !pad->map)
      return 0;
   if (port >= MAX_USERS_MISTER)
      return 0;
   return mister_joypad_button_state(pad, port, joykey);
}

static int16_t mister_joypad_axis_state(
      mister_joypad_t *pad,
      unsigned port, uint32_t joyaxis)
{
  return 0;
}

static int16_t mister_joypad_axis(unsigned port, uint32_t joyaxis)
{
   mister_joypad_t *pad = (mister_joypad_t*)&mister_pads[port];
   if (!pad || !pad->map)
      return 0;
   return mister_joypad_axis_state(pad, port, joyaxis);
}

static int16_t mister_joypad_state(
      rarch_joypad_info_t *joypad_info,
      const struct retro_keybind *binds,
      unsigned port)
{
   unsigned i;
   int16_t ret                          = 0;
   uint16_t port_idx                    = joypad_info->joy_idx;
   mister_joypad_t *pad                 = (mister_joypad_t*)&mister_pads[port_idx];

   if (!pad || !pad->map)
      return 0;
   if (port_idx >= MAX_USERS_MISTER)
      return 0;

   for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
   {
      /* Auto-binds are per joypad, not per user. */
      const uint64_t joykey  = (binds[i].joykey != NO_BTN)
         ? binds[i].joykey  : joypad_info->auto_binds[i].joykey;
      const uint32_t joyaxis = (binds[i].joyaxis != AXIS_NONE)
         ? binds[i].joyaxis : joypad_info->auto_binds[i].joyaxis;
      if (
               (uint16_t)joykey != NO_BTN 
            && mister_joypad_button_state(pad, port_idx, (uint16_t)joykey)
         )
         ret |= ( 1 << i);
      else if (joyaxis != AXIS_NONE &&
            ((float)abs(mister_joypad_axis_state(pad, port_idx, joyaxis)) 
             / 0x8000) > joypad_info->axis_threshold)
         ret |= (1 << i);
   }

   return ret;
}

static void mister_joypad_poll(void)
{   	 
   gmw_pollInputs(); 
   gmw_fpgaInputs inputs;
   gmw_getInputs(&inputs);
   mister_joypad_t *pad1 = (mister_joypad_t*)&mister_pads[0];
   mister_joypad_t *pad2 = (mister_joypad_t*)&mister_pads[1];
   pad1->map = inputs.joy1;
   pad2->map = inputs.joy2;      
}


static bool mister_joypad_query_pad(unsigned pad)
{
   return pad < MAX_USERS_MISTER;
}

input_device_driver_t mister_joypad = {
   mister_joypad_init,
   mister_joypad_query_pad,
   mister_joypad_destroy,
   mister_joypad_button,
   mister_joypad_state,
   NULL,
   mister_joypad_axis,
   mister_joypad_poll,
   NULL,
   NULL,
   mister_joypad_name,
   "mister"
};
