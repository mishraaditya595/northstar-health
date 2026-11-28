package `in`.beyondrep.wear.core.link

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DataLayerPathsTest {
    @Test
    fun pathsRoundTrip() {
        assertEquals("/beyondrep/context/plans_snapshot", DataLayerPaths.context("plans_snapshot"))
        assertEquals("/beyondrep/queue/phone/abc", DataLayerPaths.phoneQueue("abc"))
        assertEquals("/beyondrep/queue/watch/abc", DataLayerPaths.watchQueue("abc"))
        assertEquals(Route.Context("plans_snapshot"), DataLayerPaths.parse(DataLayerPaths.context("plans_snapshot")))
        assertEquals(Route.PhoneQueued("abc"), DataLayerPaths.parse(DataLayerPaths.phoneQueue("abc")))
        assertEquals(Route.WatchQueued("abc"), DataLayerPaths.parse(DataLayerPaths.watchQueue("abc")))
    }

    @Test
    fun otherPrefixesAndEmptyOrNestedNamesAreRejected() {
        assertNull(DataLayerPaths.parse("/other/context/x"))
        assertNull(DataLayerPaths.parse("/beyondrep/context/"))
        assertNull(DataLayerPaths.parse("/beyondrep/context"))
        assertNull(DataLayerPaths.parse("/beyondrep/queue/phone/"))
        assertNull(DataLayerPaths.parse("/beyondrep/queue/phone/a/b"))
        assertNull(DataLayerPaths.parse("/beyondrep/queue/other/a"))
        assertNull(DataLayerPaths.parse("beyondrep/context/x"))
        assertNull(DataLayerPaths.parse(""))
    }
}
