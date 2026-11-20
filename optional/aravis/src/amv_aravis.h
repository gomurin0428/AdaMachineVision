#ifndef AMV_ARAVIS_H
#define AMV_ARAVIS_H

#include <stddef.h>
#include <stdint.h>

enum {
	AMV_ARAVIS_SUCCESS = 0,
	AMV_ARAVIS_TIMEOUT = 1,
	AMV_ARAVIS_UNSUPPORTED = 2,
	AMV_ARAVIS_BAD_PARAMETER = 3,
	AMV_ARAVIS_ERROR = 4
};

int amv_aravis_open(const char *device_id, void **camera,
		    char *error, size_t error_size);
void amv_aravis_close(void *camera);
int amv_aravis_start(void *camera, char *error, size_t error_size);
int amv_aravis_stop(void *camera, char *error, size_t error_size);
int amv_aravis_is_streaming(void *camera);
int amv_aravis_grab(void *camera, uint64_t timeout_ms,
		    uint32_t *width, uint32_t *height,
		    void **pixels, size_t *pixel_size,
		    char *error, size_t error_size);
void amv_aravis_free_pixels(void *pixels);

int amv_aravis_copy_mono8(const void *source, size_t source_size,
			  uint32_t width, uint32_t height,
			  size_t row_stride, size_t x_padding,
			  size_t y_padding_rows,
			  void *destination, size_t destination_size,
			  size_t *copied_size,
			  char *error, size_t error_size);

#ifdef AMV_ARAVIS_TESTING
void amv_aravis_test_reset_stop_attempts(void);
void amv_aravis_test_fail_next_stop(void);
unsigned int amv_aravis_test_stop_attempts(void);
int amv_aravis_test_selector_policy(void);
#endif

#endif
