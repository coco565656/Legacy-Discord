/*
 * ldv_protocol.c - see ldv_protocol.h.
 */

#include "ldv_protocol.h"
#include <string.h>

const uint8_t ldv_opus_silence[3] = {0xF8, 0xFF, 0xFE};

static uint16_t read16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static uint32_t read32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void write16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)(value >> 8);
    p[1] = (uint8_t)value;
}

static void write32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)(value >> 24);
    p[1] = (uint8_t)(value >> 16);
    p[2] = (uint8_t)(value >> 8);
    p[3] = (uint8_t)value;
}

void ldv_discovery_request(uint32_t ssrc, uint8_t out[LDV_DISCOVERY_LENGTH]) {
    memset(out, 0, LDV_DISCOVERY_LENGTH);
    write16(out, 1);
    write16(out + 2, 70);
    write32(out + 4, ssrc);
}

int ldv_discovery_parse(const uint8_t *packet, size_t length, char address[65], uint16_t *port) {
    if (length < LDV_DISCOVERY_LENGTH || read16(packet) != 2 || read16(packet + 2) != 70) return 0;
    memcpy(address, packet + 8, 64);
    address[64] = '\0';
    if (address[0] == '\0') return 0;
    *port = read16(packet + 72);
    return *port != 0;
}

int ldv_rtp_parse(const uint8_t *packet, size_t length, ldv_rtp_header *header) {
    size_t offset;
    uint8_t csrcCount;
    if (length < 12 || (packet[0] & 0xC0) != 0x80) return 0;
    header->payloadType = packet[1] & 0x7F;
    /* RTCP shares the socket: packet types 200-204 (marker bit included). */
    if (packet[1] >= 200 && packet[1] <= 204) return 0;
    header->sequence = read16(packet + 2);
    header->timestamp = read32(packet + 4);
    header->ssrc = read32(packet + 8);
    csrcCount = packet[0] & 0x0F;
    offset = 12 + (size_t)csrcCount * 4;
    header->extensionBodyLength = 0;
    if (packet[0] & 0x10) {
        if (length < offset + 4) return 0;
        header->extensionBodyLength = (size_t)read16(packet + offset + 2) * 4;
        offset += 4;
    }
    header->aadLength = offset;
    /* Ciphertext + 16-byte tag + 4-byte nonce must follow. */
    return length >= offset + 20;
}

void ldv_rtp_write(uint16_t sequence, uint32_t timestamp, uint32_t ssrc, uint8_t out[12]) {
    out[0] = 0x80;
    out[1] = 0x78;
    write16(out + 2, sequence);
    write32(out + 4, timestamp);
    write32(out + 8, ssrc);
}

int ldv_binary_parse(const uint8_t *message, size_t length,
                     uint16_t *sequence, uint8_t *opcode, const uint8_t **payload, size_t *payloadLength) {
    if (length < 3) return 0;
    *sequence = read16(message);
    *opcode = message[2];
    *payload = message + 3;
    *payloadLength = length - 3;
    return 1;
}

int ldv_transition_payload(const uint8_t *payload, size_t length,
                           uint16_t *transitionId, const uint8_t **body, size_t *bodyLength) {
    if (length < 2) return 0;
    *transitionId = read16(payload);
    *body = payload + 2;
    *bodyLength = length - 2;
    return 1;
}
