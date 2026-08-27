// Pinned from forcequitOS/bad_query @ 73ef6da1adabef0982fd00e36cb85f21b8f8194a
// Unsigned/sideload builds only. This source is not part of the TestFlight target.

#ifndef LITTER_BAD_QUERY_H
#define LITTER_BAD_QUERY_H

#include <stdbool.h>
#include <stdint.h>

int64_t bad_query(char *path, bool create, char *group_identifier, bool is_group);
char *bad_query_list(char *path, int64_t max_inode);
void bad_query_release(int64_t handle);

#endif
