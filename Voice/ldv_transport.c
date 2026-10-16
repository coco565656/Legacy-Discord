/*
 * ldv_transport.c - voice transport encryption for Legacy Discord.
 *
 * Built into libLegacyDiscordVoice.dylib (see scripts/build-voice-deps.sh)
 * so the app can use OpenSSL's AES-256-GCM without OpenSSL's symbols
 * leaking into, or clashing with, anything else in the process.
 *
 * Mode: aead_aes256_gcm_rtpsize. The RTP header (including any extension
 * header) is the additional authenticated data, the 32-bit nonce counter is
 * appended after the ciphertext+tag and zero-padded to a 12-byte IV.
 */

#include "ldv_transport.h"
#include <openssl/evp.h>
#include <string.h>

#define LDV_EXPORT __attribute__((visibility("default")))

static int ldv_aes256gcm(int encrypt, const uint8_t key[32], uint32_t nonce,
                         const uint8_t *aad, size_t aadLength,
                         const uint8_t *input, size_t inputLength,
                         uint8_t *output, uint8_t tag[16]) {
    uint8_t iv[12] = {0};
    int length = 0;
    int ok = 0;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return 0;
    /* Big-endian counter in the first four bytes, as Discord sends it. */
    iv[0] = (uint8_t)(nonce >> 24);
    iv[1] = (uint8_t)(nonce >> 16);
    iv[2] = (uint8_t)(nonce >> 8);
    iv[3] = (uint8_t)nonce;
    if (EVP_CipherInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL, encrypt) != 1) goto done;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, sizeof(iv), NULL) != 1) goto done;
    if (EVP_CipherInit_ex(ctx, NULL, NULL, key, iv, encrypt) != 1) goto done;
    if (aadLength && EVP_CipherUpdate(ctx, NULL, &length, aad, (int)aadLength) != 1) goto done;
    if (inputLength && EVP_CipherUpdate(ctx, output, &length, input, (int)inputLength) != 1) goto done;
    if (!encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, tag) != 1) goto done;
    if (EVP_CipherFinal_ex(ctx, output + length, &length) != 1) goto done;
    if (encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag) != 1) goto done;
    ok = 1;
done:
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

LDV_EXPORT size_t ldv_transport_seal(const uint8_t key[32], uint32_t nonce,
                                     const uint8_t *header, size_t headerLength,
                                     const uint8_t *payload, size_t payloadLength,
                                     uint8_t *packet, size_t packetCapacity) {
    size_t total = headerLength + payloadLength + 16 + 4;
    if (packetCapacity < total) return 0;
    memmove(packet, header, headerLength);
    if (!ldv_aes256gcm(1, key, nonce, header, headerLength, payload, payloadLength,
                       packet + headerLength, packet + headerLength + payloadLength)) return 0;
    packet[total - 4] = (uint8_t)(nonce >> 24);
    packet[total - 3] = (uint8_t)(nonce >> 16);
    packet[total - 2] = (uint8_t)(nonce >> 8);
    packet[total - 1] = (uint8_t)nonce;
    return total;
}

LDV_EXPORT size_t ldv_transport_open(const uint8_t key[32],
                                     const uint8_t *packet, size_t packetLength, size_t headerLength,
                                     uint8_t *payload, size_t payloadCapacity) {
    size_t cipherLength;
    uint32_t nonce;
    uint8_t tag[16];
    if (packetLength < headerLength + 16 + 4) return 0;
    cipherLength = packetLength - headerLength - 16 - 4;
    if (payloadCapacity < cipherLength) return 0;
    nonce = ((uint32_t)packet[packetLength - 4] << 24) | ((uint32_t)packet[packetLength - 3] << 16) |
            ((uint32_t)packet[packetLength - 2] << 8) | (uint32_t)packet[packetLength - 1];
    memcpy(tag, packet + headerLength + cipherLength, 16);
    if (!ldv_aes256gcm(0, key, nonce, packet, headerLength, packet + headerLength, cipherLength,
                       payload, tag)) return 0;
    return cipherLength ? cipherLength : 0;
}
