import { test } from "node:test";
import assert from "node:assert";
import { add, multiply } from "./lib.js";

test("add positive", () => {
  assert.strictEqual(add(2, 3), 5);
});

test("add negative", () => {
  assert.strictEqual(add(-1, -1), -2);
});

test("multiply positive", () => {
  assert.strictEqual(multiply(3, 4), 12);
});

test("multiply zero", () => {
  assert.strictEqual(multiply(0, 5), 0);
});
