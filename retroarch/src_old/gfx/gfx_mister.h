#include <switchres/switchres_wrapper.h>

void mister_draw(video_driver_state_t *video_st, const void *data, unsigned width, unsigned height, size_t pitch);
void mister_audio(void);
void mister_sync(void);
int  mister_diff_time_raster(void);
void mister_close(void);
void mister_set_mode(sr_mode *srm);
void mister_set_menu_buffer(char *frame, unsigned width, unsigned height);
bool mister_is_connected();
