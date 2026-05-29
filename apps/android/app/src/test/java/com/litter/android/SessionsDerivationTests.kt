package com.litter.android

import com.litter.android.ui.sessions.SessionsDerivation
import com.litter.android.ui.sessions.WorkspaceSortMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionsDerivationTests {

    @Test
    fun `normalizedCwd trims trailing slash and lowercases`() {
        assertEquals("/home/user/projects", SessionsDerivation.normalizedCwd("/home/user/projects/"))
        assertEquals("/home/user/projects", SessionsDerivation.normalizedCwd("/home/user/Projects"))
    }

    @Test
    fun `normalizedCwd returns tilde for null or blank`() {
        assertEquals("~", SessionsDerivation.normalizedCwd(null))
        assertEquals("~", SessionsDerivation.normalizedCwd(""))
    }

    // Note: Full derivation tests require constructing AppSessionSummary objects,
    // which depend on UniFFI-generated types. These tests would need the native
    // library loaded. Integration tests should cover:
    //
    // - derive() builds correct parent→child tree from parentThreadId
    // - derive() groups sessions by (serverId + cwd)
    // - derive() filters by server ID
    // - derive() filters by fork-only mode
    // - derive() search matches title, cwd, model, agentDisplayLabel
    // - derive() sorts by RECENT (max updatedAt desc)
    // - derive() sorts by NAME (workspaceLabel asc)
    // - derive() handles empty input
    // - Orphaned children become root nodes
}
