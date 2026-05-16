package qg;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class LibTest {
  @Test
  void addPositive() {
    assertEquals(5, Lib.add(2, 3));
  }

  @Test
  void addNegative() {
    assertEquals(-2, Lib.add(-1, -1));
  }

  @Test
  void multiplyPositive() {
    assertEquals(12, Lib.multiply(3, 4));
  }

  @Test
  void multiplyZero() {
    assertEquals(0, Lib.multiply(0, 5));
  }
}
