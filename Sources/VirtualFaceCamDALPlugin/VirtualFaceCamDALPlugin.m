#import <Foundation/Foundation.h>
#import <CoreFoundation/CFPlugInCOM.h>
#import <CoreMediaIO/CMIOHardwarePlugIn.h>
#import <CoreMediaIO/CMIOHardwareSystem.h>
#import <CoreMediaIO/CMIOHardwareObject.h>
#import <CoreMediaIO/CMIOHardwareDevice.h>
#import <CoreMediaIO/CMIOHardwareStream.h>
#import <CoreMedia/CMSimpleQueue.h>
#import <CoreMedia/CMFormatDescription.h>
#import <CoreMedia/CMSampleBuffer.h>
#import <CoreVideo/CVPixelBuffer.h>
#include <stdint.h>

typedef struct {
    CMIOHardwarePlugInInterface* interface;
    UInt32 refCount;
} VirtualDALPlugInRef;

static HRESULT PlugInQueryInterface(void* self, REFIID uuid, LPVOID* interface);
static ULONG PlugInAddRef(void* self);
static ULONG PlugInRelease(void* self);
static OSStatus PlugInInitialize(CMIOHardwarePlugInRef self);
static OSStatus PlugInInitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
static OSStatus PlugInTeardown(CMIOHardwarePlugInRef self);
static void PlugInObjectShow(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
static Boolean PlugInObjectHasProperty(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address);
static OSStatus PlugInObjectIsPropertySettable(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, Boolean* isSettable);
static OSStatus PlugInObjectGetPropertyDataSize(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* dataSize);
static OSStatus PlugInObjectGetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 dataSize, UInt32* dataUsed, void* data);
static OSStatus PlugInObjectSetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 dataSize, const void* data);
static OSStatus PlugInDeviceSuspend(CMIOHardwarePlugInRef self, CMIODeviceID device);
static OSStatus PlugInDeviceResume(CMIOHardwarePlugInRef self, CMIODeviceID device);
static OSStatus PlugInDeviceStartStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream);
static OSStatus PlugInDeviceStopStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream);
static OSStatus PlugInDeviceProcessAVCCommand(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIODeviceAVCCommand* ioAVCCommand);
static OSStatus PlugInDeviceProcessRS422Command(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIODeviceRS422Command* ioRS422Command);
static OSStatus PlugInStreamCopyBufferQueue(CMIOHardwarePlugInRef self, CMIOStreamID stream, CMIODeviceStreamQueueAlteredProc queueAlteredProc, void* queueAlteredRefCon, CMSimpleQueueRef* queue);
static OSStatus PlugInStreamDeckPlay(CMIOHardwarePlugInRef self, CMIOStreamID stream);
static OSStatus PlugInStreamDeckStop(CMIOHardwarePlugInRef self, CMIOStreamID stream);
static OSStatus PlugInStreamDeckJog(CMIOHardwarePlugInRef self, CMIOStreamID stream, SInt32 speed);
static OSStatus PlugInStreamDeckCueTo(CMIOHardwarePlugInRef self, CMIOStreamID stream, Float64 frameNumber, Boolean playOnCue);

static CMIOHardwarePlugInInterface gInterface = {
    ._reserved = NULL,
    .QueryInterface = PlugInQueryInterface,
    .AddRef = PlugInAddRef,
    .Release = PlugInRelease,
    .Initialize = PlugInInitialize,
    .InitializeWithObjectID = PlugInInitializeWithObjectID,
    .Teardown = PlugInTeardown,
    .ObjectShow = PlugInObjectShow,
    .ObjectHasProperty = PlugInObjectHasProperty,
    .ObjectIsPropertySettable = PlugInObjectIsPropertySettable,
    .ObjectGetPropertyDataSize = PlugInObjectGetPropertyDataSize,
    .ObjectGetPropertyData = PlugInObjectGetPropertyData,
    .ObjectSetPropertyData = PlugInObjectSetPropertyData,
    .DeviceSuspend = PlugInDeviceSuspend,
    .DeviceResume = PlugInDeviceResume,
    .DeviceStartStream = PlugInDeviceStartStream,
    .DeviceStopStream = PlugInDeviceStopStream,
    .DeviceProcessAVCCommand = PlugInDeviceProcessAVCCommand,
    .DeviceProcessRS422Command = PlugInDeviceProcessRS422Command,
    .StreamCopyBufferQueue = PlugInStreamCopyBufferQueue,
    .StreamDeckPlay = PlugInStreamDeckPlay,
    .StreamDeckStop = PlugInStreamDeckStop,
    .StreamDeckJog = PlugInStreamDeckJog,
    .StreamDeckCueTo = PlugInStreamDeckCueTo
};

static VirtualDALPlugInRef gPlugIn = {
    .interface = &gInterface,
    .refCount = 1
};

static CMIOObjectID gPlugInObjectID = kCMIOObjectUnknown;
static CMIOObjectID gDeviceObjectID = kCMIOObjectUnknown;
static CMIOObjectID gStreamObjectID = kCMIOObjectUnknown;
static Boolean gDeviceRunning = false;
static CMSimpleQueueRef gQueue = NULL;
static CMFormatDescriptionRef gFormatDescription = NULL;
static CMIODeviceStreamQueueAlteredProc gQueueAlteredProc = NULL;
static void* gQueueAlteredRefCon = NULL;
static dispatch_source_t gFrameTimer = NULL;
static dispatch_queue_t gFrameQueue = NULL;
static NSString* const kSharedFramePath = @"/tmp/virtualfacecam_frame.bin";

typedef struct {
    UInt32 magic;
    UInt32 width;
    UInt32 height;
    UInt32 bytesPerRow;
    UInt32 format;
    int64_t timeValue;
    int32_t timeScale;
} SharedFrameHeader;

static CFStringRef CopyCFString(CFStringRef str) {
    if (!str) { return NULL; }
    return (CFStringRef)CFRetain(str);
}

static void EnsureFormatDescription(void) {
    if (gFormatDescription != NULL) { return; }
    CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault,
        kCVPixelFormatType_32BGRA,
        1280,
        720,
        NULL,
        (CMVideoFormatDescriptionRef*)&gFormatDescription
    );
}

static CMSampleBufferRef CreateSampleBufferFromSharedFrame(void) {
    NSData* blob = [NSData dataWithContentsOfFile:kSharedFramePath];
    if (blob.length < sizeof(SharedFrameHeader)) { return NULL; }

    SharedFrameHeader header;
    [blob getBytes:&header length:sizeof(SharedFrameHeader)];
    if (header.magic != 0x5646434D || header.format != kCVPixelFormatType_32BGRA) {
        return NULL;
    }

    size_t payloadSize = blob.length - sizeof(SharedFrameHeader);
    size_t expectedSize = (size_t)header.bytesPerRow * (size_t)header.height;
    if (payloadSize < expectedSize || header.width == 0 || header.height == 0) {
        return NULL;
    }

    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary* attrs = @{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (__bridge NSString*)kCVPixelBufferWidthKey: @(header.width),
        (__bridge NSString*)kCVPixelBufferHeightKey: @(header.height),
        (__bridge NSString*)kCVPixelBufferBytesPerRowAlignmentKey: @(header.bytesPerRow),
        (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVReturn cvErr = CVPixelBufferCreate(
        kCFAllocatorDefault,
        header.width,
        header.height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &pixelBuffer
    );
    if (cvErr != kCVReturnSuccess || pixelBuffer == NULL) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    uint8_t* dst = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);
    const uint8_t* src = (const uint8_t*)blob.bytes + sizeof(SharedFrameHeader);
    if (!dst || !src) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CFRelease(pixelBuffer);
        return NULL;
    }
    size_t dstBpr = CVPixelBufferGetBytesPerRow(pixelBuffer);
    for (UInt32 y = 0; y < header.height; ++y) {
        memcpy(dst + y * dstBpr, src + y * header.bytesPerRow, MIN((size_t)header.bytesPerRow, dstBpr));
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus vdErr = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (vdErr != noErr || formatDesc == NULL) {
        CFRelease(pixelBuffer);
        return NULL;
    }

    CMTime pts = CMTimeMake(header.timeValue, header.timeScale > 0 ? header.timeScale : 30);
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = kCMTimeInvalid
    };

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus sbErr = CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        true,
        NULL,
        NULL,
        formatDesc,
        &timing,
        &sampleBuffer
    );
    CFRelease(formatDesc);
    CFRelease(pixelBuffer);
    if (sbErr != noErr) { return NULL; }
    return sampleBuffer;
}

static void EnqueueSharedFrameIfAvailable(void) {
    if (gQueue == NULL || !gDeviceRunning) { return; }
    CMSampleBufferRef sample = CreateSampleBufferFromSharedFrame();
    if (sample == NULL) { return; }

    while (CMSimpleQueueGetCount(gQueue) >= CMSimpleQueueGetCapacity(gQueue)) {
        const void* old = CMSimpleQueueDequeue(gQueue);
        if (old) { CFRelease(old); }
    }

    OSStatus err = CMSimpleQueueEnqueue(gQueue, sample);
    if (err == noErr) {
        if (gQueueAlteredProc != NULL) {
            gQueueAlteredProc(gStreamObjectID, (void*)sample, gQueueAlteredRefCon);
        }
    } else {
        CFRelease(sample);
    }
}

static void StartFrameTimerIfNeeded(void) {
    if (gFrameTimer != NULL) { return; }
    if (gFrameQueue == NULL) {
        gFrameQueue = dispatch_queue_create("com.virtualfacecam.dal.framequeue", DISPATCH_QUEUE_SERIAL);
    }
    gFrameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gFrameQueue);
    if (gFrameTimer == NULL) { return; }
    dispatch_source_set_timer(gFrameTimer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 30, NSEC_PER_MSEC * 2);
    dispatch_source_set_event_handler(gFrameTimer, ^{
        EnqueueSharedFrameIfAvailable();
    });
    dispatch_resume(gFrameTimer);
}

static void StopFrameTimer(void) {
    if (gFrameTimer != NULL) {
        dispatch_source_cancel(gFrameTimer);
        gFrameTimer = NULL;
    }
}

void *VirtualFaceCamDALPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    (void)allocator;
    if (typeID == NULL) {
        return NULL;
    }
    if (!CFEqual(typeID, kCMIOHardwarePlugInTypeID)) {
        return NULL;
    }
    gPlugIn.refCount = 1;
    return &gPlugIn;
}

static HRESULT PlugInQueryInterface(void* self, REFIID uuid, LPVOID* interface) {
    (void)self;
    if (interface == NULL) {
        return E_POINTER;
    }
    *interface = NULL;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, uuid);
    Boolean matches = (requested != NULL) && (CFEqual(requested, IUnknownUUID) || CFEqual(requested, kCMIOHardwarePlugInInterfaceID));
    if (requested != NULL) {
        CFRelease(requested);
    }
    if (matches) {
        *interface = &gPlugIn;
        PlugInAddRef(self);
        return S_OK;
    }
    return E_NOINTERFACE;
}

static ULONG PlugInAddRef(void* self) {
    (void)self;
    gPlugIn.refCount += 1;
    return gPlugIn.refCount;
}

static ULONG PlugInRelease(void* self) {
    (void)self;
    if (gPlugIn.refCount > 0) {
        gPlugIn.refCount -= 1;
    }
    return gPlugIn.refCount;
}

static OSStatus PlugInInitialize(CMIOHardwarePlugInRef self) {
    return PlugInInitializeWithObjectID(self, kCMIOObjectUnknown);
}

static OSStatus PlugInInitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID) {
    gPlugInObjectID = objectID;
    EnsureFormatDescription();

    if (gDeviceObjectID == kCMIOObjectUnknown) {
        OSStatus err = CMIOObjectCreate(self, gPlugInObjectID, kCMIODeviceClassID, &gDeviceObjectID);
        if (err != noErr) { return err; }
    }

    if (gStreamObjectID == kCMIOObjectUnknown) {
        OSStatus err = CMIOObjectCreate(self, gDeviceObjectID, kCMIOStreamClassID, &gStreamObjectID);
        if (err != noErr) { return err; }
    }

    CMIOObjectID publishDevice[] = { gDeviceObjectID };
    CMIOObjectID publishStream[] = { gStreamObjectID };
    OSStatus pubErr = CMIOObjectsPublishedAndDied(self, gPlugInObjectID, 1, publishDevice, 0, NULL);
    if (pubErr != noErr) { return pubErr; }
    return CMIOObjectsPublishedAndDied(self, gDeviceObjectID, 1, publishStream, 0, NULL);
}

static OSStatus PlugInTeardown(CMIOHardwarePlugInRef self) {
    StopFrameTimer();
    if (gQueue != NULL) {
        while (CMSimpleQueueGetCount(gQueue) > 0) {
            const void* old = CMSimpleQueueDequeue(gQueue);
            if (old) { CFRelease(old); }
        }
        CFRelease(gQueue);
        gQueue = NULL;
    }
    if (gFormatDescription != NULL) {
        CFRelease(gFormatDescription);
        gFormatDescription = NULL;
    }
    if (gStreamObjectID != kCMIOObjectUnknown) {
        CMIOObjectID deadStream[] = { gStreamObjectID };
        CMIOObjectsPublishedAndDied(self, gDeviceObjectID, 0, NULL, 1, deadStream);
        gStreamObjectID = kCMIOObjectUnknown;
    }
    if (gDeviceObjectID != kCMIOObjectUnknown) {
        CMIOObjectID deadDevice[] = { gDeviceObjectID };
        CMIOObjectsPublishedAndDied(self, gPlugInObjectID, 0, NULL, 1, deadDevice);
        gDeviceObjectID = kCMIOObjectUnknown;
    }
    gPlugInObjectID = kCMIOObjectUnknown;
    return noErr;
}

static void PlugInObjectShow(CMIOHardwarePlugInRef self, CMIOObjectID objectID) {
    (void)self;
    printf("VirtualFaceCamDAL object: %u\n", objectID);
}

static Boolean IsGlobalScope(const CMIOObjectPropertyAddress* address) {
    return (address->mScope == kCMIOObjectPropertyScopeGlobal || address->mScope == kCMIOObjectPropertyScopeWildcard);
}

static Boolean PlugInObjectHasProperty(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address) {
    (void)self;
    if (!address || !IsGlobalScope(address)) { return false; }

    if (objectID == kCMIOObjectSystemObject) {
        return address->mSelector == kCMIOHardwarePropertyDevices;
    }

    if (objectID == gPlugInObjectID) {
        switch (address->mSelector) {
            case kCMIOObjectPropertyClass:
            case kCMIOObjectPropertyName:
            case kCMIOObjectPropertyManufacturer:
            case kCMIOObjectPropertyOwnedObjects:
                return true;
            default:
                return false;
        }
    }

    if (objectID == gDeviceObjectID) {
        switch (address->mSelector) {
            case kCMIOObjectPropertyClass:
            case kCMIOObjectPropertyName:
            case kCMIOObjectPropertyManufacturer:
            case kCMIODevicePropertyDeviceUID:
            case kCMIODevicePropertyModelUID:
            case kCMIODevicePropertyStreams:
            case kCMIODevicePropertyDeviceIsAlive:
            case kCMIODevicePropertyDeviceIsRunning:
            case kCMIODevicePropertyDeviceIsRunningSomewhere:
            case kCMIODevicePropertyTransportType:
                return true;
            default:
                return false;
        }
    }

    if (objectID == gStreamObjectID) {
        switch (address->mSelector) {
            case kCMIOObjectPropertyClass:
            case kCMIOObjectPropertyName:
            case kCMIOStreamPropertyDirection:
            case kCMIOStreamPropertyFormatDescription:
            case kCMIOStreamPropertyFrameRate:
            case kCMIOStreamPropertyFrameRates:
                return true;
            default:
                return false;
        }
    }

    return false;
}

static OSStatus PlugInObjectIsPropertySettable(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, Boolean* isSettable) {
    (void)self; (void)objectID; (void)address;
    if (isSettable == NULL) { return kCMIOHardwareIllegalOperationError; }
    *isSettable = false;
    return noErr;
}

static OSStatus PlugInObjectGetPropertyDataSize(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* dataSize) {
    (void)self; (void)qualifierDataSize; (void)qualifierData;
    if (dataSize == NULL || address == NULL) { return kCMIOHardwareIllegalOperationError; }

    if (objectID == kCMIOObjectSystemObject && address->mSelector == kCMIOHardwarePropertyDevices) {
        *dataSize = sizeof(CMIOObjectID);
        return noErr;
    }
    if (objectID == gPlugInObjectID && address->mSelector == kCMIOObjectPropertyOwnedObjects) {
        *dataSize = sizeof(CMIOObjectID);
        return noErr;
    }
    if (objectID == gDeviceObjectID && address->mSelector == kCMIODevicePropertyStreams) {
        *dataSize = sizeof(CMIOObjectID);
        return noErr;
    }

    switch (address->mSelector) {
        case kCMIOObjectPropertyClass:
            *dataSize = sizeof(CMIOClassID);
            return noErr;
        case kCMIOObjectPropertyName:
        case kCMIOObjectPropertyManufacturer:
        case kCMIODevicePropertyDeviceUID:
        case kCMIODevicePropertyModelUID:
        case kCMIOStreamPropertyFormatDescription:
            *dataSize = sizeof(CFTypeRef);
            return noErr;
        case kCMIODevicePropertyDeviceIsAlive:
        case kCMIODevicePropertyDeviceIsRunning:
        case kCMIODevicePropertyDeviceIsRunningSomewhere:
            *dataSize = sizeof(UInt32);
            return noErr;
        case kCMIODevicePropertyTransportType:
        case kCMIOStreamPropertyDirection:
            *dataSize = sizeof(UInt32);
            return noErr;
        case kCMIOStreamPropertyFrameRate:
            *dataSize = sizeof(Float64);
            return noErr;
        case kCMIOStreamPropertyFrameRates:
            *dataSize = sizeof(Float64);
            return noErr;
        default:
            return kCMIOHardwareUnknownPropertyError;
    }
}

static OSStatus PlugInObjectGetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 dataSize, UInt32* dataUsed, void* data) {
    (void)self; (void)qualifierDataSize; (void)qualifierData;
    if (!address || !data || !dataUsed) { return kCMIOHardwareIllegalOperationError; }

    if (objectID == kCMIOObjectSystemObject && address->mSelector == kCMIOHardwarePropertyDevices) {
        if (dataSize < sizeof(CMIOObjectID)) { return kCMIOHardwareBadPropertySizeError; }
        ((CMIOObjectID*)data)[0] = gDeviceObjectID;
        *dataUsed = sizeof(CMIOObjectID);
        return noErr;
    }

    if (objectID == gPlugInObjectID && address->mSelector == kCMIOObjectPropertyOwnedObjects) {
        if (dataSize < sizeof(CMIOObjectID)) { return kCMIOHardwareBadPropertySizeError; }
        ((CMIOObjectID*)data)[0] = gDeviceObjectID;
        *dataUsed = sizeof(CMIOObjectID);
        return noErr;
    }

    if (objectID == gDeviceObjectID && address->mSelector == kCMIODevicePropertyStreams) {
        if (dataSize < sizeof(CMIOObjectID)) { return kCMIOHardwareBadPropertySizeError; }
        ((CMIOObjectID*)data)[0] = gStreamObjectID;
        *dataUsed = sizeof(CMIOObjectID);
        return noErr;
    }

    switch (address->mSelector) {
        case kCMIOObjectPropertyClass: {
            if (dataSize < sizeof(CMIOClassID)) { return kCMIOHardwareBadPropertySizeError; }
            CMIOClassID classID = kCMIOObjectClassID;
            if (objectID == gPlugInObjectID) { classID = kCMIOPlugInClassID; }
            else if (objectID == gDeviceObjectID) { classID = kCMIODeviceClassID; }
            else if (objectID == gStreamObjectID) { classID = kCMIOStreamClassID; }
            *((CMIOClassID*)data) = classID;
            *dataUsed = sizeof(CMIOClassID);
            return noErr;
        }
        case kCMIOObjectPropertyName: {
            if (dataSize < sizeof(CFStringRef)) { return kCMIOHardwareBadPropertySizeError; }
            CFStringRef value = CFSTR("VirtualFaceCam");
            if (objectID == gStreamObjectID) { value = CFSTR("VirtualFaceCam Stream"); }
            *((CFStringRef*)data) = CopyCFString(value);
            *dataUsed = sizeof(CFStringRef);
            return noErr;
        }
        case kCMIOObjectPropertyManufacturer: {
            if (dataSize < sizeof(CFStringRef)) { return kCMIOHardwareBadPropertySizeError; }
            *((CFStringRef*)data) = CopyCFString(CFSTR("VirtualFaceCam"));
            *dataUsed = sizeof(CFStringRef);
            return noErr;
        }
        case kCMIODevicePropertyDeviceUID: {
            if (dataSize < sizeof(CFStringRef)) { return kCMIOHardwareBadPropertySizeError; }
            *((CFStringRef*)data) = CopyCFString(CFSTR("com.virtualfacecam.device.main"));
            *dataUsed = sizeof(CFStringRef);
            return noErr;
        }
        case kCMIODevicePropertyModelUID: {
            if (dataSize < sizeof(CFStringRef)) { return kCMIOHardwareBadPropertySizeError; }
            *((CFStringRef*)data) = CopyCFString(CFSTR("com.virtualfacecam.model.v1"));
            *dataUsed = sizeof(CFStringRef);
            return noErr;
        }
        case kCMIODevicePropertyDeviceIsAlive:
        case kCMIODevicePropertyDeviceIsRunning:
        case kCMIODevicePropertyDeviceIsRunningSomewhere: {
            if (dataSize < sizeof(UInt32)) { return kCMIOHardwareBadPropertySizeError; }
            *((UInt32*)data) = gDeviceRunning ? 1 : 0;
            *dataUsed = sizeof(UInt32);
            return noErr;
        }
        case kCMIODevicePropertyTransportType: {
            if (dataSize < sizeof(UInt32)) { return kCMIOHardwareBadPropertySizeError; }
            *((UInt32*)data) = 'virt';
            *dataUsed = sizeof(UInt32);
            return noErr;
        }
        case kCMIOStreamPropertyDirection: {
            if (dataSize < sizeof(UInt32)) { return kCMIOHardwareBadPropertySizeError; }
            *((UInt32*)data) = 0; // input stream from device to client
            *dataUsed = sizeof(UInt32);
            return noErr;
        }
        case kCMIOStreamPropertyFormatDescription: {
            if (dataSize < sizeof(CMFormatDescriptionRef)) { return kCMIOHardwareBadPropertySizeError; }
            EnsureFormatDescription();
            *((CMFormatDescriptionRef*)data) = (CMFormatDescriptionRef)CFRetain(gFormatDescription);
            *dataUsed = sizeof(CMFormatDescriptionRef);
            return noErr;
        }
        case kCMIOStreamPropertyFrameRate: {
            if (dataSize < sizeof(Float64)) { return kCMIOHardwareBadPropertySizeError; }
            *((Float64*)data) = 30.0;
            *dataUsed = sizeof(Float64);
            return noErr;
        }
        case kCMIOStreamPropertyFrameRates: {
            if (dataSize < sizeof(Float64)) { return kCMIOHardwareBadPropertySizeError; }
            ((Float64*)data)[0] = 30.0;
            *dataUsed = sizeof(Float64);
            return noErr;
        }
        default:
            return kCMIOHardwareUnknownPropertyError;
    }
}

static OSStatus PlugInObjectSetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 dataSize, const void* data) {
    (void)self; (void)objectID; (void)address; (void)qualifierDataSize; (void)qualifierData; (void)dataSize; (void)data;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInDeviceSuspend(CMIOHardwarePlugInRef self, CMIODeviceID device) {
    (void)self; (void)device;
    gDeviceRunning = false;
    return noErr;
}

static OSStatus PlugInDeviceResume(CMIOHardwarePlugInRef self, CMIODeviceID device) {
    (void)self; (void)device;
    return noErr;
}

static OSStatus PlugInDeviceStartStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream) {
    (void)self;
    if (device != gDeviceObjectID || stream != gStreamObjectID) {
        return kCMIOHardwareBadObjectError;
    }
    gDeviceRunning = true;
    StartFrameTimerIfNeeded();
    return noErr;
}

static OSStatus PlugInDeviceStopStream(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIOStreamID stream) {
    (void)self;
    if (device != gDeviceObjectID || stream != gStreamObjectID) {
        return kCMIOHardwareBadObjectError;
    }
    gDeviceRunning = false;
    StopFrameTimer();
    return noErr;
}

static OSStatus PlugInDeviceProcessAVCCommand(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIODeviceAVCCommand* ioAVCCommand) {
    (void)self; (void)device; (void)ioAVCCommand;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInDeviceProcessRS422Command(CMIOHardwarePlugInRef self, CMIODeviceID device, CMIODeviceRS422Command* ioRS422Command) {
    (void)self; (void)device; (void)ioRS422Command;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInStreamCopyBufferQueue(CMIOHardwarePlugInRef self, CMIOStreamID stream, CMIODeviceStreamQueueAlteredProc queueAlteredProc, void* queueAlteredRefCon, CMSimpleQueueRef* queue) {
    (void)self; (void)queueAlteredProc; (void)queueAlteredRefCon;
    if (stream != gStreamObjectID || queue == NULL) {
        return kCMIOHardwareIllegalOperationError;
    }
    if (gQueue == NULL) {
        CMSimpleQueueCreate(kCFAllocatorDefault, 32, &gQueue);
    }
    gQueueAlteredProc = queueAlteredProc;
    gQueueAlteredRefCon = queueAlteredRefCon;
    *queue = (CMSimpleQueueRef)CFRetain(gQueue);
    return noErr;
}

static OSStatus PlugInStreamDeckPlay(CMIOHardwarePlugInRef self, CMIOStreamID stream) {
    (void)self; (void)stream;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInStreamDeckStop(CMIOHardwarePlugInRef self, CMIOStreamID stream) {
    (void)self; (void)stream;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInStreamDeckJog(CMIOHardwarePlugInRef self, CMIOStreamID stream, SInt32 speed) {
    (void)self; (void)stream; (void)speed;
    return kCMIOHardwareIllegalOperationError;
}

static OSStatus PlugInStreamDeckCueTo(CMIOHardwarePlugInRef self, CMIOStreamID stream, Float64 frameNumber, Boolean playOnCue) {
    (void)self; (void)stream; (void)frameNumber; (void)playOnCue;
    return kCMIOHardwareIllegalOperationError;
}
