#import <mach/mach.h>
#import "SampleHandler.h"

NSString *failReasonByPolicy = @"Screen sharing isn't allowed in your org.";
NSString *failReasonByRole = @"Only presenters and meeting organizers can share screen.";
NSString *failReasonNoCall = @"You're not in a call or meeting. Start one to share your screen.";
NSString *failureReasonStoppedRemotelyScreenSharing = @"Someone else started sharing.";
NSString *failureReasonStoppedScreenSharing = @"You have stopped screen sharing";
NSString *failureReasonStandardDefaults = @"Screen sharing not initialized";


static NSString *const TSErrorDomain = @"com.yourappdomain.yourappname.ErrorDomain";
static NSString *const AXPkApplicationGroupIdentifierKey = @"AXPApplicationGroupIdentifier";

// DO NOT CHANGE: Hard coded string constants from the video team.
static NSString *const TSkScreenShareImageDataKey = @"image_data";
static NSString *const TSkScreenShareImageOrientationKey = @"image_orientation";
static NSString *const TSkScreenShareImageWidthKey = @"image_width";
static NSString *const TSkScreenShareImageHeightKey = @"image_height";
static NSString *const TSkScreenShareImageStrideKey = @"image_stride";
static NSString *const TSkScreenShareStart = @"sharing_started";
static NSString *const TSkScreenShareStop = @"sharing_stopped";
static NSString *const TSkScreenShareFrameReady = @"frame_ready";

// DO NOT CHANGE: Hard coded string for notification between the app and this extension
static NSString *const TSkScreenShareFrameDroppedOOM = @"ss_frame_dropped_oom";
static NSString *const TSkScreenShareFrameDroppedFPS = @"ss_frame_dropped_fps";
static NSString *const TSkScreenShareSendingStop = @"ss_sending_stopped";
static NSString *const TSkScreenShareSendingStopRemotely = @"ss_sending_stopped_remotely";
static NSString *const TSkScreenShareImageOrientation0= @"ss_image_orientation_0";
static NSString *const TSkScreenShareImageOrientation90Clockwise= @"ss_image_orientation_90clockwise";
static NSString *const TSkScreenShareImageOrientation270Clockwise= @"ss_image_orientation_270clockwise";
static NSString *const TSkScreenShareImageOrientation180= @"ss_image_orientation_180";

// Only allow share extension to run when there is a ongoing team call
static NSString *const TSkCanShareScreenToClient= @"canShareScreenToClient";
static NSString *const TSkIsScreenShareEnabledByOrgPolicy= @"isScreenShareEnabledByOrgPolicy";
static NSString *const TSkIsScreenShareEnabledByMeetingRole = @"isScreenShareEnabledByMeetingRole";

// We choose some conservative value here based on experiments
static float const TSkMaxScreenShareMemoryCapInMBytes = 40.f;
static float const TSkPanicScreenShareMemoryCapInMBytes = 30.f;
// Video pipeline only support up to 15FPS for ScreenShare scenario
static unsigned long const TSkMaxScreenShareFrameRate = 15;
static unsigned long const TSkOneMBInBytes = 1024 * 1024;

static SampleHandler *handler;

static NSDate *lastFrameTime;
static NSDate *lastFrameSkipLogTime;

static CIContext *ciContext;
static NSNumber *previousOrientation;

@interface SampleHandler ()

@property (nonatomic, assign) uint maxResolutionCap;
@property (nonatomic, assign) float frame_internal_seconds;
@property (nonatomic, assign) float curFrameSizeInMBytes;
@property (nonatomic, assign) float rawFrameSizeInMBytes;
@property (nonatomic, assign) float maxScreenShareMemoryCapInMBytes;
@property (nonatomic, assign) float panicScreenShareMemoryCapInMBytes;
@property (nonatomic, assign) BOOL panicMode;
@property (nonatomic, assign) BOOL canShareScreenToClient;
@property (nonatomic, assign) BOOL isScreenShareEnabledByOrgPolicy;
@property (nonatomic, assign) BOOL isScreenShareEnabledByMeetingRole;

@end

@implementation SampleHandler

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *, NSObject *> *)setupInfo
{
    // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
    
    // TODO: add hockeyapp support here
    
    // Cached the handler reference
    handler = self;
    
    NSString *suiteName = [[NSBundle mainBundle] objectForInfoDictionaryKey:AXPkApplicationGroupIdentifierKey];
    if (!suiteName)
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           @synchronized(self) {
                               NSDictionary *info = @{ NSLocalizedFailureReasonErrorKey : failureReasonStandardDefaults};
                               [handler finishBroadcastWithError:[[NSError alloc] initWithDomain:TSErrorDomain
                                                                                            code:0
                                                                                        userInfo:info]];
                           }
                       });
        return;
    }
    
    sharedUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    frameData = [NSMutableData data];
    
    _canShareScreenToClient = [sharedUserDefaults boolForKey:TSkCanShareScreenToClient];
    _isScreenShareEnabledByOrgPolicy = [sharedUserDefaults boolForKey:TSkIsScreenShareEnabledByOrgPolicy];
    _isScreenShareEnabledByMeetingRole = [sharedUserDefaults boolForKey:TSkIsScreenShareEnabledByMeetingRole];
    if (!_canShareScreenToClient || !_isScreenShareEnabledByOrgPolicy || !_isScreenShareEnabledByMeetingRole) {
        // We have to delay a bit the stopping here since via testing
        // If we stop immediately, iOS system level seems having problem tearing down the recording pipeline
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           @synchronized(self) {
                               NSString *errorInfo = nil;
                               if (!self.canShareScreenToClient)
                               {
                                   errorInfo = failReasonNoCall;
                               }
                               else if (!self.isScreenShareEnabledByOrgPolicy)
                               {
                                   errorInfo = failReasonByPolicy;
                               }
                               else if (!self.isScreenShareEnabledByMeetingRole)
                               {
                                   errorInfo = failReasonByRole;
                               }
                               NSDictionary *info = @{ NSLocalizedFailureReasonErrorKey : errorInfo != nil ? errorInfo : [NSNull null]};
                               [handler finishBroadcastWithError:[[NSError alloc] initWithDomain:TSErrorDomain
                                                                                            code:0
                                                                                        userInfo:info]];
                           }
                       });
        return;
    }
    
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL, onScreenShareSendingStopReceived, (__bridge CFStringRef)TSkScreenShareSendingStop, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, onScreenShareSendingStopRemotelyReceived, (__bridge CFStringRef)TSkScreenShareSendingStopRemotely, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    
    [self postNotification:TSkScreenShareStart];
    _frame_internal_seconds = 1.0f / TSkMaxScreenShareFrameRate;
    
    uint memory = (uint)([NSProcessInfo processInfo].physicalMemory / TSkOneMBInBytes);
    
    _maxScreenShareMemoryCapInMBytes = TSkMaxScreenShareMemoryCapInMBytes;
    _panicScreenShareMemoryCapInMBytes = TSkPanicScreenShareMemoryCapInMBytes;
    
    if (memory < 1500)
    {
        // for 1GB iOS device, cap the resolution to be 640
        _maxResolutionCap = 640;
    }
    else if (memory < 2500)
    {
        // for > 2GB device, resolution is capped to be 960 to be aligned with video pipeline support
        _maxResolutionCap = 960;
    }
    else
    {
        _maxResolutionCap = 1280;
        // for > 2G device, e.g., iphone 8 and above, we loose a bit the memory limit
        _maxScreenShareMemoryCapInMBytes = TSkMaxScreenShareMemoryCapInMBytes * 2;
        _panicScreenShareMemoryCapInMBytes = TSkPanicScreenShareMemoryCapInMBytes * 2;
    }
    
    _panicMode = NO;
    ciContext = [CIContext context];
}

- (void)broadcastPaused
{
    // User has requested to pause the broadcast. Samples will stop being delivered.
}

- (void)broadcastResumed
{
    // User has requested to resume the broadcast. Samples delivery will resume.
}

- (void)broadcastFinished
{
    // Only User request the stop, this will be triggerred
    // Per experiment + Per document, finishBroadcastWithError wont hit here
    // Only finishBroadcast will hit here
    [self postNotification:TSkScreenShareStop];
    [self cleanupResources];
}

- (void) cleanupResources {
    [sharedUserDefaults removeObjectForKey:TSkScreenShareImageDataKey];
    [sharedUserDefaults removeObjectForKey:TSkScreenShareImageWidthKey];
    [sharedUserDefaults removeObjectForKey:TSkScreenShareImageHeightKey];
    [sharedUserDefaults removeObjectForKey:TSkScreenShareImageStrideKey];
    [sharedUserDefaults removeObjectForKey:TSkScreenShareImageOrientationKey];
    frameData = nil;
    lastFrameTime = nil;
    lastFrameSkipLogTime = nil;
    previousOrientation = nil;
    ciContext = nil;
    
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveObserver(center, NULL, (__bridge CFStringRef)TSkScreenShareSendingStop, NULL);
    CFNotificationCenterRemoveObserver(center, NULL, (__bridge CFStringRef)TSkScreenShareSendingStopRemotely, NULL);
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType
{
    switch (sampleBufferType)
    {
        case RPSampleBufferTypeVideo:
        {
            // Handle video sample buffer
            @autoreleasepool
            {
                @synchronized(self)
                {
                    if (![self shoudSkipFrame] && _canShareScreenToClient)
                    {
                        CGSize maxSize = CGSizeZero;
                        CVPixelBufferRef orgPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                        size_t orgWidth = CVPixelBufferGetWidth(orgPixelBuffer);
                        size_t orgHeight = CVPixelBufferGetHeight(orgPixelBuffer);
                        
                        
                        if (orgWidth <= 0 || orgHeight <= 0)
                        {
                            // if orgWidth and orgHeight <= 0 something wrong, we do nothing
                            return;
                        }
                        
                        // Keep the aspect ratio but make the longer side to be _maxResolutionCap
                        if (orgWidth > orgHeight)
                        {
                            size_t maxHeight = orgHeight * _maxResolutionCap / orgWidth;
                            // Make sure height is divisble by 2
                            maxSize = CGSizeMake(_maxResolutionCap, maxHeight >> 1 << 1);
                        }
                        else
                        {
                            size_t maxWidth = orgWidth * _maxResolutionCap / orgHeight;
                            // Make sure width is divisble by 2
                            maxSize = CGSizeMake(maxWidth >> 1 << 1, _maxResolutionCap);
                        }
                        
                        // Resize using CoreImage
                        CVPixelBufferRef pixelBuffer = resizePixelBuffer(orgPixelBuffer, maxSize, ciContext);
                        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
                        
                        // Update frame size
                        size_t width = CVPixelBufferGetWidth(pixelBuffer);
                        size_t height = CVPixelBufferGetHeight(pixelBuffer);
                        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
                        if (width == 0 || height == 0 || stride == 0)
                        {
                            // if width/height/stride == 0 something wrong, we do nothing
                            CVPixelBufferRelease(pixelBuffer);
                            return;
                        }
                        
                        
                        // Remove the Object here might not means recycling the memory while we have no idea when OS will recyle this part
                        [sharedUserDefaults removeObjectForKey:TSkScreenShareImageDataKey];
                        
                        if (@available(iOS 11, *))
                        {
                            // Update frame orientation
                            NSNumber *orientationAttachment = (__bridge NSNumber *)CMGetAttachment(sampleBuffer, (CFStringRef)RPVideoSampleOrientationKey, nil);
                            NSNumber *orientation = orientationAttachment ?: [NSNumber numberWithInteger:1];
                            [self updateOrientationIfNeeded:orientation];
                            [sharedUserDefaults setInteger:orientation.integerValue forKey:TSkScreenShareImageOrientationKey];
                        }
                        
                        [sharedUserDefaults setInteger:width forKey:TSkScreenShareImageWidthKey];
                        [sharedUserDefaults setInteger:height forKey:TSkScreenShareImageHeightKey];
                        [sharedUserDefaults setInteger:stride forKey:TSkScreenShareImageStrideKey];
                        
                        // Update frame buffer
                        size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
                        NSUInteger location = 0;
                        for (int plane = 0; plane < planeCount; plane++)
                        {
                            void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane);
                            size_t planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane);
                            size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane);
                            NSUInteger totalBytes = (int)planeHeight * (int)bytesPerRow;
                            [frameData replaceBytesInRange:NSMakeRange(location, totalBytes) withBytes:baseAddress];
                            location += totalBytes;
                        }
                        
                        _curFrameSizeInMBytes = (float) location / TSkOneMBInBytes;
                        _rawFrameSizeInMBytes = _curFrameSizeInMBytes * orgWidth / width;
                        
                        [sharedUserDefaults setObject:frameData forKey:TSkScreenShareImageDataKey];
                        [self postNotification:TSkScreenShareFrameReady];
                        
                        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                        // Recyle this part, otherwise, leak.
                        CVPixelBufferRelease(pixelBuffer);
                    }
                }
            }
        }
            
            break;
        case RPSampleBufferTypeAudioApp:
            // Handle audio sample buffer for app audio
            break;
        case RPSampleBufferTypeAudioMic:
            // Handle audio sample buffer for mic audio
            break;
            
        default:
            break;
    }
}

- (void)updateOrientationIfNeeded:(NSNumber *)orientation
{
    if (orientation && ![orientation isEqual:previousOrientation])
    {
        previousOrientation = orientation;
        switch (orientation.integerValue)
        {
            case 6:
                [self postNotification:TSkScreenShareImageOrientation90Clockwise];
                break;
            case 8:
                [self postNotification:TSkScreenShareImageOrientation270Clockwise];
                break;
            case 3:
                [self postNotification:TSkScreenShareImageOrientation180];
                break;
            default:
                [self postNotification:TSkScreenShareImageOrientation0];
                break;
        }
    }
}

- (void)postNotification:(nullable NSString*)identifier
{
    CFNotificationCenterRef notification = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(notification, (__bridge CFStringRef)identifier, NULL, NULL, YES);
}

- (BOOL)shoudSkipFrame
{
    NSDate *now = [NSDate new];
    double seconds = [now timeIntervalSinceDate:lastFrameTime];
    // Panic mode have to continue skip frame for 5 seconds;
    // We wont drop the very first frame
    if (lastFrameTime)
    {
        if (_panicMode)
        {
            if (seconds > 5)
            {
                _panicMode = NO;
            }
            else
            {
                return YES;
            }
        }
        
        // Per experiment, TASK_VM_INFO_COUNT is more dynamic/sensitive than MACH_TASK_BASIC_INFO_COUNT for dynamic memory change
        // It is more aligned with what we see at the Xcode debugger/profiler
        task_vm_info_data_t vmInfo;
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        kern_return_t kernelReturn = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vmInfo, &count);
        if (kernelReturn == KERN_SUCCESS)
        {
            float curMemUsageInMBytes = (double)vmInfo.phys_footprint / TSkOneMBInBytes;
            
            // Per experiment, iOS at low end devices, seems to have a big spike on cpu usage when opening other app / multi tasking.
            // which will result on no input to ext part for few seconds and after that a sudden flush of a lot of frames
            // We need to react very fast when we see the hint of this happening, thus, "Panic" mode, skip frame in this case for 5 seconds
            if (curMemUsageInMBytes > _panicScreenShareMemoryCapInMBytes)
            {
                _panicMode = YES;
                lastFrameTime = now;
                return YES;
            }
            
            if (_rawFrameSizeInMBytes > 0) {
                float maxSustainableFps = (_maxScreenShareMemoryCapInMBytes - curMemUsageInMBytes - _curFrameSizeInMBytes) / (_rawFrameSizeInMBytes);
                if (maxSustainableFps > 0)
                {
                    _frame_internal_seconds = 1.0f / MIN(maxSustainableFps, TSkMaxScreenShareFrameRate);
                }
                else
                {
                    _frame_internal_seconds = 5;
                }
            } else {
                // If RawFrameSize <= 0, something wrong, just skip the frame
                return YES;
            }
        }
        
        if (seconds < _frame_internal_seconds)
        {
            // Only notify main app to log such information once every 3 seconds
            if (!lastFrameSkipLogTime || fabs([lastFrameSkipLogTime timeIntervalSinceNow]) > 3)
            {
                [self postNotification:TSkScreenShareFrameDroppedFPS];
                lastFrameSkipLogTime = [NSDate date];
            }
            return YES;
        }
    }
    
    lastFrameTime = now;
    return NO;
}

void onScreenShareSendingStopReceived(CFNotificationCenterRef postingCenter,
                                      void * observer,
                                      CFStringRef name,
                                      void const * object,
                                      CFDictionaryRef userInfo)
{
    @synchronized(handler)
    {
        NSDictionary *info = @{ NSLocalizedFailureReasonErrorKey : failureReasonStoppedScreenSharing };
        [handler finishBroadcastWithError:[[NSError alloc] initWithDomain:TSErrorDomain
                                                                     code:0
                                                                 userInfo:info]];
        [handler cleanupResources];
    }
}

void onScreenShareSendingStopRemotelyReceived(CFNotificationCenterRef postingCenter,
                                              void * observer,
                                              CFStringRef name,
                                              void const * object,
                                              CFDictionaryRef userInfo)
{
    @synchronized(handler)
    {
        NSDictionary *info = @{ NSLocalizedFailureReasonErrorKey : failureReasonStoppedRemotelyScreenSharing };
        [handler finishBroadcastWithError:[[NSError alloc] initWithDomain:TSErrorDomain
                                                                     code:0
                                                                 userInfo:info]];
        [handler cleanupResources];
    }
}

CVPixelBufferRef resizePixelBuffer(CVPixelBufferRef pixelBuffer,
                                   CGSize scaleSize,
                                   CIContext *context) {
    // autoreleasepool for CIImage, for PixelBuffer will be released externally.
    @autoreleasepool {
        CIImage *image = [CIImage imageWithCVImageBuffer:pixelBuffer];
        CGFloat orgWidth = CGRectGetWidth(image.extent);
        CGFloat orgHeight = CGRectGetHeight(image.extent);
        
        CGFloat scaleX = scaleSize.width / orgWidth;
        CGFloat scaleY = scaleSize.height / orgHeight;
        
        image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
        image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x, -image.extent.origin.y)];
        
        CVPixelBufferRef output = NULL;
        
        CVPixelBufferCreate(nil,
                            scaleSize.width,
                            scaleSize.height,
                            CVPixelBufferGetPixelFormatType(pixelBuffer),
                            nil,
                            &output);
        
        if (output != NULL)
        {
            [context render:image toCVPixelBuffer:output];
        }
        return output;
    }
}

@end

