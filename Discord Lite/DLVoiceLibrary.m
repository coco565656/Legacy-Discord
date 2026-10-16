//
//  DLVoiceLibrary.m
//  Legacy Discord
//

#import "DLVoiceLibrary.h"
#import <AppKit/AppKit.h>
#include <dlfcn.h>

static DLVoiceAPI voiceAPI;
static BOOL voiceLoaded = NO;
static NSString *voiceUnavailableReason = nil;

// libdave logs every MLS step, including key packages; keep only warnings
// and errors, and never the payloads.
static void DLVoiceLogSink(DAVELoggingSeverity severity, const char *file, int line, const char *message) {
    if (severity < DAVE_LOGGING_SEVERITY_WARNING) return;
    NSLog(@"DAVE %s:%d %s", file ? file : "", line, message ? message : "");
}

@implementation DLVoiceLibrary

+(BOOL)systemSupportsVoice {
    // NSAppKitVersionNumber10_8 is 1187.
    return floor(NSAppKitVersionNumber) >= 1187;
}

+(void)loadLibrary {
    static BOOL attempted = NO;
    if (attempted) return;
    attempted = YES;
    if (![self systemSupportsVoice]) {
        voiceUnavailableReason = [@"Voice requires OS X 10.8 or later." retain];
        return;
    }
    NSString *path = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"libLegacyDiscordVoice.dylib"];
    void *handle = dlopen([path fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *error = dlerror();
        voiceUnavailableReason = [[NSString stringWithFormat:@"The voice library could not be loaded (%s).", error ? error : "unknown error"] retain];
        NSLog(@"%@", voiceUnavailableReason);
        return;
    }
#define DLVOICE_BIND(field, symbol) \
    voiceAPI.field = (__typeof__(voiceAPI.field))dlsym(handle, #symbol); \
    if (!voiceAPI.field) { \
        voiceUnavailableReason = [[NSString stringWithFormat:@"The voice library is missing %s.", #symbol] retain]; \
        NSLog(@"%@", voiceUnavailableReason); \
        return; \
    }
    DLVOICE_BIND(maxProtocolVersion, daveMaxSupportedProtocolVersion)
    DLVOICE_BIND(free, daveFree)
    DLVOICE_BIND(setLogSink, daveSetLogSinkCallback)
    DLVOICE_BIND(sessionCreate, daveSessionCreate)
    DLVOICE_BIND(sessionDestroy, daveSessionDestroy)
    DLVOICE_BIND(sessionInit, daveSessionInit)
    DLVOICE_BIND(sessionReset, daveSessionReset)
    DLVOICE_BIND(sessionSetExternalSender, daveSessionSetExternalSender)
    DLVOICE_BIND(sessionProcessProposals, daveSessionProcessProposals)
    DLVOICE_BIND(sessionProcessCommit, daveSessionProcessCommit)
    DLVOICE_BIND(sessionProcessWelcome, daveSessionProcessWelcome)
    DLVOICE_BIND(sessionGetKeyPackage, daveSessionGetMarshalledKeyPackage)
    DLVOICE_BIND(sessionGetKeyRatchet, daveSessionGetKeyRatchet)
    DLVOICE_BIND(keyRatchetDestroy, daveKeyRatchetDestroy)
    DLVOICE_BIND(commitIsFailed, daveCommitResultIsFailed)
    DLVOICE_BIND(commitIsIgnored, daveCommitResultIsIgnored)
    DLVOICE_BIND(commitRosterIds, daveCommitResultGetRosterMemberIds)
    DLVOICE_BIND(commitDestroy, daveCommitResultDestroy)
    DLVOICE_BIND(welcomeRosterIds, daveWelcomeResultGetRosterMemberIds)
    DLVOICE_BIND(welcomeDestroy, daveWelcomeResultDestroy)
    DLVOICE_BIND(encryptorCreate, daveEncryptorCreate)
    DLVOICE_BIND(encryptorDestroy, daveEncryptorDestroy)
    DLVOICE_BIND(encryptorSetKeyRatchet, daveEncryptorSetKeyRatchet)
    DLVOICE_BIND(encryptorSetPassthrough, daveEncryptorSetPassthroughMode)
    DLVOICE_BIND(encryptorAssignSsrc, daveEncryptorAssignSsrcToCodec)
    DLVOICE_BIND(encryptorMaxCiphertext, daveEncryptorGetMaxCiphertextByteSize)
    DLVOICE_BIND(encrypt, daveEncryptorEncrypt)
    DLVOICE_BIND(decryptorCreate, daveDecryptorCreate)
    DLVOICE_BIND(decryptorDestroy, daveDecryptorDestroy)
    DLVOICE_BIND(decryptorSetKeyRatchet, daveDecryptorTransitionToKeyRatchet)
    DLVOICE_BIND(decryptorSetPassthrough, daveDecryptorTransitionToPassthroughMode)
    DLVOICE_BIND(decryptorMaxPlaintext, daveDecryptorGetMaxPlaintextByteSize)
    DLVOICE_BIND(decrypt, daveDecryptorDecrypt)
    DLVOICE_BIND(opusEncoderCreate, opus_encoder_create)
    DLVOICE_BIND(opusEncoderDestroy, opus_encoder_destroy)
    DLVOICE_BIND(opusEncode, opus_encode)
    DLVOICE_BIND(opusDecoderCreate, opus_decoder_create)
    DLVOICE_BIND(opusDecoderDestroy, opus_decoder_destroy)
    DLVOICE_BIND(opusDecode, opus_decode)
    DLVOICE_BIND(opusVersion, opus_get_version_string)
    DLVOICE_BIND(transportSeal, ldv_transport_seal)
    DLVOICE_BIND(transportOpen, ldv_transport_open)
#undef DLVOICE_BIND
    voiceAPI.setLogSink(DLVoiceLogSink);
    voiceLoaded = YES;
    NSLog(@"Voice library loaded: DAVE v%u, %s", voiceAPI.maxProtocolVersion(), voiceAPI.opusVersion());
}

+(const DLVoiceAPI *)api {
    [self loadLibrary];
    return voiceLoaded ? &voiceAPI : NULL;
}

+(NSString *)unavailableReason {
    [self loadLibrary];
    return voiceLoaded ? nil : voiceUnavailableReason;
}

@end
