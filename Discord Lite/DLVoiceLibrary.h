//
//  DLVoiceLibrary.h
//  Legacy Discord
//
//  Loads libLegacyDiscordVoice.dylib (DAVE end-to-end encryption, Opus and
//  the transport cipher; built by scripts/build-voice-deps.sh) at run time.
//  The library targets OS X 10.8, so on 10.6 and 10.7 voice is unavailable
//  and nothing here is loaded; the app binary itself never links it.
//

#import <Foundation/Foundation.h>
#include "dave/dave.h"
#include "opus/opus.h"
#include "ldv_transport.h"

typedef struct {
    __typeof__(&daveMaxSupportedProtocolVersion) maxProtocolVersion;
    __typeof__(&daveFree) free;
    __typeof__(&daveSetLogSinkCallback) setLogSink;
    __typeof__(&daveSessionCreate) sessionCreate;
    __typeof__(&daveSessionDestroy) sessionDestroy;
    __typeof__(&daveSessionInit) sessionInit;
    __typeof__(&daveSessionReset) sessionReset;
    __typeof__(&daveSessionSetExternalSender) sessionSetExternalSender;
    __typeof__(&daveSessionProcessProposals) sessionProcessProposals;
    __typeof__(&daveSessionProcessCommit) sessionProcessCommit;
    __typeof__(&daveSessionProcessWelcome) sessionProcessWelcome;
    __typeof__(&daveSessionGetMarshalledKeyPackage) sessionGetKeyPackage;
    __typeof__(&daveSessionGetKeyRatchet) sessionGetKeyRatchet;
    __typeof__(&daveKeyRatchetDestroy) keyRatchetDestroy;
    __typeof__(&daveCommitResultIsFailed) commitIsFailed;
    __typeof__(&daveCommitResultIsIgnored) commitIsIgnored;
    __typeof__(&daveCommitResultGetRosterMemberIds) commitRosterIds;
    __typeof__(&daveCommitResultDestroy) commitDestroy;
    __typeof__(&daveWelcomeResultGetRosterMemberIds) welcomeRosterIds;
    __typeof__(&daveWelcomeResultDestroy) welcomeDestroy;
    __typeof__(&daveEncryptorCreate) encryptorCreate;
    __typeof__(&daveEncryptorDestroy) encryptorDestroy;
    __typeof__(&daveEncryptorSetKeyRatchet) encryptorSetKeyRatchet;
    __typeof__(&daveEncryptorSetPassthroughMode) encryptorSetPassthrough;
    __typeof__(&daveEncryptorAssignSsrcToCodec) encryptorAssignSsrc;
    __typeof__(&daveEncryptorGetMaxCiphertextByteSize) encryptorMaxCiphertext;
    __typeof__(&daveEncryptorEncrypt) encrypt;
    __typeof__(&daveDecryptorCreate) decryptorCreate;
    __typeof__(&daveDecryptorDestroy) decryptorDestroy;
    __typeof__(&daveDecryptorTransitionToKeyRatchet) decryptorSetKeyRatchet;
    __typeof__(&daveDecryptorTransitionToPassthroughMode) decryptorSetPassthrough;
    __typeof__(&daveDecryptorGetMaxPlaintextByteSize) decryptorMaxPlaintext;
    __typeof__(&daveDecryptorDecrypt) decrypt;
    __typeof__(&opus_encoder_create) opusEncoderCreate;
    __typeof__(&opus_encoder_destroy) opusEncoderDestroy;
    __typeof__(&opus_encode) opusEncode;
    __typeof__(&opus_decoder_create) opusDecoderCreate;
    __typeof__(&opus_decoder_destroy) opusDecoderDestroy;
    __typeof__(&opus_decode) opusDecode;
    __typeof__(&opus_get_version_string) opusVersion;
    __typeof__(&ldv_transport_seal) transportSeal;
    __typeof__(&ldv_transport_open) transportOpen;
} DLVoiceAPI;

@interface DLVoiceLibrary : NSObject

// The loaded API, or NULL when voice is unavailable (OS older than 10.8, or
// the library is missing from the bundle).
+(const DLVoiceAPI *)api;
// Why voice is unavailable, for logs and the UI.
+(NSString *)unavailableReason;

@end
