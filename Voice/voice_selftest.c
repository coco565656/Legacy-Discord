/*
 * voice_selftest.c - checks libLegacyDiscordVoice.dylib on the target OS:
 * DAVE session + key package, Opus encode/decode round trip, and the
 * transport seal/open round trip (including tamper detection).
 *
 * cc -mmacosx-version-min=10.8 -I out/include voice_selftest.c \
 *    -L out -lLegacyDiscordVoice -Wl,-rpath,@executable_path -o voice_selftest
 */

#include <stdio.h>
#include <string.h>
#include <math.h>
#include <dave/dave.h>
#include <opus/opus.h>
#include "ldv_transport.h"

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

    printf(failures ? "SELFTEST FAILED (%d)\n" : "SELFTEST PASSED\n", failures);
    return failures ? 1 : 0;
}
