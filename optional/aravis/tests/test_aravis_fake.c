#include <arv.h>

#include <stdio.h>
#include <string.h>

#define AMV_TEST_FAKE_WIDTH 64
#define AMV_TEST_FAKE_HEIGHT 48

static ArvGvFakeCamera *fake_camera;
static guint8 next_pixel_value;

static void
fill_pattern(ArvBuffer *buffer, void *data, guint32 exposure_time_us,
	     guint32 gain, ArvPixelFormat pixel_format)
{
	void *pixels = (void *) arv_buffer_get_data(buffer, NULL);
	guint8 *next_value = data;

	(void) exposure_time_us;
	(void) gain;
	if (pixel_format != ARV_PIXEL_FORMAT_MONO_8 || pixels == NULL)
		return;

	memset(pixels, *next_value,
	       AMV_TEST_FAKE_WIDTH * AMV_TEST_FAKE_HEIGHT);
	(*next_value)++;
}

int
amv_test_fake_start(void)
{
	ArvFakeCamera *camera;

	if (fake_camera != NULL)
		return 0;

	next_pixel_value = 1;
	fake_camera = arv_gv_fake_camera_new("127.0.0.1", "AMVFAKE");
	if (fake_camera == NULL || !arv_gv_fake_camera_is_running(fake_camera)) {
		fprintf(stderr, "Could not start the Aravis fake camera on 127.0.0.1\n");
		g_clear_object(&fake_camera);
		return 1;
	}

	camera = arv_gv_fake_camera_get_fake_camera(fake_camera);
	if (!arv_fake_camera_write_register
		    (camera, ARV_FAKE_CAMERA_REGISTER_WIDTH, AMV_TEST_FAKE_WIDTH) ||
	    !arv_fake_camera_write_register
		    (camera, ARV_FAKE_CAMERA_REGISTER_HEIGHT, AMV_TEST_FAKE_HEIGHT)) {
		fprintf(stderr, "Could not set the loopback fixture dimensions\n");
		g_clear_object(&fake_camera);
		return 1;
	}
	arv_fake_camera_set_fill_pattern(camera, fill_pattern, &next_pixel_value);
	g_object_set(fake_camera, "gvsp-lost-ratio", 0.0, NULL);
	return 0;
}

int
amv_test_fake_set_packet_loss(int enabled)
{
	if (fake_camera == NULL)
		return 1;
	g_object_set(fake_camera, "gvsp-lost-ratio", enabled ? 1.0 : 0.0, NULL);
	return 0;
}

int
amv_test_fake_set_mono16(void)
{
	ArvFakeCamera *camera;

	if (fake_camera == NULL)
		return 1;
	camera = arv_gv_fake_camera_get_fake_camera(fake_camera);
	return arv_fake_camera_write_register
		(camera, ARV_FAKE_CAMERA_REGISTER_PIXEL_FORMAT,
		 ARV_PIXEL_FORMAT_MONO_16) ? 0 : 1;
}

int
amv_test_fake_set_mono8(void)
{
	ArvFakeCamera *camera;

	if (fake_camera == NULL)
		return 1;
	camera = arv_gv_fake_camera_get_fake_camera(fake_camera);
	return arv_fake_camera_write_register
		(camera, ARV_FAKE_CAMERA_REGISTER_PIXEL_FORMAT,
		 ARV_PIXEL_FORMAT_MONO_8) ? 0 : 1;
}

void
amv_test_fake_stop(void)
{
	g_clear_object(&fake_camera);
}
