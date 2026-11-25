#include <arv.h>

#include <stdio.h>
#include <string.h>

#define AMV_TEST_FAKE_WIDTH 64
#define AMV_TEST_FAKE_HEIGHT 48
#define AMV_TEST_BAYER_RED 200
#define AMV_TEST_BAYER_GREEN 100
#define AMV_TEST_BAYER_BLUE 40

static ArvGvFakeCamera *fake_camera;
static guint8 next_pixel_value;

/* Layout of the 2x2 cell at the origin: 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR. */
static int
bayer_layout(ArvPixelFormat pixel_format)
{
	switch (pixel_format) {
	case ARV_PIXEL_FORMAT_BAYER_RG_8:
		return 0;
	case ARV_PIXEL_FORMAT_BAYER_GR_8:
		return 1;
	case ARV_PIXEL_FORMAT_BAYER_GB_8:
		return 2;
	case ARV_PIXEL_FORMAT_BAYER_BG_8:
		return 3;
	default:
		return -1;
	}
}

/* Every red, green and blue sample has its own constant value, so each
 * converted grey pixel is the same known luma. */
static void
fill_bayer(guint8 *pixels, int layout)
{
	int x;
	int y;

	for (y = 0; y < AMV_TEST_FAKE_HEIGHT; y++) {
		for (x = 0; x < AMV_TEST_FAKE_WIDTH; x++) {
			int cell_x = (layout & 1) ^ (x & 1);
			int cell_y = ((layout >> 1) & 1) ^ (y & 1);
			guint8 value = AMV_TEST_BAYER_GREEN;

			if (cell_x == 0 && cell_y == 0)
				value = AMV_TEST_BAYER_RED;
			else if (cell_x == 1 && cell_y == 1)
				value = AMV_TEST_BAYER_BLUE;
			pixels[y * AMV_TEST_FAKE_WIDTH + x] = value;
		}
	}
}

static void
fill_pattern(ArvBuffer *buffer, void *data, guint32 exposure_time_us,
	     guint32 gain, ArvPixelFormat pixel_format)
{
	void *pixels = (void *) arv_buffer_get_data(buffer, NULL);
	guint8 *next_value = data;
	int layout = bayer_layout(pixel_format);

	(void) exposure_time_us;
	(void) gain;
	if (pixels == NULL)
		return;
	if (layout >= 0) {
		fill_bayer(pixels, layout);
		return;
	}
	if (pixel_format != ARV_PIXEL_FORMAT_MONO_8)
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

#if defined(_WIN32)
	printf("Native OS: Windows_NT\n");
#elif defined(__linux__)
	printf("Native OS: Linux\n");
#else
	printf("Native OS: unknown\n");
#endif

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

int
amv_test_fake_set_pixel_format(unsigned int pixel_format)
{
	ArvFakeCamera *camera;

	if (fake_camera == NULL)
		return 1;
	camera = arv_gv_fake_camera_get_fake_camera(fake_camera);
	return arv_fake_camera_write_register
		(camera, ARV_FAKE_CAMERA_REGISTER_PIXEL_FORMAT, pixel_format) ? 0 : 1;
}

void
amv_test_fake_stop(void)
{
	g_clear_object(&fake_camera);
}
