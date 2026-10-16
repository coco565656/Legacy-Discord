/*
 * ldv_transport.h - voice transport encryption (aead_aes256_gcm_rtpsize).
 * Implemented in libLegacyDiscordVoice.dylib.
 */

#ifndef LDV_TRANSPORT_H
#define LDV_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Builds header + ciphertext + 16-byte tag + 4-byte big-endian nonce into
 * packet. Returns the packet length, or 0 on failure. */
size_t ldv_transport_seal(const uint8_t key[32], uint32_t nonce,
                          const uint8_t *header, size_t headerLength,
                          const uint8_t *payload, size_t payloadLength,
                          uint8_t *packet, size_t packetCapacity);

/* Authenticates and decrypts a received packet whose first headerLength
 * bytes are the RTP header (AAD). Returns the plaintext length, or 0 when the
 * packet is too short or fails authentication. */
size_t ldv_transport_open(const uint8_t key[32],
                          const uint8_t *packet, size_t packetLength, size_t headerLength,
                          uint8_t *payload, size_t payloadCapacity);

#ifdef __cplusplus
}
#endif

#endif
