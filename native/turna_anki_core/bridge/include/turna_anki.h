#ifndef TURNA_ANKI_H
#define TURNA_ANKI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t TurnaAnkiHandle;

typedef struct TurnaAnkiBuffer {
    uint8_t* ptr;
    uintptr_t len;
} TurnaAnkiBuffer;

typedef struct TurnaAnkiResult {
    int32_t status;
    TurnaAnkiBuffer buffer;
} TurnaAnkiResult;

/* Contract / probe. Implemented in P0-001. */
uint32_t turna_anki_abi_version(void);

/* Lifecycle and call surface. Declared now so the header is the ABI
 * source of truth; implementations land in later P0 tasks. */
TurnaAnkiResult turna_anki_engine_new(const uint8_t* config, size_t config_len);
TurnaAnkiResult turna_anki_engine_open(
    TurnaAnkiHandle handle,
    const uint8_t* request,
    size_t request_len
);
TurnaAnkiResult turna_anki_call(
    TurnaAnkiHandle handle,
    uint32_t operation,
    const uint8_t* request,
    size_t request_len
);
TurnaAnkiResult turna_anki_cancel(TurnaAnkiHandle handle);
TurnaAnkiResult turna_anki_engine_close(TurnaAnkiHandle handle);
void turna_anki_buffer_free(uint8_t* ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* TURNA_ANKI_H */
