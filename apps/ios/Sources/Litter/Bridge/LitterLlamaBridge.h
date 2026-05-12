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
                                         minP:(double)minP
                                     typicalP:(double)typicalP
                      dynamicTemperatureRange:(double)dynamicTemperatureRange
                   dynamicTemperatureExponent:(double)dynamicTemperatureExponent
                                 mirostatMode:(NSString *)mirostatMode
                                  mirostatTau:(double)mirostatTau
                                  mirostatEta:(double)mirostatEta
                                  repeatLastN:(NSInteger)repeatLastN
                                repeatPenalty:(double)repeatPenalty
                             frequencyPenalty:(double)frequencyPenalty
                              presencePenalty:(double)presencePenalty
                                         seed:(NSInteger)seed
                                  threadCount:(NSInteger)threadCount
                             batchThreadCount:(NSInteger)batchThreadCount
                                    batchSize:(NSInteger)batchSize
                               microBatchSize:(NSInteger)microBatchSize
                                 metalEnabled:(BOOL)metalEnabled
                                gpuLayerCount:(NSInteger)gpuLayerCount
                           cpuFallbackAllowed:(BOOL)cpuFallbackAllowed
                                  mmapEnabled:(BOOL)mmapEnabled
                                  mlockEnabled:(BOOL)mlockEnabled
                                 checkTensors:(BOOL)checkTensors
                           flashAttentionMode:(NSString *)flashAttentionMode
                                   offloadKQV:(BOOL)offloadKQV
                                    opOffload:(BOOL)opOffload
                                      swaFull:(BOOL)swaFull
                                    kvUnified:(BOOL)kvUnified
                                  kvCacheMode:(NSString *)kvCacheMode
                           promptTemplateMode:(NSString *)promptTemplateMode
                           parseSpecialTokens:(BOOL)parseSpecialTokens
                                stopSequences:(NSArray<NSString *> *)stopSequences
                              ropeScalingMode:(NSString *)ropeScalingMode
                            ropeFrequencyBase:(double)ropeFrequencyBase
                           ropeFrequencyScale:(double)ropeFrequencyScale
                          yarnExtensionFactor:(double)yarnExtensionFactor
                          yarnAttentionFactor:(double)yarnAttentionFactor
                                 yarnBetaFast:(double)yarnBetaFast
                                 yarnBetaSlow:(double)yarnBetaSlow
                          yarnOriginalContext:(NSInteger)yarnOriginalContext
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString *token))onToken
                                        error:(NSError **)error;
+ (void)unload;
@end

NS_ASSUME_NONNULL_END
