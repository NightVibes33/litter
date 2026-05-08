#import "LitterLlamaBridge.h"

#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include("llama.h")
#import "llama.h"
#else
#error "llama.cpp headers were not found. Build apps/ios/Frameworks/llama.xcframework before compiling LitterLlamaBridge.mm."
#endif

#import <Foundation/Foundation.h>
#import <algorithm>
#import <atomic>
#import <cmath>
#import <cstring>
#import <mutex>
#import <string>
#import <vector>

static NSString * const LitterLlamaBridgeErrorDomain = @"com.sigkitten.litter.llama";

static std::once_flag LitterLlamaBackendOnce;
static std::atomic_bool LitterLlamaCancelRequested(false);

static void LitterLlamaSetError(NSError **error, NSInteger code, NSString *message) {
    if (error == nullptr) { return; }
    *error = [NSError errorWithDomain:LitterLlamaBridgeErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

static std::string LitterLlamaUTF8(NSString *string) {
    if (string == nil) { return std::string(); }
    const char *utf8 = [string UTF8String];
    return utf8 == nullptr ? std::string() : std::string(utf8);
}

static std::string LitterLlamaPrompt(NSArray<NSDictionary<NSString *, NSString *> *> *messages) {
    std::string prompt;
    for (NSDictionary<NSString *, NSString *> *message in messages) {
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

@implementation LitterLlamaBridge

+ (BOOL)isAvailable {
    return YES;
}

+ (nullable NSString *)generateWithModelPath:(NSString *)modelPath
                               contextTokens:(NSInteger)contextTokens
                                    maxTokens:(NSInteger)maxTokens
                                  temperature:(double)temperature
                                     messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                                      onToken:(void (^)(NSString * token))onToken
                                        error:(NSError **)error {
    if (modelPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        LitterLlamaSetError(error, 1, @"The selected GGUF model file does not exist.");
        return nil;
    }

    std::call_once(LitterLlamaBackendOnce, [] { llama_backend_init(); });
    LitterLlamaCancelRequested.store(false);

    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = -1;

    llama_model *model = llama_model_load_from_file([modelPath fileSystemRepresentation], modelParams);
    if (model == nullptr) {
        LitterLlamaSetError(error, 2, @"llama.cpp could not load the GGUF model.");
        return nil;
    }

    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)std::max<NSInteger>(512, contextTokens);
    contextParams.n_batch = std::min<uint32_t>(contextParams.n_ctx, 1024);
    contextParams.n_ubatch = std::min<uint32_t>(contextParams.n_batch, 512);
    contextParams.n_threads = (int32_t)std::max<NSInteger>(2, std::min<NSInteger>(6, [[NSProcessInfo processInfo] processorCount] - 1));
    contextParams.n_threads_batch = contextParams.n_threads;

    llama_context *ctx = llama_init_from_model(model, contextParams);
    if (ctx == nullptr) {
        llama_model_free(model);
        LitterLlamaSetError(error, 3, @"llama.cpp could not create an inference context for this model.");
        return nil;
    }

    const llama_vocab *vocab = llama_model_get_vocab(model);
    int32_t generationBudget = (int32_t)std::max<NSInteger>(1, maxTokens);
    int32_t promptBudget = std::max<int32_t>(32, (int32_t)contextParams.n_ctx - generationBudget - 8);
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
    if (temperature > 0.001) {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
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

+ (void)unload {
    LitterLlamaCancelRequested.store(true);
}

@end
