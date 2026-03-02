#!/usr/bin/env bun
import { commandExists, ensurePythonDevEnvironment, runCommand, section, zigExecutable } from "./_lib";

interface Task {
  name: string;
  command: string;
  args: string[];
  required: boolean;
}

const python = ensurePythonDevEnvironment();

const tasks: Task[] = [
  {
    name: "python-tests",
    command: python,
    args: ["-m", "pytest", "-q"],
    required: true,
  },
  {
    name: "js-smoke",
    command: "bun",
    args: ["test", "wrappers/js/tests/smoke.test.ts"],
    required: true,
  },
  {
    name: "zig-tests",
    command: zigExecutable(),
    args: ["build", "test"],
    required: true,
  },
];

let failures = 0;
for (const task of tasks) {
  if (!commandExists(task.command)) {
    if (task.required) {
      console.error(`${task.command} is required for ${task.name} but is not available`);
      failures += 1;
    } else {
      console.warn(`${task.command} is not available; skipping optional task ${task.name}`);
    }
    continue;
  }

  section(`Running ${task.name}`);
  const result = runCommand(task.command, task.args, { allowFailure: true });
  if (result.stdout.trim().length > 0) {
    console.log(result.stdout.trim());
  }
  if (result.stderr.trim().length > 0) {
    console.error(result.stderr.trim());
  }
  if (result.code !== 0) {
    if (task.required) {
      failures += 1;
    } else {
      console.warn(`${task.name} failed but is optional in scaffold mode`);
    }
  }
}

process.exit(failures === 0 ? 0 : 1);
