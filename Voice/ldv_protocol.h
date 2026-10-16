/*
 * ldv_protocol.h - pure C helpers for Discord voice packets, shared by the
 * app (compiled by Xcode) and Voice/voice_selftest.c. No dependencies.
 */

#ifndef LDV_PROTOCOL_H
#define LDV_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* IP discovery (74-byte request/response, big-endian). */
#define LDV_DISCOVERY_LENGTH 74
void ldv_discovery_request(uint32_t ssrc, uint8_t out[LDV_DISCOVERY_LENGTH]);
/* Returns 1 and fills address (NUL-terminated, up to 64 bytes) and port for
 * a valid response, else 0. */
int ldv_discovery_parse(const uint8_t *packet, size_t length, char address[65], uint16_t *port);

/* RTP. */
typedef struct {
    uint16_t sequence;
    uint32_t timestamp;
    uint32_t ssrc;
    uint8_t payloadType;
    /* Bytes authenticated but not encrypted in the rtpsize modes: the fixed
     * header, CSRCs and, when present, the 4-byte extension header. */
    size_t aadLength;
    /* Extension body length in bytes (it is encrypted; strip it from the
     * decrypted payload), 0 without an extension. */
    size_t extensionBodyLength;
} ldv_rtp_header;

/* Returns 1 for an RTP audio packet, 0 for RTCP, keep-alives or garbage. */
int ldv_rtp_parse(const uint8_t *packet, size_t length, ldv_rtp_header *header);
/* Writes the 12-byte Opus RTP header (0x80, 0x78). */
void ldv_rtp_write(uint16_t sequence, uint32_t timestamp, uint32_t ssrc, uint8_t out[12]);

/* Voice gateway binary messages.
 * Server to client: [sequence u16 BE][opcode u8][payload].
 * Client to server: [opcode u8][payload]. */
int ldv_binary_parse(const uint8_t *message, size_t length,
                     uint16_t *sequence, uint8_t *opcode, const uint8_t **payload, size_t *payloadLength);
/* DAVE commit/welcome payloads (opcodes 29, 30) start with a transition id. */
int ldv_transition_payload(const uint8_t *payload, size_t length,
                           uint16_t *transitionId, const uint8_t **body, size_t *bodyLength);

/* The three-byte Opus silence frame Discord expects after speech. */
extern const uint8_t ldv_opus_silence[3];

#ifdef __cplusplus
}
#endif

#endif
