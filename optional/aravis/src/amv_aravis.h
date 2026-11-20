#ifndef AMV_ARAVIS_H
#define AMV_ARAVIS_H

#include <stddef.h>
#include <stdint.h>

enum {
	AMV_ARAVIS_SUCCESS = 0,
	AMV_ARAVIS_TIMEOUT = 1,
	AMV_ARAVIS_UNSUPPORTED = 2,
	AMV_ARAVIS_BAD_PARAMETER = 3,
	AMV_ARAVIS_ERROR = 4,
	AMV_ARAVIS_OUT_OF_MEMORY = 5,
	AMV_ARAVIS_NOT_CALLED = 6
};

int amv_aravis_open(const char *device_id, void **camera,
		    char *error, size_t error_size);
int amv_aravis_close(void *camera);
int amv_aravis_start(void *camera, char *error, size_t error_size);
int amv_aravis_stop(void *camera, char *error, size_t error_size);
int amv_aravis_is_streaming(void *camera);
int amv_aravis_grab(void *camera, uint64_t timeout_ms,
			    int32_t *buffer_status,
			    uint32_t *payload_type, uint32_t *pixel_format,
			    int32_t *width, int32_t *height,
			    void **raw_bytes, size_t *raw_size,
			    char *error, size_t error_size);
void amv_aravis_free_pixels(void *pixels);

#ifdef AMV_ARAVIS_TESTING
void amv_aravis_test_reset_stop_attempts(void);
void amv_aravis_test_fail_next_stop(void);
unsigned int amv_aravis_test_stop_attempts(void);
int amv_aravis_test_selector_policy(void);
#endif

#endif
