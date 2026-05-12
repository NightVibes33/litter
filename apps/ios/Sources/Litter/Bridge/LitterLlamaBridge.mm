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

static std::string LitterLlamaModelPrompt(const llama_model *model, NSArray<NSDictionary<NSString *, NSString *> *> *messages) {
    const char *tmpl = llama_model_chat_template(model, nullptr);
    if (tmpl == nullptr) { return LitterLlamaPrompt(messages); }

    std::vector<std::string> roles;
    std::vector<std::string> contents;
    std::vector<llama_chat_message> chat;
    roles.reserve(messages.count);
    contents.reserve(messages.count);
    chat.reserve(messages.count);
    for (NSDictionary *message in messages) {
        roles.push_back(LitterLlamaUTF8(message[@"role"] ?: @"user"));
        contents.push_back(LitterLlamaUTF8(message[@"text"] ?: @""));
    }
    for (size_t index = 0; index < roles.size(); index++) {
        chat.push_back({ roles[index].c_str(), contents[index].c_str() });
    }

    int32_t needed = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, nullptr, 0);
    if (needed <= 0) { return LitterLlamaPrompt(messages); }
    std::vector<char> rendered((size_t)needed + 1);
    int32_t written = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, rendered.data(), needed + 1);
    if (written <= 0) { return LitterLlamaPrompt(messages); }
    return std::string(rendered.data(), (size_t)written);
}

static std::string LitterLlamaPromptForMode(const llama_model *model,
                                            NSArray<NSDictionary<NSString *, NSString *> *> *messages,
                                            NSString *promptTemplateMode) {
    NSString *mode = [promptTemplateMode lowercaseString];
    if ([mode isEqualToString:@"modeldefault"]) {
        return LitterLlamaModelPrompt(model, messages);
    }
    return LitterLlamaPrompt(messages);
}

static std::vector<llama_token> LitterLlamaTokenize(const llama_vocab *vocab,
                                                    const std::string &prompt,
                                                    int32_t maxContextTokens,
                                                    BOOL parseSpecialTokens) {
    bool parseSpecial = parseSpecialTokens ? true : false;
    int32_t count = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), nullptr, 0, true, parseSpecial);
    if (count < 0) { count = -count; }
    if (count <= 0) { return {}; }
    std::vector<llama_token> tokens((size_t)count);
    int32_t written = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), tokens.data(), count, true, parseSpecial);
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

static enum llama_flash_attn_type LitterLlamaFlashAttentionType(NSString *mode) {
    NSString *lower = [(mode.length > 0 ? mode : @"automatic") lowercaseString];
    if ([lower isEqualToString:@"enabled"]) { return LLAMA_FLASH_ATTN_TYPE_ENABLED; }
    if ([lower isEqualToString:@"disabled"]) { return LLAMA_FLASH_ATTN_TYPE_DISABLED; }
    return LLAMA_FLASH_ATTN_TYPE_AUTO;
}

static enum llama_rope_scaling_type LitterLlamaRopeScalingType(NSString *mode) {
    NSString *lower = [(mode.length > 0 ? mode : @"modeldefault") lowercaseString];
    if ([lower isEqualToString:@"none"]) { return LLAMA_ROPE_SCALING_TYPE_NONE; }
    if ([lower isEqualToString:@"linear"]) { return LLAMA_ROPE_SCALING_TYPE_LINEAR; }
    if ([lower isEqualToString:@"yarn"]) { return LLAMA_ROPE_SCALING_TYPE_YARN; }
    if ([lower isEqualToString:@"longrope"]) { return LLAMA_ROPE_SCALING_TYPE_LONGROPE; }
    return LLAMA_ROPE_SCALING_TYPE_UNSPECIFIED;
}

static uint32_t LitterLlamaSamplerSeed(NSInteger seed) {
    return seed < 0 ? LLAMA_DEFAULT_SEED : (uint32_t)seed;
}

static llama_model *LitterLlamaLoadModel(NSString *modelPath,
                                         BOOL metalEnabled,
                                         NSInteger gpuLayerCount,
                                         BOOL mmapEnabled,
                                         BOOL mlockEnabled,
                                         BOOL checkTensors) {
    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = metalEnabled ? (int32_t)gpuLayerCount : 0;
    modelParams.use_mmap = mmapEnabled;
    modelParams.use_mlock = mlockEnabled;
    modelParams.check_tensors = checkTensors;
    return llama_model_load_from_file([modelPath fileSystemRepresentation], modelParams);
}

static llama_context *LitterLlamaCreateContext(llama_model *model,
                                               NSInteger contextTokens,
                                               NSInteger threadCount,
                                               NSInteger batchThreadCount,
                                               NSInteger batchSize,
                                               NSInteger microBatchSize,
                                               ggml_type kvType,
                                               NSString *flashAttentionMode,
                                               BOOL offloadKQV,
                                               BOOL opOffload,
                                               BOOL swaFull,
                                               BOOL kvUnified,
                                               NSString *ropeScalingMode,
                                               double ropeFrequencyBase,
                                               double ropeFrequencyScale,
                                               double yarnExtensionFactor,
                                               double yarnAttentionFactor,
                                               double yarnBetaFast,
                                               double yarnBetaSlow,
                                               NSInteger yarnOriginalContext) {
    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)std::max((NSInteger)512, contextTokens);
    uint32_t requestedBatch = (uint32_t)std::max((NSInteger)32, batchSize);
    contextParams.n_batch = std::min(contextParams.n_ctx, requestedBatch);
    uint32_t requestedMicroBatch = (uint32_t)std::max((NSInteger)32, microBatchSize);
    contextParams.n_ubatch = std::min(contextParams.n_batch, requestedMicroBatch);
    int32_t threads = (int32_t)std::max((NSInteger)1, std::min((NSInteger)12, threadCount));
    int32_t batchThreads = batchThreadCount <= 0 ? threads : (int32_t)std::max((NSInteger)1, std::min((NSInteger)12, batchThreadCount));
    contextParams.n_threads = threads;
    contextParams.n_threads_batch = batchThreads;
    contextParams.type_k = kvType;
    contextParams.type_v = kvType;
    contextParams.flash_attn_type = LitterLlamaFlashAttentionType(flashAttentionMode);
    contextParams.offload_kqv = offloadKQV;
    contextParams.op_offload = opOffload;
    contextParams.swa_full = swaFull;
    contextParams.kv_unified = kvUnified;
    contextParams.rope_scaling_type = LitterLlamaRopeScalingType(ropeScalingMode);
    contextParams.rope_freq_base = (float)std::max(0.0, ropeFrequencyBase);
    contextParams.rope_freq_scale = (float)std::max(0.0, ropeFrequencyScale);
    contextParams.yarn_ext_factor = (float)yarnExtensionFactor;
    contextParams.yarn_attn_factor = (float)yarnAttentionFactor;
    contextParams.yarn_beta_fast = (float)yarnBetaFast;
    contextParams.yarn_beta_slow = (float)yarnBetaSlow;
    contextParams.yarn_orig_ctx = (uint32_t)std::max((NSInteger)0, yarnOriginalContext);
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
                                   minP:0
                               typicalP:1
                dynamicTemperatureRange:0
             dynamicTemperatureExponent:1
                           mirostatMode:@"off"
                            mirostatTau:5
                            mirostatEta:0.1
                            repeatLastN:64
                          repeatPenalty:1.08
                       frequencyPenalty:0
                        presencePenalty:0
                                   seed:-1
                            threadCount:defaultThreads
                       batchThreadCount:0
                              batchSize:1024
                         microBatchSize:512
                           metalEnabled:YES
                          gpuLayerCount:-1
                     cpuFallbackAllowed:YES
                            mmapEnabled:YES
                           mlockEnabled:NO
                           checkTensors:NO
                     flashAttentionMode:@"automatic"
                             offloadKQV:YES
                              opOffload:YES
                                swaFull:YES
                              kvUnified:NO
                            kvCacheMode:@"automatic"
                     promptTemplateMode:@"litter"
                     parseSpecialTokens:YES
                          stopSequences:@[]
                        ropeScalingMode:@"modelDefault"
                      ropeFrequencyBase:0
                     ropeFrequencyScale:0
                    yarnExtensionFactor:-1
                    yarnAttentionFactor:-1
                           yarnBetaFast:-1
                           yarnBetaSlow:-1
                    yarnOriginalContext:0
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

    llama_model *model = LitterLlamaLoadModel(modelPath, metalEnabled, gpuLayerCount, mmapEnabled, mlockEnabled, checkTensors);
    if (model == nullptr && metalEnabled && cpuFallbackAllowed) {
        model = LitterLlamaLoadModel(modelPath, false, 0, mmapEnabled, mlockEnabled, checkTensors);
    }
    if (model == nullptr) {
        LitterLlamaSetError(error, 2, @"llama.cpp could not load the GGUF model.");
        return nil;
    }

    llama_context *ctx = LitterLlamaCreateContext(
        model,
        contextTokens,
        threadCount,
        batchThreadCount,
        batchSize,
        microBatchSize,
        kvType,
        flashAttentionMode,
        offloadKQV,
        opOffload,
        swaFull,
        kvUnified,
        ropeScalingMode,
        ropeFrequencyBase,
        ropeFrequencyScale,
        yarnExtensionFactor,
        yarnAttentionFactor,
        yarnBetaFast,
        yarnBetaSlow,
        yarnOriginalContext
    );
    if (ctx == nullptr && metalEnabled && cpuFallbackAllowed) {
        llama_model_free(model);
        model = LitterLlamaLoadModel(modelPath, false, 0, mmapEnabled, mlockEnabled, checkTensors);
        if (model != nullptr) {
            ctx = LitterLlamaCreateContext(
                model,
                contextTokens,
                threadCount,
                batchThreadCount,
                batchSize,
                microBatchSize,
                kvType,
                flashAttentionMode,
                false,
                false,
                swaFull,
                kvUnified,
                ropeScalingMode,
                ropeFrequencyBase,
                ropeFrequencyScale,
                yarnExtensionFactor,
                yarnAttentionFactor,
                yarnBetaFast,
                yarnBetaSlow,
                yarnOriginalContext
            );
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
    std::string prompt = LitterLlamaPromptForMode(model, messages, promptTemplateMode);
    std::vector<llama_token> promptTokens = LitterLlamaTokenize(vocab, prompt, promptBudget, parseSpecialTokens);
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
    uint32_t samplerSeed = LitterLlamaSamplerSeed(seed);
    if (temperature > 0.001) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int32_t)std::max((NSInteger)1, topK)));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p((float)std::max(0.05, std::min(1.0, topP)), 1));
        if (minP > 0.001) {
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p((float)std::min(1.0, std::max(0.0, minP)), 1));
        }
        if (typicalP < 0.999) {
            llama_sampler_chain_add(sampler, llama_sampler_init_typical((float)std::min(1.0, std::max(0.0, typicalP)), 1));
        }
        if (dynamicTemperatureRange > 0.001) {
            llama_sampler_chain_add(sampler, llama_sampler_init_temp_ext((float)temperature, (float)dynamicTemperatureRange, (float)dynamicTemperatureExponent));
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)temperature));
        }
        NSString *mirostat = [(mirostatMode.length > 0 ? mirostatMode : @"off") lowercaseString];
        if ([mirostat isEqualToString:@"v1"]) {
            llama_sampler_chain_add(sampler, llama_sampler_init_mirostat(llama_vocab_n_tokens(vocab), samplerSeed, (float)mirostatTau, (float)mirostatEta, 100));
        } else if ([mirostat isEqualToString:@"v2"]) {
            llama_sampler_chain_add(sampler, llama_sampler_init_mirostat_v2(samplerSeed, (float)mirostatTau, (float)mirostatEta));
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(samplerSeed));
        }
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
        BOOL hitStop = NO;
        NSString *pieceToEmit = piece;
        if (piece.length > 0 && stopSequences.count > 0) {
            NSString *candidate = [output stringByAppendingString:piece];
            NSUInteger earliest = NSNotFound;
            NSUInteger longestStop = 0;
            for (NSString *stop in stopSequences) {
                longestStop = std::max(longestStop, stop.length);
            }
            NSUInteger searchStart = output.length > longestStop ? output.length - longestStop : 0;
            NSRange searchRange = NSMakeRange(searchStart, candidate.length - searchStart);
            for (NSString *stop in stopSequences) {
                if (stop.length == 0) { continue; }
                NSRange range = [candidate rangeOfString:stop options:0 range:searchRange];
                if (range.location != NSNotFound && range.location < earliest) {
                    earliest = range.location;
                }
            }
            if (earliest != NSNotFound) {
                NSString *trimmed = [candidate substringToIndex:earliest];
                pieceToEmit = trimmed.length > output.length ? [trimmed substringFromIndex:output.length] : @"";
                hitStop = YES;
            }
        }
        if (pieceToEmit.length > 0) {
            [output appendString:pieceToEmit];
            if (onToken != nil) { onToken(pieceToEmit); }
        }
        if (hitStop) { break; }
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
