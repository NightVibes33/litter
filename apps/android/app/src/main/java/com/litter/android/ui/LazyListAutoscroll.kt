package com.litter.android.ui

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow

internal fun LazyListState.isNearListBottom(bufferItems: Int = 2): Boolean {
    val info = layoutInfo
    if (info.totalItemsCount == 0) return true
    val lastVisible = info.visibleItemsInfo.lastOrNull() ?: return false
    return lastVisible.index >= info.totalItemsCount - bufferItems
}

@Composable
internal fun rememberStickyFollowTail(
    listState: LazyListState,
    resetKey: Any?,
    bufferItems: Int = 2,
    initialValue: Boolean = true,
): Boolean {
    var shouldFollowTail by remember(resetKey) { mutableStateOf(initialValue) }

    LaunchedEffect(listState, resetKey, bufferItems) {
        snapshotFlow { listState.isScrollInProgress }
            .collect { isScrolling ->
                if (!isScrolling) {
                    shouldFollowTail = listState.isNearListBottom(bufferItems)
                }
            }
    }

    return shouldFollowTail
}
