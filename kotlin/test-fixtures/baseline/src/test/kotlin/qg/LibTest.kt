package qg

import kotlin.test.Test
import kotlin.test.assertEquals

class LibTest {
    @Test
    fun addPositive() {
        assertEquals(5, add(2, 3))
    }

    @Test
    fun addNegative() {
        assertEquals(-2, add(-1, -1))
    }

    @Test
    fun multiplyPositive() {
        assertEquals(12, multiply(3, 4))
    }

    @Test
    fun multiplyZero() {
        assertEquals(0, multiply(0, 5))
    }
}
