//
//  NOZXAppleCompressionCoder.m
//  ZipUtilities
//
//  Created by Nolan O'Brien on 9/12/15.
//  Copyright © 2015 NSProgrammer. All rights reserved.
//

#import "NOZXAppleCompressionCoder.h"

#if COMPRESSION_LIB_AVAILABLE

@interface NOZXAppleCompressionCoderContext ()
@property (nonatomic) compression_stream_operation operation;
@property (nonatomic) compression_algorithm algorithm;
@property (nonatomic) UInt16 bitFlags;
@property (nonatomic, readonly, nonnull) compression_stream *stream;
@property (nonatomic, copy) NOZFlushCallback flushCallback;
@property (nonatomic, readonly) Byte *compressedDataBuffer;
@property (nonatomic, readonly) size_t compressedDataBufferSize;
@property (nonatomic) size_t compressedDataPosition;
@property (nonatomic) BOOL hasFinished;
@end

@implementation NOZXAppleCompressionCoder

+ (BOOL)isSupported
{
    NSProcessInfo *procInfo = [NSProcessInfo processInfo];
    if (![procInfo respondsToSelector:@selector(operatingSystemVersion)]) {
        return NO;
    }
    NSOperatingSystemVersion osVersion = procInfo.operatingSystemVersion;
#if TARGET_OS_IPHONE
    return osVersion.majorVersion >= 9;
#elif TARGET_OS_MAC
    return osVersion.majorVersion == 10 && osVersion.minorVersion >= 11;
#else
    return NO;
#endif
}

- (NOZXAppleCompressionCoderContext *)createContextForAlgorithm:(compression_algorithm)algorithm
                                                      operation:(compression_stream_operation)operation
                                                       bitFlags:(UInt16)bitFlags
                                                  flushCallback:(NOZFlushCallback)callback
{
    if (![[self class] isSupported]) {
        return nil;
    }

    NOZXAppleCompressionCoderContext *context = [[NOZXAppleCompressionCoderContext alloc] init];
    context.algorithm = algorithm;
    context.operation = operation;
    context.bitFlags = bitFlags;
    context.flushCallback = callback;
    return context;
}

- (BOOL)initializeWithContext:(NOZXAppleCompressionCoderContext *)context
{
    if (![[self class] isSupported]) {
        return NO;
    }

    if (COMPRESSION_STATUS_OK != compression_stream_init(context.stream,
                                                         context.operation,
                                                         context.algorithm)) {
        return NO;
    }

    context.stream->dst_ptr = context.compressedDataBuffer;
    context.stream->dst_size = context.compressedDataBufferSize;

    return YES;
}

- (BOOL)codeBytes:(const Byte*)bytes
           length:(size_t)length
            final:(BOOL)final
          context:(NOZXAppleCompressionCoderContext *)context
{
    if (![[self class] isSupported]) {
        return NO;
    }

    if (final && context.hasFinished) {
        return YES;
    }

    BOOL success = YES;

    compression_stream *stream = context.stream;
    stream->src_ptr = bytes;
    stream->src_size = length;

    do {
        size_t oldDstSize = stream->dst_size;
        compression_status status = compression_stream_process(stream, (final && stream->src_size == 0) ? COMPRESSION_STREAM_FINALIZE : 0);
        if (status < 0) {
            success = NO;
            break;
        }
        context.compressedDataPosition += oldDstSize - stream->dst_size;

        if (stream->dst_size == 0) {
            if (!context.flushCallback(self, context, context.compressedDataBuffer, context.compressedDataPosition)) {
                success = NO;
            }
            context.compressedDataPosition = 0;
            stream->dst_size = context.compressedDataBufferSize;
            stream->dst_ptr = context.compressedDataBuffer;
        }

        if (COMPRESSION_STATUS_END == status) {
            if (!context.flushCallback(self, context, context.compressedDataBuffer, context.compressedDataPosition)) {
                success = NO;
            }
            context.hasFinished = YES;
            break;
        }
    } while (success && (final || stream->src_size > 0));

    return success;
}

- (BOOL)finalizeWithContext:(NOZXAppleCompressionCoderContext *)context
{
    if (![[self class] isSupported]) {
        return NO;
    }

    BOOL success = [self codeBytes:NULL length:0 final:YES context:context];
    compression_stream_destroy(context.stream);
    context.flushCallback = nil;
    return success;
}

@end

@implementation NOZXAppleCompressionCoderContext
{
    compression_stream _stream;
}

- (instancetype)init
{
    if (self = [super init]) {
        _compressedDataBufferSize = NSPageSize();
        _compressedDataBuffer = malloc(_compressedDataBufferSize);
    }
    return self;
}

- (compression_stream *)stream
{
    return &_stream;
}

- (BOOL)encodedDataWasText
{
    return NO;
}

@end

#endif // COMPRESSION_LIB_AVAILABLE
