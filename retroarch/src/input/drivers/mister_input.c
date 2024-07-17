/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *  Copyright (C) 2014-2015 - Higor Euripedes
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
#include <stdlib.h>

#include <boolean.h>
#include <string/stdstring.h>
#include <libretro.h>

#include <mister/groovymister_wrapper.h>

#include "../input_keymaps.h"

#include "../../configuration.h"
#include "../../retroarch.h"
#include "../../verbosity.h"
#include "../../tasks/tasks_internal.h"

typedef struct mister_input
{
   uint8_t keys_mister[32]; 
   uint8_t mouse_mister; 
   uint32_t frame_mister; 
   int mouse_x;
   int mouse_y;
   int mouse_abs_x;
   int mouse_abs_y;
   int mouse_l;
   int mouse_r;
   int mouse_m; 
} mister_input_t;


static void *mister_input_init(const char *joypad_driver)
{ 		
   mister_input_t *mister = (mister_input_t*)calloc(1, sizeof(mister_input_t));
   if (!mister || !config_get_ptr()->bools.video_mister_enable)
      return NULL;	       
   
   gmw_bindInputs(config_get_ptr()->arrays.mister_ip);
   input_keymaps_init_keyboard_lut(rarch_key_map_mister);   	  
     
   return mister;
}

static bool mister_key_pressed(void *data, int key)
{
   mister_input_t *mister = (mister_input_t*)data;	
   unsigned sym = rarch_keysym_lut[(enum retro_key)key];
   int pressed = 1 & (mister->keys_mister[sym / 8] >> (sym % 8));     
   
   return pressed;    	
}

static int16_t mister_input_state(
      void *data,
      const input_device_driver_t *joypad,
      const input_device_driver_t *sec_joypad,
      rarch_joypad_info_t *joypad_info,
      const retro_keybind_set *binds,
      bool keyboard_mapping_blocked,
      unsigned port,
      unsigned device,
      unsigned idx,
      unsigned id)
{
	
   int16_t      ret = 0;  
   mister_input_t *mister = (mister_input_t*)data;
   
   switch (device)
   {
      case RETRO_DEVICE_JOYPAD:        
         if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
         {
            unsigned i;

            for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
            {
               if (binds[port][i].valid)                 
                  if (mister_key_pressed(mister, binds[port][i].key)) 
                     ret |= (1 << i);
            }

            return ret;
         }

         if (id < RARCH_BIND_LIST_END)
         {
            if (binds[port][id].valid)            
              if (mister_key_pressed(mister, binds[port][id].key))
                  return 1;
         }
         break;
      case RETRO_DEVICE_ANALOG:
         {
            int id_minus_key      = 0;
            int id_plus_key       = 0;
            unsigned id_minus     = 0;
            unsigned id_plus      = 0;
            bool id_plus_valid    = false;
            bool id_minus_valid   = false;

            input_conv_analog_id_to_bind_id(idx, id, id_minus, id_plus);

            id_minus_valid        = binds[port][id_minus].valid;
            id_plus_valid         = binds[port][id_plus].valid;
            id_minus_key          = binds[port][id_minus].key;
            id_plus_key           = binds[port][id_plus].key;

            if (id_plus_valid && id_plus_key < RETROK_LAST)
            {
               if (mister_key_pressed(mister, id_plus_key))
                  ret = 0x7fff;
            }
            if (id_minus_valid && id_minus_key < RETROK_LAST)
            {
               if (mister_key_pressed(mister, id_minus_key))
                  ret += -0x7fff;
            }
         }
	 return ret;
      case RETRO_DEVICE_MOUSE:
      case RARCH_DEVICE_MOUSE_SCREEN:
         if (config_get_ptr()->uints.input_mouse_index[ port ] == 0)
         {
            switch (id)
            {
               case RETRO_DEVICE_ID_MOUSE_LEFT:
                  return mister->mouse_l;
               case RETRO_DEVICE_ID_MOUSE_RIGHT:
                  return mister->mouse_r;
               case RETRO_DEVICE_ID_MOUSE_WHEELUP:
                  return 0;
               case RETRO_DEVICE_ID_MOUSE_WHEELDOWN:
                  return 0;
               case RETRO_DEVICE_ID_MOUSE_X:
                  return mister->mouse_x;
               case RETRO_DEVICE_ID_MOUSE_Y:
                  return mister->mouse_y;
               case RETRO_DEVICE_ID_MOUSE_MIDDLE:
                  return mister->mouse_m;
               case RETRO_DEVICE_ID_MOUSE_BUTTON_4:
                  return 0;
               case RETRO_DEVICE_ID_MOUSE_BUTTON_5:
                  return 0;
            }
         }
         break;
      case RETRO_DEVICE_POINTER:
      case RARCH_DEVICE_POINTER_SCREEN:
         if (idx == 0)
         {
            struct video_viewport vp;
            bool screen                 = device == 
               RARCH_DEVICE_POINTER_SCREEN;
            const int edge_detect       = 32700;
            bool inside                 = false;
            int16_t res_x               = 0;
            int16_t res_y               = 0;
            int16_t res_screen_x        = 0;
            int16_t res_screen_y        = 0;

            vp.x                        = 0;
            vp.y                        = 0;
            vp.width                    = 0;
            vp.height                   = 0;
            vp.full_width               = 0;
            vp.full_height              = 0;

            if (video_driver_translate_coord_viewport_wrap(
                        &vp, mister->mouse_abs_x, mister->mouse_abs_y,
                        &res_x, &res_y, &res_screen_x, &res_screen_y))
            {
               if (screen)
               {
                  res_x = res_screen_x;
                  res_y = res_screen_y;
               }

               inside =    (res_x >= -edge_detect) 
                  && (res_y >= -edge_detect)
                  && (res_x <= edge_detect)
                  && (res_y <= edge_detect);

               switch (id)
               {
                  case RETRO_DEVICE_ID_POINTER_X:
                     return res_x;
                  case RETRO_DEVICE_ID_POINTER_Y:
                     return res_y;
                  case RETRO_DEVICE_ID_POINTER_PRESSED:
                     return mister->mouse_l;
                  case RETRO_DEVICE_ID_LIGHTGUN_IS_OFFSCREEN:
                     return !inside;
               }
            }
         }
         break;
      case RETRO_DEVICE_KEYBOARD:                	                 
        return (id < RETROK_LAST) && mister_key_pressed(mister, id);                                                          
      case RETRO_DEVICE_LIGHTGUN:
         switch (id)
         {
            case RETRO_DEVICE_ID_LIGHTGUN_X:
               return mister->mouse_x;
            case RETRO_DEVICE_ID_LIGHTGUN_Y:
               return mister->mouse_y;
            case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER:
               return mister->mouse_l;
            case RETRO_DEVICE_ID_LIGHTGUN_CURSOR:
               return mister->mouse_m;
            case RETRO_DEVICE_ID_LIGHTGUN_TURBO:
               return mister->mouse_r;
            case RETRO_DEVICE_ID_LIGHTGUN_START:
               return mister->mouse_m && mister->mouse_r;
            case RETRO_DEVICE_ID_LIGHTGUN_PAUSE:
               return mister->mouse_m && mister->mouse_l;
         }
         break;
   }

   return 0;
}

static void mister_input_free(void *data)
{
   if (!data)
      return;
      
   free(data);
}


static void mister_input_poll(void *data)
{	
   if (config_get_ptr()->bools.video_mister_enable)
   {		
	   gmw_pollInputs();
	   gmw_fpgaPS2Inputs ps2Inputs; 	
	   gmw_getPS2Inputs(&ps2Inputs); 	
	   
	   mister_input_t *mister = (mister_input_t*)data;
	   
	   for (int i=0; i<256; i++)
	   {
		int bit_pos = 1 & (ps2Inputs.ps2Keys[i / 8] >> (i % 8));		
		int bit_pre = 1 & (mister->keys_mister[i / 8] >> (i % 8));
		if (bit_pre != bit_pos) 
		{			
			uint16_t mod  = 0;	
	         	unsigned code = input_keymaps_translate_keysym_to_rk(i);	         	
	         	input_keyboard_event(!bit_pos, code, code, mod, RETRO_DEVICE_KEYBOARD);  //bit_pos is keyup       		
		}	
	   }		
	   memcpy(&mister->keys_mister, &ps2Inputs.ps2Keys, sizeof(mister->keys_mister));    
	   
	   if ((ps2Inputs.ps2Mouse & (1 << 0)) && !(mister->mouse_mister & (1 << 0)))
	      mister->mouse_l = 1;
	
	   if ((ps2Inputs.ps2Mouse & (1 << 1)) && !(mister->mouse_mister & (1 << 1)))   
	      mister->mouse_r = 1;
	   
	   if ((ps2Inputs.ps2Mouse & (1 << 2)) && !(mister->mouse_mister & (1 << 2)))   
	      mister->mouse_m = 1;
	   
	   if (!(ps2Inputs.ps2Mouse & (1 << 0)) && (mister->mouse_mister & (1 << 0)))
	      mister->mouse_l = 0;   
	   
	   if (!(ps2Inputs.ps2Mouse & (1 << 1)) && (mister->mouse_mister & (1 << 1)))   
	      mister->mouse_r = 0;   
	   
	   if (!(ps2Inputs.ps2Mouse & (1 << 2)) && (mister->mouse_mister & (1 << 2)))
	      mister->mouse_m = 0;
	      
	   mister->mouse_mister = ps2Inputs.ps2Mouse;   
	 
	   if (mister->frame_mister != ps2Inputs.ps2Frame)
	   {   	
		if (ps2Inputs.ps2Mouse & (1 << 4))
		{						
			mister->mouse_x += -255 + ps2Inputs.ps2MouseX;
			mister->mouse_abs_x += -255 + ps2Inputs.ps2MouseX;
		}			
		else
		{
			mister->mouse_x += ps2Inputs.ps2MouseX;
			mister->mouse_abs_x += ps2Inputs.ps2MouseX;
		}
		if (ps2Inputs.ps2Mouse & (1 << 5))
		{		
			mister->mouse_y -= -255 + ps2Inputs.ps2MouseY;			
			mister->mouse_abs_y -= -255 + ps2Inputs.ps2MouseY;
		}	
		else
		{		
			mister->mouse_y -= ps2Inputs.ps2MouseY;
			mister->mouse_abs_y -= ps2Inputs.ps2MouseY;
		}	
		mister->frame_mister = ps2Inputs.ps2Frame;
	    }
	    else  
	    {
	    	mister->mouse_x = 0;
	    	mister->mouse_y = 0;
	    	mister->mouse_abs_x = 0;
	    	mister->mouse_abs_y = 0;
	    }
    }              
}

static uint64_t mister_get_capabilities(void *data)
{ 
   return
           (1 << RETRO_DEVICE_JOYPAD)
         | (1 << RETRO_DEVICE_MOUSE)
         | (1 << RETRO_DEVICE_KEYBOARD)
         | (1 << RETRO_DEVICE_LIGHTGUN)
         | (1 << RETRO_DEVICE_POINTER)
         | (1 << RETRO_DEVICE_ANALOG);                
}

input_driver_t input_mister = {
   mister_input_init,
   mister_input_poll,
   mister_input_state,
   mister_input_free,
   NULL,
   NULL,
   mister_get_capabilities,
   "mister",
   NULL,                   /* grab_mouse */
   NULL,
   NULL
};


