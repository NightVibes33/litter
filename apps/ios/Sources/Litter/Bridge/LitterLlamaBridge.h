#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LitterLlamaBridge : NSObject

+ (BOOL)isAvailable;

+ (nullable NSString *)generateWithModelPath:(NSString *)modelPath
                               contextTokens:(NSInteger)contextTokens
                                    maxTokens:(NSInteger)maxTokens
                                  temperature:(double)temperature
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString * token))onToken
                                        error:(NSError **)error;

+ (void)unload;

@end

NS_ASSUME_NONNULL_END
