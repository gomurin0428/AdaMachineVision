#include "amv_aravis.h"

#include <arv.h>
#include <gio/gio.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AMV_GVCP_PORT 3956
#define AMV_STREAM_BUFFER_COUNT 4

typedef struct {
	ArvCamera *camera;
	ArvStream *stream;
	gboolean streaming;
} AmvAravisCamera;

#ifdef AMV_ARAVIS_TESTING
static unsigned int test_stop_attempts;
static unsigned int test_stop_failures_remaining;

static gboolean
test_selector_allowed(const char *device_id)
{
	return device_id != NULL && strcmp(device_id, "127.0.0.1") == 0;
}

int
amv_aravis_test_selector_policy(void)
{
	return test_selector_allowed("127.0.0.1") &&
		!test_selector_allowed("127.0.0.2") &&
		!test_selector_allowed("192.0.2.1") &&
		!test_selector_allowed("AMVFAKE") &&
		!test_selector_allowed("127.0.0.1 ") ? 0 : 1;
}

void
amv_aravis_test_reset_stop_attempts(void)
{
	test_stop_attempts = 0;
	test_stop_failures_remaining = 0;
}

void
amv_aravis_test_fail_next_stop(void)
{
	test_stop_failures_remaining = 1;
}

unsigned int
amv_aravis_test_stop_attempts(void)
{
	return test_stop_attempts;
}
#endif

static void
set_error(char *buffer, size_t buffer_size, const char *format, ...)
{
	va_list arguments;

	if (buffer == NULL || buffer_size == 0)
		return;

	va_start(arguments, format);
	vsnprintf(buffer, buffer_size, format, arguments);
	va_end(arguments);
}

static int
set_gerror(int status, GError **error, char *message, size_t message_size)
{
	if (error != NULL && *error != NULL) {
		set_error(message, message_size, "%s", (*error)->message);
		g_clear_error(error);
	}

	return status;
}

static void
stop_acquisition(ArvCamera *camera, GError **error)
{
#ifdef AMV_ARAVIS_TESTING
	test_stop_attempts++;
	if (test_stop_failures_remaining > 0) {
		test_stop_failures_remaining--;
		g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
				    "Injected acquisition stop failure");
		return;
	}
#endif
	arv_camera_stop_acquisition(camera, error);
}

static GInetAddress *
get_local_ipv4_address(GInetAddress *device_address, GError **error)
{
	GSocket *socket = NULL;
	GSocketAddress *remote_address = NULL;
	GSocketAddress *local_address = NULL;
	GInetAddress *local_ipv4_address = NULL;

	socket = g_socket_new(G_SOCKET_FAMILY_IPV4, G_SOCKET_TYPE_DATAGRAM,
			     G_SOCKET_PROTOCOL_UDP, error);
	if (socket == NULL)
		goto done;

	remote_address = g_inet_socket_address_new(device_address, AMV_GVCP_PORT);
	if (!g_socket_connect(socket, remote_address, NULL, error))
		goto done;

	local_address = g_socket_get_local_address(socket, error);
	if (local_address == NULL)
		goto done;
	if (!G_IS_INET_SOCKET_ADDRESS(local_address)) {
		g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
				    "Could not select a local IPv4 interface");
		goto done;
	}

	local_ipv4_address = g_object_ref
		(g_inet_socket_address_get_address
		 (G_INET_SOCKET_ADDRESS(local_address)));

done:
	g_clear_object(&local_address);
	g_clear_object(&remote_address);
	g_clear_object(&socket);
	return local_ipv4_address;
}

int
amv_aravis_open(const char *device_id, void **camera_out,
		char *error, size_t error_size)
{
	ArvCamera *camera = NULL;
	ArvDevice *device = NULL;
	GInetAddress *device_address = NULL;
	GInetAddress *interface_address = NULL;
	GError *gerror = NULL;
	ArvPixelFormat pixel_format;
	AmvAravisCamera *result = NULL;
	int status = AMV_ARAVIS_ERROR;

	if (camera_out == NULL)
		return AMV_ARAVIS_BAD_PARAMETER;
	*camera_out = NULL;
	if (device_id == NULL || device_id[0] == '\0') {
		set_error(error, error_size, "Device ID must not be empty");
		return AMV_ARAVIS_BAD_PARAMETER;
	}

#ifdef AMV_ARAVIS_TESTING
	if (!test_selector_allowed(device_id)) {
		set_error(error, error_size,
			  "Test adapter only permits the literal address 127.0.0.1");
		return AMV_ARAVIS_BAD_PARAMETER;
	}
#endif

	device_address = g_inet_address_new_from_string(device_id);
	if (device_address != NULL) {
		if (g_inet_address_get_family(device_address) != G_SOCKET_FAMILY_IPV4) {
			set_error(error, error_size,
				  "Only IPv4 GigE Vision addresses are supported");
			status = AMV_ARAVIS_UNSUPPORTED;
			goto done;
		}

		interface_address = get_local_ipv4_address(device_address, &gerror);
		if (interface_address == NULL) {
			set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
			goto done;
		}

		device = arv_gv_device_new(interface_address, device_address, &gerror);
		if (device == NULL) {
			set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
			goto done;
		}

		camera = arv_camera_new_with_device(device, &gerror);
	} else {
		camera = arv_camera_new(device_id, &gerror);
	}

	if (camera == NULL) {
		set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
		goto done;
	}
	if (device_address != NULL && g_inet_address_get_is_loopback(device_address))
		arv_camera_gv_set_stream_options
			(camera, ARV_GV_STREAM_OPTION_PACKET_SOCKET_DISABLED);

	pixel_format = arv_camera_get_pixel_format(camera, &gerror);
	if (gerror != NULL) {
		set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
		goto done;
	}
	if (pixel_format != ARV_PIXEL_FORMAT_MONO_8) {
		set_error(error, error_size,
			  "Unsupported pixel format; only Mono8 is supported");
		status = AMV_ARAVIS_UNSUPPORTED;
		goto done;
	}

	result = calloc(1, sizeof(*result));
	if (result == NULL) {
		set_error(error, error_size, "Could not allocate camera state");
		goto done;
	}
	result->camera = camera;
	camera = NULL;
	*camera_out = result;
	result = NULL;
	status = AMV_ARAVIS_SUCCESS;

done:
	if (result != NULL) {
	g_clear_object(&result->stream);
	g_clear_object(&result->camera);
	free(result);
	}
	g_clear_object(&camera);
	g_clear_object(&device);
	g_clear_object(&interface_address);
	g_clear_object(&device_address);
	g_clear_error(&gerror);
	return status;
}

static void
stop_and_release_stream(AmvAravisCamera *camera)
{
	GError *error = NULL;

	if (camera->streaming) {
		stop_acquisition(camera->camera, &error);
		g_clear_error(&error);
		camera->streaming = FALSE;
	}
	g_clear_object(&camera->stream);
}

void
amv_aravis_close(void *opaque_camera)
{
	AmvAravisCamera *camera = opaque_camera;

	if (camera == NULL)
		return;

	stop_and_release_stream(camera);
	g_clear_object(&camera->camera);
	free(camera);
}

int
amv_aravis_start(void *opaque_camera, char *error, size_t error_size)
{
	AmvAravisCamera *camera = opaque_camera;
	GError *gerror = NULL;
	guint payload_size;
	unsigned int index;

	if (camera == NULL || camera->camera == NULL) {
		set_error(error, error_size, "Camera is not open");
		return AMV_ARAVIS_BAD_PARAMETER;
	}
	if (camera->streaming)
		return AMV_ARAVIS_SUCCESS;

	camera->stream = arv_camera_create_stream(camera->camera, NULL, NULL,
						  &gerror);
	if (camera->stream == NULL)
		return set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);

	payload_size = arv_camera_get_payload(camera->camera, &gerror);
	if (gerror != NULL || payload_size == 0) {
		if (gerror == NULL)
			set_error(error, error_size, "Camera reported an empty payload");
		else
			set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
		g_clear_object(&camera->stream);
		return AMV_ARAVIS_ERROR;
	}

	for (index = 0; index < AMV_STREAM_BUFFER_COUNT; index++) {
		ArvBuffer *buffer = arv_buffer_new_allocate(payload_size);
		if (buffer == NULL) {
			set_error(error, error_size, "Could not allocate stream buffer");
			g_clear_object(&camera->stream);
			return AMV_ARAVIS_ERROR;
		}
		arv_stream_push_buffer(camera->stream, buffer);
	}

	arv_camera_start_acquisition(camera->camera, &gerror);
	if (gerror != NULL) {
		set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
		stop_acquisition(camera->camera, &gerror);
		g_clear_error(&gerror);
		g_clear_object(&camera->stream);
		return AMV_ARAVIS_ERROR;
	}

	camera->streaming = TRUE;
	return AMV_ARAVIS_SUCCESS;
}

int
amv_aravis_stop(void *opaque_camera, char *error, size_t error_size)
{
	AmvAravisCamera *camera = opaque_camera;
	GError *gerror = NULL;

	if (camera == NULL || !camera->streaming)
		return AMV_ARAVIS_SUCCESS;

	stop_acquisition(camera->camera, &gerror);
	if (gerror != NULL)
		return set_gerror(AMV_ARAVIS_ERROR, &gerror, error, error_size);
	camera->streaming = FALSE;
	g_clear_object(&camera->stream);
	return AMV_ARAVIS_SUCCESS;
}

int
amv_aravis_is_streaming(void *opaque_camera)
{
	AmvAravisCamera *camera = opaque_camera;

	return camera != NULL && camera->streaming;
}

int
amv_aravis_copy_mono8(const void *source, size_t source_size,
		      uint32_t width, uint32_t height,
		      size_t row_stride, size_t x_padding,
		      size_t y_padding_rows,
		      void *destination, size_t destination_size,
		      size_t *copied_size, char *error, size_t error_size)
{
	const uint8_t *source_bytes = source;
	uint8_t *destination_bytes = destination;
	size_t row_bytes;
	size_t expected_stride;
	size_t padded_height;
	size_t expected_source_size;
	uint32_t row;

	if (copied_size != NULL)
		*copied_size = 0;
	if (source == NULL || destination == NULL || copied_size == NULL ||
	    width == 0 || height == 0) {
		set_error(error, error_size, "Invalid Mono8 image data");
		return AMV_ARAVIS_BAD_PARAMETER;
	}
	if ((size_t) width > SIZE_MAX / (size_t) height) {
		set_error(error, error_size, "Mono8 image dimensions overflow");
		return AMV_ARAVIS_ERROR;
	}

	row_bytes = (size_t) width * (size_t) height;
	if (x_padding > SIZE_MAX - (size_t) width) {
		set_error(error, error_size, "Mono8 horizontal padding overflows");
		return AMV_ARAVIS_ERROR;
	}
	expected_stride = (size_t) width + x_padding;
	if (row_stride != expected_stride) {
		set_error(error, error_size, "Mono8 row stride and horizontal padding disagree");
		return AMV_ARAVIS_ERROR;
	}
	if (y_padding_rows > SIZE_MAX - (size_t) height) {
		set_error(error, error_size, "Mono8 vertical padding overflows");
		return AMV_ARAVIS_ERROR;
	}
	padded_height = (size_t) height + y_padding_rows;
	if (row_stride != 0 && padded_height > SIZE_MAX / row_stride) {
		set_error(error, error_size, "Mono8 padded image size overflows");
		return AMV_ARAVIS_ERROR;
	}
	expected_source_size = row_stride * padded_height;
	if (destination_size < row_bytes || source_size != expected_source_size) {
		set_error(error, error_size, "Mono8 image buffer size is invalid");
		return AMV_ARAVIS_ERROR;
	}

	for (row = 0; row < height; row++)
		memcpy(destination_bytes + (size_t) row * width,
		       source_bytes + (size_t) row * row_stride, width);

	*copied_size = row_bytes;
	return AMV_ARAVIS_SUCCESS;
}

int
amv_aravis_grab(void *opaque_camera, uint64_t timeout_ms,
		uint32_t *width_out, uint32_t *height_out,
		void **pixels_out, size_t *pixel_size_out,
		char *error, size_t error_size)
{
	AmvAravisCamera *camera = opaque_camera;
	ArvBuffer *buffer = NULL;
	const void *source;
	size_t source_size;
	size_t row_stride;
	size_t copied_size = 0;
	gint width;
	gint height;
	void *pixels = NULL;
	int result = AMV_ARAVIS_ERROR;

	if (width_out != NULL)
		*width_out = 0;
	if (height_out != NULL)
		*height_out = 0;
	if (pixels_out != NULL)
		*pixels_out = NULL;
	if (pixel_size_out != NULL)
		*pixel_size_out = 0;
	if (camera == NULL || !camera->streaming || width_out == NULL ||
	    height_out == NULL || pixels_out == NULL || pixel_size_out == NULL ||
	    timeout_ms == 0 || timeout_ms > G_MAXUINT64 / 1000) {
		set_error(error, error_size, "Invalid camera, output, or timeout");
		return AMV_ARAVIS_BAD_PARAMETER;
	}

	buffer = arv_stream_timeout_pop_buffer(camera->stream,
					       timeout_ms * 1000);
	if (buffer == NULL) {
		set_error(error, error_size, "Timed out waiting for a camera frame");
		return AMV_ARAVIS_TIMEOUT;
	}

	if (arv_buffer_get_status(buffer) == ARV_BUFFER_STATUS_TIMEOUT) {
		set_error(error, error_size, "Timed out receiving a camera frame");
		result = AMV_ARAVIS_TIMEOUT;
		goto done;
	}
	if (arv_buffer_get_status(buffer) != ARV_BUFFER_STATUS_SUCCESS) {
		set_error(error, error_size, "Aravis reported an incomplete camera frame");
		goto done;
	}
	if (arv_buffer_get_payload_type(buffer) != ARV_BUFFER_PAYLOAD_TYPE_IMAGE) {
		set_error(error, error_size, "Camera frame does not contain an image payload");
		goto done;
	}
	if (arv_buffer_get_image_pixel_format(buffer) != ARV_PIXEL_FORMAT_MONO_8) {
		set_error(error, error_size,
			  "Unsupported pixel format; only Mono8 is supported");
		result = AMV_ARAVIS_UNSUPPORTED;
		goto done;
	}

	width = arv_buffer_get_image_width(buffer);
	height = arv_buffer_get_image_height(buffer);
	if (width <= 0 || height <= 0) {
		set_error(error, error_size, "Camera frame has invalid dimensions");
		goto done;
	}

	source = arv_buffer_get_data(buffer, &source_size);
	if (source == NULL) {
		set_error(error, error_size, "Camera frame has no image data");
		goto done;
	}
	if ((size_t) width > SIZE_MAX / (size_t) height) {
		set_error(error, error_size, "Camera frame dimensions overflow");
		goto done;
	}
	row_stride = (size_t) width;

	pixels = malloc((size_t) width * (size_t) height);
	if (pixels == NULL) {
		set_error(error, error_size, "Could not allocate image pixels");
		goto done;
	}

	result = amv_aravis_copy_mono8(source, source_size,
				       (uint32_t) width, (uint32_t) height,
				       row_stride, 0, 0,
				       pixels, (size_t) width * (size_t) height,
				       &copied_size, error, error_size);
	if (result != AMV_ARAVIS_SUCCESS)
		goto done;

	*width_out = (uint32_t) width;
	*height_out = (uint32_t) height;
	*pixels_out = pixels;
	*pixel_size_out = copied_size;
	pixels = NULL;
	result = AMV_ARAVIS_SUCCESS;

done:
	free(pixels);
	arv_stream_push_buffer(camera->stream, buffer);
	return result;
}

void
amv_aravis_free_pixels(void *pixels)
{
	free(pixels);
}
