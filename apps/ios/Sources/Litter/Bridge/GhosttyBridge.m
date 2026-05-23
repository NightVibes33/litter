#import "GhosttyBridge.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

#define GHOSTTY_STATIC 1
#import "ghostty.h"

static NSString *const LitterGhosttyErrorDomain = @"com.sigkitten.litter.ghostty";

static void LitterGhosttyResizeBackingLayers(UIView *view, CGFloat scale);
static void LitterGhosttyWakeup(void *userdata);
static bool LitterGhosttyAction(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action);
static bool LitterGhosttyReadClipboard(void *userdata, ghostty_clipboard_e clipboard, void *request);
static void LitterGhosttyConfirmReadClipboard(void *userdata, const char *title, void *request, ghostty_clipboard_request_e requestType);
static void LitterGhosttyWriteClipboard(void *userdata, ghostty_clipboard_e clipboard, const ghostty_clipboard_content_s *contents, size_t count, bool confirm);
static void LitterGhosttyCloseSurface(void *userdata, bool processActive);
static void LitterGhosttyExternalWrite(void *userdata, const uint8_t *data, uintptr_t length);
static dispatch_queue_t LitterGhosttyDestroyQueue(void);

@interface LitterGhosttyTerminal ()
@property (nonatomic, weak) UIView *view;
- (void)draw;
@end

@implementation LitterGhosttyTerminal {
    ghostty_config_t _config;
    ghostty_app_t _app;
    ghostty_surface_t _surface;
    uint32_t _lastPixelWidth;
    uint32_t _lastPixelHeight;
    CGFloat _lastScale;
    BOOL _invalidated;
}

+ (BOOL)ensureInitialized:(NSError **)error {
    static dispatch_once_t onceToken;
    static int initResult = 1;

    dispatch_once(&onceToken, ^{
        char arg0[] = "litter";
        char *argv[] = { arg0 };
        initResult = ghostty_init(1, argv);
    });

    if (initResult == GHOSTTY_SUCCESS) {
        return YES;
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                     code:initResult
                                 userInfo:@{NSLocalizedDescriptionKey: @"Ghostty failed to initialize"}];
    }
    return NO;
}

- (nullable instancetype)initWithView:(UIView *)view error:(NSError **)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    if (![LitterGhosttyTerminal ensureInitialized:error]) {
        return nil;
    }

    _view = view;

    _config = ghostty_config_new();
    if (_config == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ghostty failed to create config"}];
        }
        return nil;
    }
    ghostty_config_finalize(_config);

    ghostty_runtime_config_s runtimeConfig = {0};
    runtimeConfig.userdata = (__bridge void *)self;
    runtimeConfig.supports_selection_clipboard = false;
    runtimeConfig.wakeup_cb = LitterGhosttyWakeup;
    runtimeConfig.action_cb = LitterGhosttyAction;
    runtimeConfig.read_clipboard_cb = LitterGhosttyReadClipboard;
    runtimeConfig.confirm_read_clipboard_cb = LitterGhosttyConfirmReadClipboard;
    runtimeConfig.write_clipboard_cb = LitterGhosttyWriteClipboard;
    runtimeConfig.close_surface_cb = LitterGhosttyCloseSurface;

    _app = ghostty_app_new(&runtimeConfig, _config);
    if (_app == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ghostty failed to create app"}];
        }
        [self invalidate];
        return nil;
    }

    ghostty_surface_config_s surfaceConfig = ghostty_surface_config_new();
    surfaceConfig.platform_tag = GHOSTTY_PLATFORM_IOS;
    surfaceConfig.platform.ios.uiview = (__bridge void *)view;
    surfaceConfig.userdata = (__bridge void *)self;
    surfaceConfig.scale_factor = view.window.screen.scale ?: UIScreen.mainScreen.scale;
    surfaceConfig.font_size = 13.0f;
    surfaceConfig.external_pty = true;
    surfaceConfig.external_pty_write = LitterGhosttyExternalWrite;
    surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW;

    _surface = ghostty_surface_new(_app, &surfaceConfig);
    if (_surface == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ghostty failed to create surface"}];
        }
        [self invalidate];
        return nil;
    }

    LitterGhosttyResizeBackingLayers(view, surfaceConfig.scale_factor);
    ghostty_app_set_focus(_app, true);
    ghostty_surface_set_focus(_surface, true);
    [self resizeToWidth:view.bounds.size.width height:view.bounds.size.height scale:surfaceConfig.scale_factor];

    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (void)invalidate {
    if (_invalidated) {
        return;
    }
    _invalidated = YES;

    self.inputHandler = nil;
    _view = nil;

    ghostty_surface_t surface = _surface;
    ghostty_app_t app = _app;
    ghostty_config_t config = _config;
    _surface = NULL;
    _app = NULL;
    _config = NULL;

    if (surface != NULL || app != NULL || config != NULL) {
        LitterGhosttyTerminal *terminal = self;
        dispatch_async(LitterGhosttyDestroyQueue(), ^{
            (void)terminal;
            if (surface != NULL) {
                ghostty_surface_free(surface);
            }
            if (app != NULL) {
                ghostty_app_free(app);
            }
            if (config != NULL) {
                ghostty_config_free(config);
            }
        });
    }
}

- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height scale:(CGFloat)scale {
    if (_surface == NULL || width <= 0 || height <= 0) {
        return;
    }

    CGFloat resolvedScale = scale > 0 ? scale : UIScreen.mainScreen.scale;
    uint32_t pixelWidth = (uint32_t)MAX(1.0, floor(width * resolvedScale));
    uint32_t pixelHeight = (uint32_t)MAX(1.0, floor(height * resolvedScale));
    BOOL sizeChanged = pixelWidth != _lastPixelWidth
        || pixelHeight != _lastPixelHeight
        || fabs(resolvedScale - _lastScale) > 0.0001;

    LitterGhosttyResizeBackingLayers(_view, resolvedScale);
    ghostty_surface_set_content_scale(_surface, resolvedScale, resolvedScale);
    ghostty_surface_set_size(_surface, pixelWidth, pixelHeight);
    _lastPixelWidth = pixelWidth;
    _lastPixelHeight = pixelHeight;
    _lastScale = resolvedScale;

    if (sizeChanged) {
        ghostty_surface_refresh(_surface);
        ghostty_surface_render(_surface);
    }
}

- (void)writeOutput:(NSData *)data {
    if (_surface == NULL || data.length == 0) {
        return;
    }

    ghostty_surface_write(_surface, data.bytes, data.length);
    ghostty_surface_render(_surface);
}

- (NSString *)visibleText {
    if (_surface == NULL) {
        return @"";
    }

    ghostty_selection_s selection = {0};
    selection.top_left.tag = GHOSTTY_POINT_VIEWPORT;
    selection.top_left.coord = GHOSTTY_POINT_COORD_TOP_LEFT;
    selection.bottom_right.tag = GHOSTTY_POINT_VIEWPORT;
    selection.bottom_right.coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT;

    ghostty_text_s text = {0};
    if (!ghostty_surface_read_text(_surface, selection, &text)) {
        return @"";
    }
    @try {
        if (text.text == NULL || text.text_len == 0) {
            return @"";
        }
        NSString *result = [[NSString alloc] initWithBytes:text.text
                                                    length:(NSUInteger)text.text_len
                                                  encoding:NSUTF8StringEncoding];
        return result ?: @"";
    } @finally {
        ghostty_surface_free_text(_surface, &text);
    }
}

- (void)draw {
    if (_app == NULL) {
        return;
    }

    ghostty_app_tick(_app);
}

- (void)setOcclusion:(BOOL)occluded {
    if (_surface == NULL) {
        return;
    }
    ghostty_surface_set_occlusion(_surface, occluded);
}

- (void)setFocused:(BOOL)focused {
    if (_app != NULL) {
        ghostty_app_set_focus(_app, focused);
    }
    if (_surface != NULL) {
        ghostty_surface_set_focus(_surface, focused);
    }
}

- (BOOL)mouseCaptured {
    return _surface != NULL ? ghostty_surface_mouse_captured(_surface) : NO;
}

- (void)mousePosX:(double)x y:(double)y mods:(int)mods {
    if (_surface == NULL) {
        return;
    }
    ghostty_surface_mouse_pos(_surface, x, y, (ghostty_input_mods_e)mods);
}

- (BOOL)mouseButtonPressed:(BOOL)pressed button:(int)button mods:(int)mods {
    if (_surface == NULL) {
        return NO;
    }
    return ghostty_surface_mouse_button(
        _surface,
        pressed ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE,
        (ghostty_input_mouse_button_e)button,
        (ghostty_input_mods_e)mods
    );
}

- (void)mouseScrollX:(double)x y:(double)y precise:(BOOL)precise mods:(int)mods {
    if (_surface == NULL) {
        return;
    }
    // ghostty_input_scroll_mods_t is a packed int from input/mouse.zig. We
    // treat bit 0 as the "precise/momentum" flag for two-finger trackpad
    // gestures; higher bits are unused for our pass-through. Modifier keys
    // (Shift/Ctrl/...) are *not* part of this field — ghostty reads them
    // separately when interpreting the scroll.
    (void)mods;
    ghostty_input_scroll_mods_t scrollMods = precise ? 1 : 0;
    ghostty_surface_mouse_scroll(_surface, x, y, scrollMods);
}

- (LitterGhosttySurfaceMetrics)surfaceMetrics {
    LitterGhosttySurfaceMetrics out = {0};
    if (_surface == NULL) {
        return out;
    }
    ghostty_surface_size_s size = ghostty_surface_size(_surface);
    out.columns = size.columns;
    out.rows = size.rows;
    out.widthPx = size.width_px;
    out.heightPx = size.height_px;
    out.cellWidthPx = size.cell_width_px;
    out.cellHeightPx = size.cell_height_px;
    return out;
}

- (nullable NSString *)readTextFromRow:(uint32_t)startRow
                                 column:(uint32_t)startCol
                                  toRow:(uint32_t)endRow
                                 column:(uint32_t)endCol {
    if (_surface == NULL) {
        return nil;
    }
    ghostty_selection_s selection = {0};
    selection.top_left.tag = GHOSTTY_POINT_VIEWPORT;
    selection.top_left.coord = GHOSTTY_POINT_COORD_EXACT;
    selection.top_left.x = startCol;
    selection.top_left.y = startRow;
    selection.bottom_right.tag = GHOSTTY_POINT_VIEWPORT;
    selection.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT;
    selection.bottom_right.x = endCol;
    selection.bottom_right.y = endRow;
    selection.rectangle = false;

    ghostty_text_s text = {0};
    if (!ghostty_surface_read_text(_surface, selection, &text)) {
        return nil;
    }
    @try {
        if (text.text == NULL || text.text_len == 0) {
            return nil;
        }
        return [[NSString alloc] initWithBytes:text.text
                                        length:(NSUInteger)text.text_len
                                      encoding:NSUTF8StringEncoding];
    } @finally {
        ghostty_surface_free_text(_surface, &text);
    }
}

static ghostty_input_key_e LitterGhosttyKeyToGhosttyKey(LitterGhosttyKey key) {
    switch (key) {
        case LitterGhosttyKeyEnter:      return GHOSTTY_KEY_ENTER;
        case LitterGhosttyKeyTab:        return GHOSTTY_KEY_TAB;
        case LitterGhosttyKeyBackspace:  return GHOSTTY_KEY_BACKSPACE;
        case LitterGhosttyKeyEscape:     return GHOSTTY_KEY_ESCAPE;
        case LitterGhosttyKeySpace:      return GHOSTTY_KEY_SPACE;
        case LitterGhosttyKeyArrowUp:    return GHOSTTY_KEY_ARROW_UP;
        case LitterGhosttyKeyArrowDown:  return GHOSTTY_KEY_ARROW_DOWN;
        case LitterGhosttyKeyArrowLeft:  return GHOSTTY_KEY_ARROW_LEFT;
        case LitterGhosttyKeyArrowRight: return GHOSTTY_KEY_ARROW_RIGHT;
        case LitterGhosttyKeyPageUp:     return GHOSTTY_KEY_PAGE_UP;
        case LitterGhosttyKeyPageDown:   return GHOSTTY_KEY_PAGE_DOWN;
        case LitterGhosttyKeyHome:       return GHOSTTY_KEY_HOME;
        case LitterGhosttyKeyEnd:        return GHOSTTY_KEY_END;
        case LitterGhosttyKeyDelete:     return GHOSTTY_KEY_DELETE;
        case LitterGhosttyKeyInsert:     return GHOSTTY_KEY_INSERT;
        case LitterGhosttyKeyUnidentified:
        default:                         return GHOSTTY_KEY_UNIDENTIFIED;
    }
}

- (BOOL)dispatchKeyAction:(int)action
                      key:(LitterGhosttyKey)key
                     mods:(int)mods
                     text:(NSString *)text
                composing:(BOOL)composing {
    if (_surface == NULL) {
        return NO;
    }
    ghostty_input_key_s event = {0};
    event.action = (ghostty_input_action_e)action;
    event.mods = (ghostty_input_mods_e)mods;
    event.consumed_mods = (ghostty_input_mods_e)0;
    event.keycode = (uint32_t)LitterGhosttyKeyToGhosttyKey(key);
    const char *cstr = text != nil ? [text UTF8String] : NULL;
    event.text = cstr;
    event.unshifted_codepoint = 0;
    event.composing = composing ? true : false;
    return ghostty_surface_key(_surface, event);
}

- (void)sendText:(NSString *)text {
    if (_surface == NULL || text.length == 0) {
        return;
    }
    const char *utf8 = [text UTF8String];
    if (utf8 == NULL) {
        return;
    }
    ghostty_surface_text(_surface, utf8, strlen(utf8));
}

- (void)setPreeditText:(NSString *)text {
    if (_surface == NULL) {
        return;
    }
    if (text == nil || text.length == 0) {
        ghostty_surface_preedit(_surface, NULL, 0);
        return;
    }
    const char *utf8 = [text UTF8String];
    if (utf8 == NULL) {
        return;
    }
    ghostty_surface_preedit(_surface, utf8, strlen(utf8));
}

- (void)keyboardChanged {
    if (_app != NULL) {
        ghostty_app_keyboard_changed(_app);
    }
}

- (BOOL)applyConfigAtPath:(NSString *)path error:(NSError **)error {
    if (_app == NULL || _surface == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Ghostty surface not ready"}];
        }
        return NO;
    }
    if (path.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty config path"}];
        }
        return NO;
    }

    ghostty_config_t config = ghostty_config_new();
    if (config == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LitterGhosttyErrorDomain
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"ghostty_config_new failed"}];
        }
        return NO;
    }
    ghostty_config_load_file(config, [path fileSystemRepresentation]);
    ghostty_config_finalize(config);
    ghostty_app_update_config(_app, config);
    ghostty_surface_update_config(_surface, config);
    float fontSize = 0.0f;
    if (ghostty_config_get(config, &fontSize, "font-size", 9)) {
        NSString *actionString = [NSString stringWithFormat:@"set_font_size:%g", fontSize];
        const char *action = actionString.UTF8String;
        (void)ghostty_surface_binding_action(
            _surface,
            action,
            [actionString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]
        );
    }
    if (_view != nil) {
        CGFloat scale = _view.window.screen.scale ?: UIScreen.mainScreen.scale;
        [self resizeToWidth:_view.bounds.size.width height:_view.bounds.size.height scale:scale];
    }
    ghostty_surface_render(_surface);
    ghostty_config_free(config);
    return YES;
}

@end

static void LitterGhosttyResizeBackingLayers(UIView *view, CGFloat scale) {
    CGRect bounds = view.bounds;
    view.contentScaleFactor = scale;
    view.layer.frame = bounds;
    view.layer.contentsScale = scale;
    view.layer.needsDisplayOnBoundsChange = YES;
    if ([view.layer isKindOfClass:CAMetalLayer.class]) {
        CAMetalLayer *metalLayer = (CAMetalLayer *)view.layer;
        metalLayer.contentsScale = scale;
        metalLayer.drawableSize = CGSizeMake(
            MAX(1.0, floor(bounds.size.width * scale)),
            MAX(1.0, floor(bounds.size.height * scale))
        );
    }
    for (CALayer *layer in view.layer.sublayers) {
        layer.frame = bounds;
        layer.contentsScale = scale;
        layer.needsDisplayOnBoundsChange = YES;
    }
}

static dispatch_queue_t LitterGhosttyDestroyQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL,
            QOS_CLASS_UTILITY,
            0
        );
        queue = dispatch_queue_create("com.sigkitten.litter.ghostty.destroy", attr);
    });
    return queue;
}

static LitterGhosttyTerminal *LitterGhosttyTerminalFromUserdata(void *userdata) {
    if (userdata == NULL) {
        return nil;
    }
    return (__bridge LitterGhosttyTerminal *)userdata;
}

static void LitterGhosttyWakeup(void *userdata) {
    LitterGhosttyTerminal *terminal = LitterGhosttyTerminalFromUserdata(userdata);
    if (terminal == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [terminal draw];
    });
}

static bool LitterGhosttyAction(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action) {
    (void)app;
    (void)target;
    (void)action;
    return false;
}

static bool LitterGhosttyReadClipboard(void *userdata, ghostty_clipboard_e clipboard, void *request) {
    (void)userdata;
    (void)clipboard;
    (void)request;
    return false;
}

static void LitterGhosttyConfirmReadClipboard(void *userdata, const char *title, void *request, ghostty_clipboard_request_e requestType) {
    (void)userdata;
    (void)title;
    (void)request;
    (void)requestType;
}

static void LitterGhosttyWriteClipboard(void *userdata, ghostty_clipboard_e clipboard, const ghostty_clipboard_content_s *contents, size_t count, bool confirm) {
    (void)userdata;
    (void)clipboard;
    (void)confirm;

    if (contents == NULL || count == 0) {
        return;
    }

    for (size_t index = 0; index < count; index += 1) {
        const ghostty_clipboard_content_s item = contents[index];
        if (item.mime == NULL || item.data == NULL) {
            continue;
        }
        if (strcmp(item.mime, "text/plain") == 0) {
            UIPasteboard.generalPasteboard.string = [NSString stringWithUTF8String:item.data];
            return;
        }
    }
}

static void LitterGhosttyCloseSurface(void *userdata, bool processActive) {
    (void)processActive;
    LitterGhosttyTerminal *terminal = LitterGhosttyTerminalFromUserdata(userdata);
    if (terminal == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [terminal invalidate];
    });
}

static void LitterGhosttyExternalWrite(void *userdata, const uint8_t *data, uintptr_t length) {
    LitterGhosttyTerminal *terminal = LitterGhosttyTerminalFromUserdata(userdata);
    if (terminal == nil || terminal.inputHandler == nil || data == NULL || length == 0) {
        return;
    }

    NSData *payload = [NSData dataWithBytes:data length:(NSUInteger)length];
    terminal.inputHandler(payload);
}
