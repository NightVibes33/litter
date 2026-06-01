#ifndef LITTER_EMEXDE_COMPILER_PREFIX_H
#define LITTER_EMEXDE_COMPILER_PREFIX_H

/*
 Xcode 26 can build Foundation modules while emexDE header search paths expose
 LindChain/ProcEnvironment/Surface/limits.h. That local header intentionally is
 not the SDK limits header, so provide the Darwin long-limit macros before
 Foundation expands NSIntegerMax.
 */
#ifndef LONG_MAX
#define LONG_MAX __LONG_MAX__
#endif

#ifndef LONG_MIN
#define LONG_MIN (-__LONG_MAX__ - 1L)
#endif

#endif /* LITTER_EMEXDE_COMPILER_PREFIX_H */
