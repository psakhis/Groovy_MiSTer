#include <retroarch.h>
#include <verbosity.h>
#include <gfx/gfx_mister.h>
#include <gfx/video_frame.h>
#include <gfx/common/gl2_common.h>
#include <gfx/common/gl3_defines.h>
#include <gfx/common/vulkan_common.h>
#include <audio/audio_driver.h>
#include <mister/groovymister_wrapper.h>
#ifdef HAVE_MENU
#include <menu/menu_driver.h>
#endif

#define MAX_BUFFER_WIDTH 720 //1024
#define MAX_BUFFER_HEIGHT 576 //768

#define RGB888  0
#define RGBA888 1
#define RGB565  2

typedef struct mister_video_info
{
   bool is_connected;
   uint32_t frame;
   uint8_t  field;
   uint16_t width;
   uint16_t height;
   double vfreq;
   uint8_t interlaced;
   uint32_t line_time; //usec
   uint32_t frame_time; //usec
   uint8_t rgb_mode;
} mister_video_t;

union
{
   const uint8_t *u8;
   const uint16_t *u16;
   const uint32_t *u32;
} u;


static void mister_init(const char* mister_host, uint8_t compression, uint32_t sound_rate, uint8_t sound_channels, uint8_t pix_fmt);
static void mister_switchres(sr_mode *srm);
static void mister_resize_viewport(video_driver_state_t *video_st, unsigned width, unsigned height);

static mister_video_t mister_video;
static sr_mode mister_mode;
static gmw_fpgaStatus status;
static char *menu_buffer = 0;
static unsigned menu_width = 0;
static unsigned menu_height = 0;
static bool modeline_active = 0;
static bool must_clear_buffer = 0;
static bool mode_switch_pending = 0;
static bool vp_resize_pending = 0;
static bool prev_menu_state = 0;
static struct scaler_ctx *scaler;
static uint8_t *mister_buffer = 0;
static uint8_t *audio_buffer = 0;
static uint8_t *convert_buffer = 0;
static uint8_t *scaled_buffer = 0;
static uint8_t *hardware_buffer = 0;


bool mister_is_connected()
{
   return mister_video.is_connected;
}

void mister_set_menu_buffer(char *frame, unsigned width, unsigned height)
{
   menu_buffer = frame;
   menu_width = width;
   menu_height = height;
}

void mister_draw(video_driver_state_t *video_st, const void *data, unsigned width, unsigned height, size_t pitch)
{
   settings_t *settings  = config_get_ptr();
   audio_driver_state_t *audio_st  = audio_state_get_ptr();
   uint8_t field = 0;
   uint8_t format = 0;
   bool menu_on = false;
   bool stretched = false;
   bool is_hw_rendered = (data == RETRO_HW_FRAME_BUFFER_VALID
                           && video_st->frame_cache_data == RETRO_HW_FRAME_BUFFER_VALID);

   // Initialize MiSTer if required
   if (!mister_video.is_connected)
      mister_init(settings->arrays.mister_ip, settings->uints.mister_lz4, settings->uints.audio_output_sample_rate, 2, video_st->pix_fmt);

   // Send audio first
   if (audio_st->output_mister && audio_st->output_mister_samples)
      mister_audio();

   // Check if we need to mode switch
   if (mode_switch_pending)
   {
      mister_switchres(&mister_mode);

      //video_driver_set_size(mister_mode.width, mister_mode.height);
      vp_resize_pending = true;
      must_clear_buffer = true;
   }

   if (!modeline_active)
      return;

   // Get pixel format
   if (video_st->pix_fmt == RETRO_PIXEL_FORMAT_XRGB8888)
      format = SCALER_FMT_ARGB8888;

   else if (video_st->pix_fmt == RETRO_PIXEL_FORMAT_RGB565)
      format = SCALER_FMT_RGB565;

   else
      // Unsupported pixel format
      return;

   // Get menu bitmap dimensions
   #ifdef HAVE_MENU
   if (menu_state_get_ptr()->flags & MENU_ST_FLAG_ALIVE && menu_buffer != 0)
   {
      menu_on = true;
      width = menu_width;
      height = menu_height;
      pitch = width * sizeof(uint16_t);
      format = SCALER_FMT_RGBA4444;
      data = menu_buffer;
   }
   else
      menu_buffer = 0;

   if (prev_menu_state != menu_on)
   {
      prev_menu_state = menu_on;
      must_clear_buffer = true;
   }
   #endif

   // Ignore bogus frames
   if (data == 0 || width <= 64 || height <= 64)
      return;

   if (vp_resize_pending)
   {
      mister_resize_viewport(video_st, width, height);
      vp_resize_pending = false;
   }

   // Get RGB buffer if hw rendered
   if (is_hw_rendered)
   {
      if (video_st->current_video->read_viewport
            && video_st->current_video->read_viewport(video_st->data, hardware_buffer, false))
         pitch = mister_video.width * 3;

      else return;

      format = SCALER_FMT_BGR24;
      data = hardware_buffer;
   }

   if (pitch == 0)
      return;

   // Scale frame
   double x_scale, y_scale;
   if (menu_on)
   {
      x_scale = (double)mister_mode.width / (double)width;
      y_scale = (double)mister_mode.height / (double)height;
      stretched = x_scale != floor(x_scale) || y_scale != floor(y_scale);
   }
   else
   {
      x_scale = (retroarch_get_rotation() & 1) ? mister_mode.y_scale : mister_mode.x_scale;
      y_scale = (retroarch_get_rotation() & 1) ? mister_mode.x_scale : mister_mode.y_scale;
      stretched = mister_mode.is_stretched;
   }

   if (is_hw_rendered)
   {
      width *= x_scale;
      height *= y_scale;
   }
   else if (x_scale != 1.0 || y_scale != 1.0)
   {
      uint32_t scaler_width  = round(width * x_scale);
      uint32_t scaler_height = round(height * y_scale);
      uint32_t scaler_pitch  = scaler_width * sizeof(uint32_t);

      if (  width  != (uint32_t)scaler->in_width
         || height != (uint32_t)scaler->in_height
         || format != scaler->in_fmt
         || pitch  != (uint32_t)scaler->in_stride
         || scaler_width  != (uint32_t)scaler->out_width
         || scaler_height != (uint32_t)scaler->out_height)
      {
         scaler->scaler_type = stretched ? SCALER_TYPE_BILINEAR : SCALER_TYPE_POINT;
         scaler->in_fmt    = format;
         scaler->in_width  = width;
         scaler->in_height = height;
         scaler->in_stride = pitch;

         scaler->out_width  = scaler_width;
         scaler->out_height = scaler_height;
         scaler->out_stride = scaler_pitch;

         scaler_ctx_gen_filter(scaler);
      }

      scaler_ctx_scale_direct(scaler, scaled_buffer, data);

      width  = scaler->out_width;
      height = scaler->out_height;
      pitch  = scaler->out_stride;
      format = scaler->out_fmt;
      data = scaled_buffer;
   }

   // Clear frame buffer if required
   if (must_clear_buffer)
   {
      must_clear_buffer = false;
      memset(mister_buffer, 0, MAX_BUFFER_WIDTH * MAX_BUFFER_HEIGHT * 3);
      memset(convert_buffer, 0, MAX_BUFFER_WIDTH * MAX_BUFFER_HEIGHT * 4);
   }

   // Compute borders and clipping
   uint32_t rotation = retroarch_get_rotation();
   uint32_t rot_width = (rotation & 1) && !menu_on ? height : width;
   uint32_t rot_height = (rotation & 1) && !menu_on ?  width : height;

   uint32_t x_start = mister_video.width > rot_width ? (mister_video.width - rot_width) / 2 : 0;
   uint32_t x_crop = mister_video.width < rot_width ? rot_width - mister_video.width : 0;
   uint32_t x_max = rot_width - x_crop;
   uint32_t y_start = mister_video.height > rot_height ? (mister_video.height - rot_height) / 2 : 0;
   uint32_t y_crop = mister_video.height < rot_height ? (rot_height - mister_video.height) : 0;
   uint32_t y_max = rot_height - y_crop;

   if (mister_video.interlaced)
   {
      y_start /= 2;
      y_crop /= 2;

      if (!(rotation & 1) || menu_on)
         y_max /= 2;
   }

   if ((rotation & 1) && !menu_on)
   {
      uint32_t tmp;
      tmp = x_max;
      x_max = y_max;
      y_max = tmp;
   }

   // Get first pixel address from our RGB source
   if (mister_video.interlaced)
   {
      mister_video.field = !status.vgaF1 ^ ((mister_video.frame - status.frame) % 2);
      field = mister_video.field;
   }
   u.u8 = data;
   u.u8 += (field + (y_crop / 2)) * pitch + (x_crop / 2);

   // Get target frame buffer
   uint8_t *fb = mister_video.rgb_mode == RGB565 && format != SCALER_FMT_RGB565 ? convert_buffer : mister_buffer;

   // Compute steps to walk through the source & target bitmaps
   uint32_t pix_size = (mister_video.rgb_mode == RGB565 && format == SCALER_FMT_RGB565) ? 2 : 3;
   uint32_t c = 0;
   int c_step = pix_size;
   int s_step = 1;
   int r_step = 1;

   bool scanlines = settings->bools.mister_scanlines && y_scale >= 2.0;

   if (menu_on || is_hw_rendered)
      r_step = mister_video.interlaced ? 2 : 1;

   else switch (rotation)
   {
      case ORIENTATION_NORMAL:
      case ORIENTATION_FLIPPED:
         c_step = pix_size;
         r_step = mister_video.interlaced ? 2 : 1;
         break;

      case ORIENTATION_VERTICAL:
         c_step = -mister_video.width * pix_size;
         s_step = mister_video.interlaced ? 2 : 1;
         break;

      case ORIENTATION_FLIPPED_ROTATED:
         c_step = +mister_video.width * pix_size;
         s_step = mister_video.interlaced ? 2 : 1;
         break;
   }

   // Copy RGB buffer as BGR24
   for (uint32_t j = 0; j < y_max - 1; j++)
   {
      if (is_hw_rendered)
         c = (mister_video.width * (mister_video.height / r_step - y_start - field - j) + x_start) * pix_size;

      else if (menu_on || !(rotation & 1))
         c = ((j + y_start) * mister_video.width + x_start) * pix_size;

      else if (rotation == ORIENTATION_VERTICAL)
         c = (mister_video.width * (mister_video.height / s_step - y_start - 1) + j + x_start) * pix_size;

      else if (rotation == ORIENTATION_FLIPPED_ROTATED)
         c = (mister_video.width * (y_start + 1) - j - x_start - 1) * pix_size;

      for (uint32_t i = 0; i < x_max - 1; i += s_step)
      {
         if (scanlines && (j % 2))
         {
            fb[c + 0] = 0; //b
            fb[c + 1] = 0; //g
            fb[c + 2] = 0; //r
         }
         else if (format == SCALER_FMT_RGBA4444)
         {
            uint16_t pixel = u.u16[i];
            fb[c + 0] = (pixel >>  8); //b
            fb[c + 1] = (pixel >>  4); //g
            fb[c + 2] = (pixel >>  0); //r
         }
         else if (format == SCALER_FMT_BGR24)
         {
            uint32_t pixel = i * pix_size;
            fb[c + 0] = u.u8[pixel + 0]; //b
            fb[c + 1] = u.u8[pixel + 1]; //g
            fb[c + 2] = u.u8[pixel + 2]; //r
         }
         else if (format == SCALER_FMT_RGB565)
         {
            uint16_t pixel = u.u16[i];
            if (mister_video.rgb_mode == RGB565)
            {
               uint16_t *target = (uint16_t *)&fb[c];
               *target = pixel;
            }
            else
            {
               uint8_t r  = (pixel >> 11) & 0x1f;
               uint8_t g  = (pixel >>  5) & 0x3f;
               uint8_t b  = (pixel >>  0) & 0x1f;
               fb[c + 0] = (b << 3) | (b >> 2); //b
               fb[c + 1] = (g << 2) | (g >> 4); //g
               fb[c + 2] = (r << 3) | (r >> 2); //r
            }
         }
         else if (format == SCALER_FMT_ARGB8888)
         {
            uint32_t pixel = u.u32[i];
            fb[c + 0] = (pixel >>  0) & 0xff; //b
            fb[c + 1] = (pixel >>  8) & 0xff; //g
            fb[c + 2] = (pixel >> 16) & 0xff; //r
         }

         c += c_step;
      }

      u.u8 += pitch * r_step;
   }

   // Convert to RGB565 if required
   if (mister_video.rgb_mode == RGB565 && format != SCALER_FMT_RGB565)
      conv_bgr24_rgb565(mister_buffer, fb, mister_video.width, mister_video.height, mister_video.width, mister_video.width * 3);

   // Compute sync scanline based on frame delay
   int mister_vsync = 1;
   if (settings->bools.video_frame_delay_auto && video_st->frame_delay_effective > 0)
      mister_vsync = height / (16 / video_st->frame_delay_effective);

   else if (settings->uints.video_frame_delay > 0)
      mister_vsync = height / (16 / settings->uints.video_frame_delay);

   mister_video.frame++;

   // Resync if required
   gmw_getStatus(&status);

   if (status.frame > mister_video.frame)
      mister_video.frame = status.frame + 1;

   // Blit to MiSTer
   gmw_blit(mister_video.frame, mister_vsync, 0);
}


static void mister_init(const char* mister_host, uint8_t compression, uint32_t sound_rate, uint8_t sound_channels, uint8_t pix_fmt)
{
   settings_t *settings  = config_get_ptr();
   mister_video.frame = 0;
   mister_video.width = 0;
   mister_video.height = 0;
   mister_video.line_time = 0;
   mister_video.frame_time = 0;
   mister_video.interlaced = 0;
   mister_video.rgb_mode = (pix_fmt == RETRO_PIXEL_FORMAT_RGB565 || settings->bools.mister_force_rgb565) ? RGB565 : RGB888;

   RARCH_LOG("[MiSTer] Sending CMD_INIT... lz4 %d sound_rate %d sound_chan %d rgb_mode %d mtu %d\n", compression, sound_rate, sound_channels, mister_video.rgb_mode, settings->uints.mister_mtu);
   gmw_init(mister_host, compression, sound_rate, sound_channels, mister_video.rgb_mode, settings->uints.mister_mtu);

   mister_video.is_connected = true;

   // Allocate buffers
   mister_buffer = (uint8_t*)gmw_get_pBufferBlit();
   audio_buffer = (uint8_t*)gmw_get_pBufferAudio();
   convert_buffer = (uint8_t*)malloc(MAX_BUFFER_WIDTH * MAX_BUFFER_HEIGHT * 4);
   scaled_buffer = (uint8_t*)malloc(MAX_BUFFER_WIDTH * MAX_BUFFER_HEIGHT * 4);
   hardware_buffer = (uint8_t*)malloc(MAX_BUFFER_WIDTH * MAX_BUFFER_HEIGHT * 4);

   // Create scaler
   scaler = (struct scaler_ctx*)calloc(1, sizeof(*scaler));

   // Get status to gather info from server
   gmw_getStatus(&status);
}


void mister_audio(void)
{
   audio_driver_state_t *audio_st  = audio_state_get_ptr();

   uint16_t audio_bytes = audio_st->output_mister_samples * 2;
   memcpy(audio_buffer, audio_st->output_mister_samples_conv_buf, audio_bytes);
   audio_st->output_mister_samples = 0;

   if (status.audio)
      gmw_audio(audio_bytes);
}

void mister_sync(void)
{
   if (!mister_video.is_connected)
      return;

   gmw_waitSync();
}

int mister_diff_time_raster(void)
{
   if (!mister_video.is_connected)
      return 0;

   return gmw_diffTimeRaster();
}

void mister_close(void)
{
   if (!mister_video.is_connected)
      return;

   RARCH_LOG("[MiSTer] Sending CMD_CLOSE...\n");

   gmw_close();

   mister_video.is_connected = 0;
   modeline_active = 0;

   free(convert_buffer);
   free(scaled_buffer);
   free(hardware_buffer);
   mister_buffer = 0;
   audio_buffer = 0;
   scaled_buffer = 0;
   hardware_buffer = 0;

   scaler_ctx_gen_reset(scaler);
   free(scaler);
   scaler = 0;
}


void mister_set_mode(sr_mode *srm)
{
   // Filter out too small modes (hack: these shouldn't reach here)
   if (srm->width < 200 || srm->height < 160)
      return;

   // Check if mode is the same as previous
   //if (memcmp(&mister_mode, srm, sizeof(sr_mode)) == 0)
   //   return;

   // otherwise store it
   memcpy(&mister_mode, srm, sizeof(sr_mode));

   // Signal mode switch pending
   mode_switch_pending = 1;
}

static void mister_switchres(sr_mode *srm)
{
   settings_t *settings  = config_get_ptr();

   if (srm == 0)
      return;

   RARCH_LOG("[MiSTer] Video_SetSwitchres - (result %dx%d@%f) - x=%.4f y=%.4f stretched(%d)\n", srm->width, srm->height,srm->vfreq, srm->x_scale, srm->y_scale, srm->is_stretched);
   RARCH_LOG("[MiSTer] Sending CMD_SWITCHRES...\n");

   gmw_switchres((double)srm->pclock / 1000000.0, srm->width, srm->hbegin, srm->hend, srm->htotal, srm->height, srm->vbegin, srm->vend, srm->vtotal, srm->interlace ? (settings->bools.mister_interlaced_fb ? 1 : 2) : 0);

   mister_video.width = srm->width;
   mister_video.height = srm->height;
   mister_video.vfreq = srm->refresh;
   mister_video.interlaced = settings->bools.mister_interlaced_fb ? srm->interlace : 0;

   double px = (double) srm->pclock / 1000000.0;
   mister_video.line_time = round((double) srm->htotal * (1 / px)); //in usec, time to raster 1 line
   mister_video.frame_time = mister_video.line_time * srm->vtotal;

   if (srm->interlace)
   {
      mister_video.field = 0;
      mister_video.frame_time = mister_video.frame_time >> 1;
   }

   modeline_active = 1;
   mode_switch_pending = 0;
}


static void mister_resize_viewport(video_driver_state_t *video_st, unsigned width, unsigned height)
{
   double x_scale, y_scale;
   x_scale = (retroarch_get_rotation() & 1) ? mister_mode.y_scale : mister_mode.x_scale;
   y_scale = (retroarch_get_rotation() & 1) ? mister_mode.x_scale : mister_mode.y_scale;

   if (string_is_equal(video_driver_get_ident(), "gl"))
   {
      gl2_t *gl = (gl2_t*)video_st->data;
      gl->video_width = width;
      gl->video_height = height;
      gl->vp.width = width;
      gl->vp.height = height;
      gl->pbo_readback_scaler.out_width = width * x_scale;
      gl->pbo_readback_scaler.out_height = height * y_scale;
      gl->pbo_readback_scaler.in_width = width;
      gl->pbo_readback_scaler.in_height = height;
      gl->pbo_readback_scaler.in_stride = width * sizeof(uint32_t);
      gl->pbo_readback_scaler.out_stride = width * 3;
   }
   else if (string_is_equal(video_driver_get_ident(), "glcore"))
   {
      gl3_t *gl = (gl3_t*)video_st->data;
      gl->video_width = width;
      gl->video_height = height;
      gl->vp.width = width;
      gl->vp.height = height;
      gl->pbo_readback_scaler.out_width = width * x_scale;
      gl->pbo_readback_scaler.out_height = height * y_scale;
      gl->pbo_readback_scaler.in_width = width;
      gl->pbo_readback_scaler.in_height = height;
      gl->pbo_readback_scaler.in_stride = width * sizeof(uint32_t);
      gl->pbo_readback_scaler.out_stride = width * 3;
   }
   else if (string_is_equal(video_driver_get_ident(), "vulkan"))
   {
      vk_t *vk = (vk_t*)video_st->data;
      vk->video_width = width;
      vk->video_height = height;
      vk->vp.width = width;
      vk->vp.height = height;
      vk->readback.scaler_bgr.in_width    = width;
      vk->readback.scaler_bgr.in_height   = height;
      vk->readback.scaler_bgr.out_width   = width * x_scale;
      vk->readback.scaler_bgr.out_height  = height * y_scale;
      vk->readback.scaler_bgr.in_stride   = width * sizeof(uint32_t);
      vk->readback.scaler_bgr.out_stride  = width * 3;
      vk->readback.scaler_bgr.in_fmt      = SCALER_FMT_ABGR8888;
      vk->readback.scaler_bgr.out_fmt     = SCALER_FMT_BGR24;
      vk->readback.scaler_bgr.scaler_type = SCALER_TYPE_POINT;

      vk->readback.scaler_rgb.in_width    = width;
      vk->readback.scaler_rgb.in_height   = height;
      vk->readback.scaler_rgb.out_width   = width * x_scale;
      vk->readback.scaler_rgb.out_height  = height * y_scale;
      vk->readback.scaler_rgb.in_stride   = width * sizeof(uint32_t);
      vk->readback.scaler_rgb.out_stride  = width * 3;
      vk->readback.scaler_rgb.in_fmt      = SCALER_FMT_ARGB8888;
      vk->readback.scaler_rgb.out_fmt     = SCALER_FMT_BGR24;
      vk->readback.scaler_rgb.scaler_type = SCALER_TYPE_POINT;
   }
}
