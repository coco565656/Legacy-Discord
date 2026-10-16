/*
 * voice_selftest.c - checks libLegacyDiscordVoice.dylib on the target OS:
 * DAVE session + key package, Opus encode/decode round trip, and the
 * transport seal/open round trip (including tamper detection).
 *
 * cc -mmacosx-version-min=10.8 -I out/include voice_selftest.c ldv_protocol.c \
 *    -L out -lLegacyDiscordVoice -Wl,-rpath,@executable_path -o voice_selftest
 */

#include <stdio.h>
#include <string.h>
#include <math.h>
#include <dave/dave.h>
#include <opus/opus.h>
#include "ldv_transport.h"
#include "ldv_protocol.h"

static int failures = 0;
#define CHECK(cond, what) do { if (cond) printf("ok   %s\n", what); else { printf("FAIL %s\n", what); failures++; } } while (0)

static void onMLSFailure(const char *source, const char *reason, void *userData) {
    printf("MLS failure: %s: %s\n", source, reason);
}

int main(void) {
    /* DAVE */
    uint16_t version = daveMaxSupportedProtocolVersion();
    printf("DAVE max protocol version: %u\n", version);
    CHECK(version >= 1, "DAVE protocol version");
    DAVESessionHandle session = daveSessionCreate(NULL, "", onMLSFailure, NULL);
    CHECK(session != NULL, "DAVE session create");
    daveSessionInit(session, version, 1234567890123456789ULL, "1234567890123456789");
    uint8_t *keyPackage = NULL;
    size_t keyPackageLength = 0;
    daveSessionGetMarshalledKeyPackage(session, &keyPackage, &keyPackageLength);
    printf("key package: %zu bytes\n", keyPackageLength);
    CHECK(keyPackage && keyPackageLength > 64, "DAVE key package");
    if (keyPackage) daveFree(keyPackage);
    DAVEEncryptorHandle encryptor = daveEncryptorCreate();
    DAVEDecryptorHandle decryptor = daveDecryptorCreate();
    CHECK(encryptor && decryptor, "DAVE encryptor/decryptor create");
    daveEncryptorDestroy(encryptor);
    daveDecryptorDestroy(decryptor);
    daveSessionDestroy(session);

    /* Opus: 20 ms of a 440 Hz tone, stereo 48 kHz. */
    int error = 0;
    OpusEncoder *encoder = opus_encoder_create(48000, 2, OPUS_APPLICATION_VOIP, &error);
    OpusDecoder *decoder = opus_decoder_create(48000, 2, &error);
    CHECK(encoder && decoder, "Opus encoder/decoder create");
    opus_int16 pcm[960 * 2], out[960 * 2];
    int i;
    for (i = 0; i < 960; i++) {
        pcm[i * 2] = pcm[i * 2 + 1] = (opus_int16)(8000 * sin(2 * M_PI * 440 * i / 48000.0));
    }
    unsigned char frame[1275];
    int frameLength = opus_encode(encoder, pcm, 960, frame, sizeof(frame));
    printf("opus frame: %d bytes (%s)\n", frameLength, opus_get_version_string());
    CHECK(frameLength > 0, "Opus encode");
    CHECK(opus_decode(decoder, frame, frameLength, out, 960, 0) == 960, "Opus decode");
    opus_encoder_destroy(encoder);
    opus_decoder_destroy(decoder);

    /* Transport */
    uint8_t key[32], header[12] = {0x80, 0x78, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3};
    for (i = 0; i < 32; i++) key[i] = (uint8_t)i;
    uint8_t packet[1500], payload[1500];
    size_t packetLength = ldv_transport_seal(key, 7, header, sizeof(header), frame, (size_t)frameLength,
                                             packet, sizeof(packet));
    CHECK(packetLength == sizeof(header) + (size_t)frameLength + 20, "transport seal");
    size_t opened = ldv_transport_open(key, packet, packetLength, sizeof(header), payload, sizeof(payload));
    CHECK(opened == (size_t)frameLength && memcmp(payload, frame, opened) == 0, "transport open");
    packet[sizeof(header) + 1] ^= 1;
    CHECK(ldv_transport_open(key, packet, packetLength, sizeof(header), payload, sizeof(payload)) == 0,
          "transport rejects tampering");

    /* Protocol helpers */
    uint8_t discovery[LDV_DISCOVERY_LENGTH];
    ldv_discovery_request(0x01020304, discovery);
    CHECK(discovery[1] == 1 && discovery[3] == 70 && discovery[7] == 4, "discovery request");
    discovery[1] = 2;
    strcpy((char *)discovery + 8, "203.0.113.7");
    discovery[72] = 0xC3; discovery[73] = 0x50;
    char address[65];
    uint16_t port = 0;
    CHECK(ldv_discovery_parse(discovery, sizeof(discovery), address, &port) &&
          strcmp(address, "203.0.113.7") == 0 && port == 50000, "discovery response");
    uint8_t rtp[12];
    ldv_rtp_write(513, 0x0A0B0C0D, 0x11223344, rtp);
    uint8_t received[64] = {0};
    memcpy(received, rtp, 12);
    ldv_rtp_header parsed;
    CHECK(ldv_rtp_parse(received, 40, &parsed) && parsed.sequence == 513 && parsed.ssrc == 0x11223344 &&
          parsed.aadLength == 12 && parsed.extensionBodyLength == 0, "RTP header");
    received[0] = 0x90;                 /* with a one-word extension (0xBEDE, length 1) */
    received[12] = 0xBE; received[13] = 0xDE; received[14] = 0; received[15] = 1;
    CHECK(ldv_rtp_parse(received, 44, &parsed) && parsed.aadLength == 16 && parsed.extensionBodyLength == 4,
          "RTP header with extension");
    received[1] = 201;
    CHECK(!ldv_rtp_parse(received, 44, &parsed), "RTCP ignored");
    uint8_t binary[] = {0x00, 0x07, 29, 0x00, 0x05, 0xAA, 0xBB};
    uint16_t sequence = 0, transition = 0;
    uint8_t opcode = 0;
    const uint8_t *body = NULL, *inner = NULL;
    size_t bodyLength = 0, innerLength = 0;
    CHECK(ldv_binary_parse(binary, sizeof(binary), &sequence, &opcode, &body, &bodyLength) &&
          sequence == 7 && opcode == 29 && bodyLength == 4, "binary frame");
    CHECK(ldv_transition_payload(body, bodyLength, &transition, &inner, &innerLength) &&
          transition == 5 && innerLength == 2 && inner[0] == 0xAA, "transition payload");

    printf(failures ? "SELFTEST FAILED (%d)\n" : "SELFTEST PASSED\n", failures);
    return failures ? 1 : 0;
}
