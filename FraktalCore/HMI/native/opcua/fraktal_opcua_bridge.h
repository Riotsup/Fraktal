#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define FRK_EXPORT __declspec(dllexport)
#else
#define FRK_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* FrkOpcUaHandle;

FRK_EXPORT FrkOpcUaHandle frk_opcua_create(void);
FRK_EXPORT void frk_opcua_destroy(FrkOpcUaHandle handle);
FRK_EXPORT int32_t frk_opcua_connect(FrkOpcUaHandle handle,
                                     const char* endpoint,
                                     const char* username,
                                     const char* password,
                                     uint32_t timeout_ms);
FRK_EXPORT void frk_opcua_disconnect(FrkOpcUaHandle handle);
FRK_EXPORT int32_t frk_opcua_is_connected(FrkOpcUaHandle handle);
FRK_EXPORT const char* frk_opcua_last_error(FrkOpcUaHandle handle);

// Returns an owned UTF-8 JSON document. Release it with frk_opcua_free_string.
FRK_EXPORT char* frk_opcua_snapshot_json(FrkOpcUaHandle handle);
FRK_EXPORT void frk_opcua_free_string(char* value);

FRK_EXPORT int32_t frk_opcua_write_bool(FrkOpcUaHandle handle,
                                        const char* browse_path,
                                        int32_t value);
FRK_EXPORT int32_t frk_opcua_write_int64(FrkOpcUaHandle handle,
                                         const char* browse_path,
                                         int64_t value);
FRK_EXPORT int32_t frk_opcua_write_int32(FrkOpcUaHandle handle,
                                         const char* browse_path,
                                         int32_t value);
FRK_EXPORT int32_t frk_opcua_write_uint32(FrkOpcUaHandle handle,
                                          const char* browse_path,
                                          uint32_t value);
FRK_EXPORT int32_t frk_opcua_write_double(FrkOpcUaHandle handle,
                                          const char* browse_path,
                                          double value);
FRK_EXPORT int32_t frk_opcua_write_string(FrkOpcUaHandle handle,
                                          const char* browse_path,
                                          const char* value);

#ifdef __cplusplus
}
#endif
