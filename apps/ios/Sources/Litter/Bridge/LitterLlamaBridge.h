#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LitterLlamaBridge : NSObject
+ (BOOL)isAvailable;
+ (BOOL)supportsTurboQuant;
+ (NSArray<NSString *> *)supportedKVCacheModes;
+ (nullable NSString *)generateWithModelPath:(NSString *)modelPath
                               contextTokens:(NSInteger)contextTokens
                                    maxTokens:(NSInteger)maxTokens
                                  temperature:(double)temperature
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString *token))onToken
                                        error:(NSError **)error;
+ (nullable NSString *)generateWithModelPath:(NSString *)modelPath
                               contextTokens:(NSInteger)contextTokens
                                    maxTokens:(NSInteger)maxTokens
                                  temperature:(double)temperature
                                         topP:(double)topP
                                         topK:(NSInteger)topK
                                  repeatLastN:(NSInteger)repeatLastN
                                repeatPenalty:(double)repeatPenalty
                              frequencyPenalty:(double)frequencyPenalty
                                presencePenalty:(double)presencePenalty
                                         seed:(NSInteger)seed
                                  threadCount:(NSInteger)threadCount
                                    batchSize:(NSInteger)batchSize
                               microBatchSize:(NSInteger)microBatchSize
                                 metalEnabled:(BOOL)metalEnabled
                           cpuFallbackAllowed:(BOOL)cpuFallbackAllowed
                                  kvCacheMode:(NSString *)kvCacheMode
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString *token))onToken
                                        error:(NSError **)error;
+ (void)unload;
@end

NS_ASSUME_NONNULL_END
