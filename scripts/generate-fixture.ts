#!/usr/bin/env bun
import { ensureFixtures } from "./_fixtures";
import { resolvePath, section } from "./_lib";

const force = process.argv.includes("--force");

section("Fixtures");
ensureFixtures(force);
console.log(`Fixtures ready: ${resolvePath("bench", "fixtures")}`);
