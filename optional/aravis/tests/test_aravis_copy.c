#include "../src/amv_aravis.h"

#include <stdint.h>
#include <string.h>

int
amv_test_copy_rows(void)
{
	const uint8_t padded_source[] = {1, 2, 3, 90, 4, 5, 6, 91};
	const uint8_t padded_with_trailing_rows[] = {
		1, 2, 3, 90, 4, 5, 6, 91, 92, 93, 94, 95
	};
	const uint8_t packed_source[] = {1, 2, 3, 4, 5, 6};
	const uint8_t expected[] = {1, 2, 3, 4, 5, 6};
	uint8_t destination[sizeof(expected)] = {0};
	char error[128] = {0};
	size_t copied_size = 0;
	int failures = 0;

	if (amv_aravis_copy_mono8(padded_source, sizeof(padded_source), 3, 2,
				  4, 1, 0,
				  destination, sizeof(destination), &copied_size,
				  error, sizeof(error)) != AMV_ARAVIS_SUCCESS ||
	    copied_size != sizeof(expected) ||
	    memcmp(destination, expected, sizeof(expected)) != 0)
		failures++;
	if (amv_aravis_copy_mono8(packed_source, sizeof(packed_source), 3, 2,
				  3, 0, 0,
				  destination, sizeof(destination), &copied_size,
				  error, sizeof(error)) != AMV_ARAVIS_SUCCESS ||
	    copied_size != sizeof(expected) ||
	    memcmp(destination, expected, sizeof(expected)) != 0)
		failures++;

	if (amv_aravis_copy_mono8(padded_with_trailing_rows,
				  sizeof(padded_with_trailing_rows), 3, 2,
				  4, 1, 1, destination, sizeof(destination),
				  &copied_size, error, sizeof(error)) != AMV_ARAVIS_SUCCESS ||
	    copied_size != sizeof(expected) ||
	    memcmp(destination, expected, sizeof(expected)) != 0)
		failures++;

	if (amv_aravis_copy_mono8(padded_with_trailing_rows, 10, 3, 2,
				  4, 1, 1, destination, sizeof(destination),
				  &copied_size, error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;
	if (amv_aravis_copy_mono8(padded_with_trailing_rows,
				  sizeof(padded_with_trailing_rows), 3, 2,
				  3, 0, 0, destination, sizeof(destination),
				  &copied_size, error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, sizeof(padded_source), 3, 2,
				  4, 1, 1, destination, sizeof(destination),
				  &copied_size, error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, 6, 3, 2,
				  4, 1, 0, destination, sizeof(destination),
				  &copied_size, error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, 5, 3, 2, 4, 1, 0,
				  destination,
				  sizeof(destination), &copied_size,
				  error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, 7, 3, 2, 4, 1, 0,
				  destination,
				  sizeof(destination), &copied_size,
				  error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, sizeof(padded_source), 3, 2,
				  4, 1, 0,
				  destination, sizeof(destination) - 1, &copied_size,
				  error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	if (amv_aravis_copy_mono8(padded_source, sizeof(padded_source), 0, 2,
				  0, 0, 0,
				  destination, sizeof(destination), &copied_size,
				  error, sizeof(error)) == AMV_ARAVIS_SUCCESS)
		failures++;

	return failures;
}
