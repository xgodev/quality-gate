package qg

import kotlin.test.Test
import kotlin.test.assertEquals

class LibTest {
    // REGRESSION test: assertion errada de proposito.
    @Test
    fun addFailingOnPurpose() {
        assertEquals(999, add(2, 3))
    }

    @Test
    fun multiplyPositive() {
        assertEquals(12, multiply(3, 4))
    }
}
