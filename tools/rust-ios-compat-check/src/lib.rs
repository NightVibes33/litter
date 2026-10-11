//! Compile the mobile graph's pure Rust Apple ABI dependencies before the SDK build.

pub fn current_thread_count() -> Option<std::num::NonZeroUsize> {
    num_threads::num_threads()
}
