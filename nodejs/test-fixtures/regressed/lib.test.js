import { test } from "node:test";
import assert from "node:assert";
import { add, multiply } from "./lib.js";

// REGRESSION test: assertion errada de proposito.
test("add failing on purpose", () => {
  assert.strictEqual(add(2, 3), 999);
});

test("multiply positive", () => {
  assert.strictEqual(multiply(3, 4), 12);
});
