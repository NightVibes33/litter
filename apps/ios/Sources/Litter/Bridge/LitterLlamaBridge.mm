#import "LitterLlamaBridge.h"

#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include("llama.h")
#import "llama.h"
#else
#error "llama.cpp headers were not found. Build apps/ios/Frameworks/llama.xcframework before compiling LitterLlamaBridge.mm."
#endif

#if __has_include(<ggml.h>)
#import <ggml.h>
#elif __has_include("ggml.h")
#import "ggml.h"
#endif

#import <Foundation/Foundation.h>
#import <algorithm>
#import <atomic>
#import <cctype>
#import <cmath>
#import <mutex>
#import <string>
#import <vector>

static NSString * const LitterLlamaBridgeErrorDomain = @"com.sigkitten.litter.llama";
static std::once_flag LitterLlamaBackendOnce;
static std::atomic_bool LitterLlamaCancelRequested(false);

static void LitterLlamaSetError(NSError **error, NSInteger code, NSString *message) {
    if (error == nullptr) { return; }
    *error = [NSError errorWithDomain:LitterLlamaBridgeErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static std::string LitterLlamaUTF8(NSString *string) {
    if (string == nil) { return std::string(); }
    const char *utf8 = [string UTF8String];
    return utf8 == nullptr ? std::string() : std::string(utf8);
}

static std::string LitterLlamaPrompt(NSArray<NSDictionary<NSString *, NSString *> *> *messages) {
    std::string prompt;
    for (NSDictionary *message in messages) {
        NSString *role = message[@"role"] ?: @"user";
        NSString *text = message[@"text"] ?: @"";
        prompt += "<|" + LitterLlamaUTF8(role) + "|>\n";
        prompt += LitterLlamaUTF8(text);
        prompt += "\n";
    }
    prompt += "<|assistant|>\n";
    return prompt;
}

static std::vector<llama_token> LitterLlamaTokenize(const llama_vocab *vocab, const std::string &prompt, int32_t maxContextTokens) {
    int32_t count = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), nullptr, 0, true, true);
    if (count < 0) { count = -count; }
    if (count <= 0) { return {}; }
    std::vector<llama_token> tokens((size_t)count);
    int32_t written = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), tokens.data(), count, true, true);
    if (written < 0) { written = -written; }
    tokens.resize((size_t)std::max(0, written));
    if (maxContextTokens > 0 && (int32_t)tokens.size() > maxContextTokens) {
        tokens.erase(tokens.begin(), tokens.end() - maxContextTokens);
    }
    return tokens;
}

static NSString *LitterLlamaPiece(const llama_vocab *vocab, llama_token token) {
    char small[256];
    int32_t written = llama_token_to_piece(vocab, token, small, sizeof(small), 0, false);
    if (written < 0) {
        std::vector<char> large((size_t)(-written) + 1);
        written = llama_token_to_piece(vocab, token, large.data(), (int32_t)large.size(), 0, false);
        if (written > 0) {
            return [[NSString alloc] initWithBytes:large.data() length:(NSUInteger)written encoding:NSUTF8StringEncoding] ?: @"";
        }
        return @"";
    }
    if (written == 0) { return @""; }
    return [[NSString alloc] initWithBytes:small length:(NSUInteger)written encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *LitterLlamaTypeName(ggml_type type) {
    const char *name = ggml_type_name(type);
    return name == nullptr ? @"" : [NSString stringWithUTF8String:name];
}

static BOOL LitterLlamaTypeLooksTurbo(ggml_type type) {
    NSString *name = [LitterLlamaTypeName(type) lowercaseString];
    return [name containsString:@"tq"] || [name containsString:@"turbo"] || [name containsString:@"tbq"];
}

static BOOL LitterLlamaSupportsTurboQuant(void) {
    return LitterLlamaTypeLooksTurbo((ggml_type)41) || LitterLlamaTypeLooksTurbo((ggml_type)42);
}

static ggml_type LitterLlamaKVType(NSString *mode, NSError **error) {
    NSString *selectedMode = mode == nil ? @"automatic" : mode;
    NSString *lower = [selectedMode lowercaseString];
    if ([lower isEqualToString:@"automatic"] || lower.length == 0) { return GGML_TYPE_F16; }
    if ([lower isEqualToString:@"f16"]) { return GGML_TYPE_F16; }
    if ([lower isEqualToString:@"q8"]) { return GGML_TYPE_Q8_0; }
    if ([lower isEqualToString:@"q4"]) { return GGML_TYPE_Q4_0; }
    if ([lower isEqualToString:@"turbo3"]) {
        ggml_type type = (ggml_type)41; // Community TurboQuant forks commonly expose TQ3_0 here.
        if (LitterLlamaTypeLooksTurbo(type)) { return type; }
        LitterLlamaSetError(error, 9, @"TurboQuant 3-bit KV cache was requested, but this llama.cpp build does not expose a TurboQuant ggml type.");
        return GGML_TYPE_F16;
    }
    if ([lower isEqualToString:@"turbo4"]) {
        ggml_type type = (ggml_type)42; // Community TurboQuant forks commonly expose the paired 4-bit type here.
        if (LitterLlamaTypeLooksTurbo(type)) { return type; }
        LitterLlamaSetError(error, 10, @"TurboQuant 4-bit KV cache was requested, but this llama.cpp build does not expose a TurboQuant ggml type.");
        return GGML_TYPE_F16;
    }
    return GGML_TYPE_F16;
}

static llama_model *LitterLlamaLoadModel(NSString *modelPath, BOOL metalEnabled) {
    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = metalEnabled ? -1 : 0;
    return llama_model_load_from_file([modelPath fileSystemRepresentation], modelParams);
}

static llama_context *LitterLlamaCreateContext(llama_model *model,
                                               NSInteger contextTokens,
                                               NSInteger threadCount,
                                               NSInteger batchSize,
                                               NSInteger microBatchSize,
                                               ggml_type kvType) {
    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)std::max((NSInteger)512, contextTokens);
    uint32_t requestedBatch = (uint32_t)std::max((NSInteger)32, batchSize);
    contextParams.n_batch = std::min(contextParams.n_ctx, requestedBatch);
    uint32_t requestedMicroBatch = (uint32_t)std::max((NSInteger)32, microBatchSize);
    contextParams.n_ubatch = std::min(contextParams.n_batch, requestedMicroBatch);
    int32_t threads = (int32_t)std::max((NSInteger)1, std::min((NSInteger)12, threadCount));
    contextParams.n_threads = threads;
    contextParams.n_threads_batch = threads;
    contextParams.type_k = kvType;
    contextParams.type_v = kvType;
    return llama_init_from_model(model, contextParams);
}

@implementation LitterLlamaBridge

+ (BOOL)isAvailable { return YES; }

+ (BOOL)supportsTurboQuant { return LitterLlamaSupportsTurboQuant(); }

+ (NSArray<NSString *> *)supportedKVCacheModes {
    NSMutableArray<NSString *> *modes = [NSMutableArray arrayWithObjects:@"automatic", @"f16", @"q8", @"q4", nil];
    if (LitterLlamaTypeLooksTurbo((ggml_type)41)) { [modes addObject:@"turbo3"]; }
    if (LitterLlamaTypeLooksTurbo((ggml_type)42)) { [modes addObject:@"turbo4"]; }
    return modes;
}

+ (nullable NSString *)generateWithModelPath:(NSString *)modelPath
                               contextTokens:(NSInteger)contextTokens
                                    maxTokens:(NSInteger)maxTokens
                                  temperature:(double)temperature
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString *token))onToken
                                        error:(NSError **)error {
    NSInteger cpuCount = (NSInteger)[[NSProcessInfo processInfo] processorCount];
    NSInteger defaultThreads = std::max((NSInteger)2, std::min((NSInteger)6, cpuCount - 1));
    return [self generateWithModelPath:modelPath
                         contextTokens:contextTokens
                              maxTokens:maxTokens
                            temperature:temperature
                                   topP:0.95
                                   topK:40
                            repeatLastN:64
                          repeatPenalty:1.08
                        frequencyPenalty:0
                          presencePenalty:0
                                   seed:-1
                            threadCount:defaultThreads
                              batchSize:1024
                         microBatchSize:512
                           metalEnabled:YES
                     cpuFallbackAllowed:YES
                            kvCacheMode:@"automatic"
                               messages:messages
                                onToken:onToken
                                  error:error];
}

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
                                        error:(NSError **)error {
    if (modelPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        LitterLlamaSetError(error, 1, @"The selected GGUF model file does not exist.");
        return nil;
    }

    NSError *kvError = nil;
    ggml_type kvType = LitterLlamaKVType(kvCacheMode, &kvError);
    if (kvError != nil) {
        if (error != nullptr) { *error = kvError; }
        return nil;
    }

    std::call_once(LitterLlamaBackendOnce, [] { llama_backend_init(); });
    LitterLlamaCancelRequested.store(false);

    llama_model *model = LitterLlamaLoadModel(modelPath, metalEnabled);
    if (model == nullptr && metalEnabled && cpuFallbackAllowed) {
        model = LitterLlamaLoadModel(modelPath, false);
    }
    if (model == nullptr) {
        LitterLlamaSetError(error, 2, @"llama.cpp could not load the GGUF model.");
        return nil;
    }

    llama_context *ctx = LitterLlamaCreateContext(model, contextTokens, threadCount, batchSize, microBatchSize, kvType);
    if (ctx == nullptr && metalEnabled && cpuFallbackAllowed) {
        llama_model_free(model);
        model = LitterLlamaLoadModel(modelPath, false);
        if (model != nullptr) {
            ctx = LitterLlamaCreateContext(model, contextTokens, threadCount, batchSize, microBatchSize, kvType);
        }
    }
    if (ctx == nullptr) {
        llama_model_free(model);
        LitterLlamaSetError(error, 3, @"llama.cpp could not create an inference context for this model and runtime settings.");
        return nil;
    }

    const llama_vocab *vocab = llama_model_get_vocab(model);
    int32_t generationBudget = (int32_t)std::max((NSInteger)1, maxTokens);
    int32_t promptBudget = std::max(32, (int32_t)std::max((NSInteger)512, contextTokens) - generationBudget - 8);
    std::vector<llama_token> promptTokens = LitterLlamaTokenize(vocab, LitterLlamaPrompt(messages), promptBudget);
    if (promptTokens.empty()) {
        llama_free(ctx);
        llama_model_free(model);
        LitterLlamaSetError(error, 4, @"The prompt could not be tokenized for this model.");
        return nil;
    }

    llama_batch promptBatch = llama_batch_get_one(promptTokens.data(), (int32_t)promptTokens.size());
    if (llama_decode(ctx, promptBatch) != 0) {
        llama_free(ctx);
        llama_model_free(model);
        LitterLlamaSetError(error, 5, @"llama.cpp failed while decoding the prompt.");
        return nil;
    }

    llama_sampler_chain_params samplerParams = llama_sampler_chain_default_params();
    llama_sampler *sampler = llama_sampler_chain_init(samplerParams);
    if ((repeatPenalty > 0.001 && fabs(repeatPenalty - 1.0) > 0.001) || fabs(frequencyPenalty) > 0.001 || fabs(presencePenalty) > 0.001) {
        int32_t repeatWindow = (int32_t)std::max((NSInteger)0, std::min((NSInteger)4096, repeatLastN));
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(repeatWindow, (float)repeatPenalty, (float)frequencyPenalty, (float)presencePenalty));
    }
    if (temperature > 0.001) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int32_t)std::max((NSInteger)1, topK)));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p((float)std::max(0.05, std::min(1.0, topP)), 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)temperature));
        uint32_t samplerSeed = seed < 0 ? LLAMA_DEFAULT_SEED : (uint32_t)seed;
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(samplerSeed));
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    }

    NSMutableString *output = [NSMutableString string];
    for (int32_t index = 0; index < generationBudget; index++) {
        if (LitterLlamaCancelRequested.load()) { break; }
        llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) { break; }
        llama_sampler_accept(sampler, token);
        NSString *piece = LitterLlamaPiece(vocab, token);
        if (piece.length > 0) {
            [output appendString:piece];
            if (onToken != nil) { onToken(piece); }
        }
        llama_batch tokenBatch = llama_batch_get_one(&token, 1);
        if (llama_decode(ctx, tokenBatch) != 0) {
            llama_sampler_free(sampler);
            llama_free(ctx);
            llama_model_free(model);
            LitterLlamaSetError(error, 6, @"llama.cpp failed while decoding a generated token.");
            return nil;
        }
    }

    llama_sampler_free(sampler);
    llama_free(ctx);
    llama_model_free(model);
    return output;
}

+ (void)unload { LitterLlamaCancelRequested.store(true); }

@end
