#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LitterGhosttyInputHandler)(NSData *data);

/// Snapshot of the Ghostty surface grid + cell metrics (returned by
/// `ghostty_surface_size`). Pixel dimensions are framebuffer pixels (already
/// multiplied by the content scale); cell sizes are floored to whole pixels.
typedef struct {
    uint16_t columns;
    uint16_t rows;
    uint32_t widthPx;
    uint32_t heightPx;
    uint32_t cellWidthPx;
    uint32_t cellHeightPx;
} LitterGhosttySurfaceMetrics;

@interface LitterGhosttyTerminal : NSObject

@property (nonatomic, copy, nullable) LitterGhosttyInputHandler inputHandler;

- (nullable instancetype)initWithView:(UIView *)view error:(NSError **)error;
- (void)resizeToWidth:(CGFloat)width height:(CGFloat)height scale:(CGFloat)scale;
- (void)writeOutput:(NSData *)data;
- (NSString *)visibleText;
- (void)setOcclusion:(BOOL)occluded;
- (void)setFocused:(BOOL)focused;
- (BOOL)applyConfigAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)mouseCaptured;
- (void)mousePosX:(double)x y:(double)y mods:(int)mods;
- (BOOL)mouseButtonPressed:(BOOL)pressed button:(int)button mods:(int)mods;
- (void)mouseScrollX:(double)x y:(double)y precise:(BOOL)precise mods:(int)mods;

/// Read live surface metrics (columns, rows, cell pixel dimensions).
/// All-zero return means the surface isn't ready yet.
- (LitterGhosttySurfaceMetrics)surfaceMetrics;

/// Read text from a viewport-relative cell range. `startRow`/`endRow` are
/// clamped by Ghostty to the visible viewport. Returns `nil` if the surface
/// isn't ready or the range is empty.
- (nullable NSString *)readTextFromRow:(uint32_t)startRow
                                 column:(uint32_t)startCol
                                  toRow:(uint32_t)endRow
                                 column:(uint32_t)endCol;

// Stable identifiers for the common Ghostty keys we pass through. The C
// enum these map to (`ghostty_input_key_e`) is internal to the bridge; the
// integer order may change when the upstream Ghostty header bumps. Use
// these constants instead of hardcoding raw enum values in Swift.
typedef NS_ENUM(int, LitterGhosttyKey) {
    LitterGhosttyKeyUnidentified = 0,
    LitterGhosttyKeyEnter,
    LitterGhosttyKeyTab,
    LitterGhosttyKeyBackspace,
    LitterGhosttyKeyEscape,
    LitterGhosttyKeySpace,
    LitterGhosttyKeyArrowUp,
    LitterGhosttyKeyArrowDown,
    LitterGhosttyKeyArrowLeft,
    LitterGhosttyKeyArrowRight,
    LitterGhosttyKeyPageUp,
    LitterGhosttyKeyPageDown,
    LitterGhosttyKeyHome,
    LitterGhosttyKeyEnd,
    LitterGhosttyKeyDelete,
    LitterGhosttyKeyInsert,
};

// Key dispatch. `action` 0=release, 1=press, 2=repeat.
// `key` is a `LitterGhosttyKey` from the table above; the bridge translates
// it to the real ghostty enum value before calling `ghostty_surface_key`.
// `text` is the platform-decoded character(s), nullable.
- (BOOL)dispatchKeyAction:(int)action
                      key:(LitterGhosttyKey)key
                     mods:(int)mods
                     text:(NSString *_Nullable)text
                composing:(BOOL)composing;
// Commit text (writes to terminal); preedit goes through `setPreeditText:`.
- (void)sendText:(NSString *)text;
- (void)setPreeditText:(NSString *_Nullable)text;
// Notify Ghostty that the platform keyboard configuration changed (layout, etc).
- (void)keyboardChanged;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
