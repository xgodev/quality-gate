package qg;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class LibTest {
  // REGRESSION test: assertion errada de proposito.
  @Test
  void addFailingOnPurpose() {
    assertEquals(999, Lib.add(2, 3));
  }

  @Test
  void multiplyPositive() {
    assertEquals(12, Lib.multiply(3, 4));
  }
}
