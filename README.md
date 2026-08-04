# Roblox TestKit

A standalone, headless test framework for Roblox Lua modules that runs **outside of Roblox Studio**. It mocks the most common Roblox APIs so you can run your tests in CI, on a developer machine without Studio, or anywhere you have Lua 5.1.

## Why does this exist?

Roblox modules are full of calls like `game:GetService("Players")`, `Instance.new("Part")`, and `script.Parent`. None of those exist in plain Lua 5.1, so you cannot run them directly in a normal test runner. Roblox TestKit solves that by:

1. Providing lightweight mocks for `game`, `workspace`, `script`, `Instance`, and common services.
2. Shipping a BDD-style test framework (`describe` / `it` / `expect`).
3. Providing a CLI runner that loads your spec, injects the mocks, and reports results.
4. Supporting colored terminal output and JUnit XML for CI systems.

## Requirements

- [Lua 5.1](https://www.lua.org/download.html) (`lua` or `lua5.1` on your PATH)

No Roblox Studio, no Rojo, no external Lua libraries.

## Installation

Clone the repository:

```bash
git clone https://github.com/SuperInstance/roblox-testkit.git
cd roblox-testkit
```

There is no Python/pip dependency — this is a pure Lua project. You can run it directly from the clone.

### Optional: add a global command

Create a symlink or copy the wrapper script to somewhere on your PATH:

```bash
chmod +x roblox-testkit
ln -s "$(pwd)/roblox-testkit" /usr/local/bin/roblox-testkit
```

Then run from anywhere:

```bash
roblox-testkit path/to/spec.lua
```

## Writing your first test

Create a Roblox module, for example `example/MyModule.lua`:

```lua
local MyModule = {}

function MyModule.add(a, b)
    return a + b
end

function MyModule.getStorage()
    return game:GetService("ReplicatedStorage")
end

function MyModule.createPart(name)
    local part = Instance.new("Part")
    part.Name = name
    part.Parent = workspace
    return part
end

return MyModule
```

Create a spec file, for example `example/spec_example.lua`:

```lua
local testkit = require("testkit")

-- Load the module under test with its own mocked script instance.
local MyModule = testkit.loadModule("example/MyModule.lua")

testkit.describe("MyModule", function()
    testkit.it("adds two numbers", function()
        testkit.expect(MyModule.add(2, 3)):equals(5)
    end)

    testkit.it("returns ReplicatedStorage", function()
        local storage = MyModule.getStorage()
        testkit.expect(storage):isNot():isNil()
        testkit.expect(storage.Name):equals("ReplicatedStorage")
    end)

    testkit.it("creates a Part in Workspace", function()
        local part = MyModule.createPart("TestBlock")
        testkit.expect(part.Name):equals("TestBlock")
        testkit.expect(part.Parent.Name):equals("Workspace")
        testkit.expect(part:IsA("BasePart")):equals(true)
    end)
end)
```

Run it:

```bash
lua src/runner.lua example/spec_example.lua
```

Output:

```
Roblox TestKit
========================================
[PASS] MyModule > adds two numbers (0.000s)
[PASS] MyModule > returns ReplicatedStorage (0.000s)
[PASS] MyModule > creates a Part in Workspace (0.000s)
----------------------------------------
3 tests, 3 passed, 0 failed, 0 skipped (0.001s)
```

## CLI runner

```bash
lua src/runner.lua [options] <spec-file>
```

### Options

| Option | Description |
|--------|-------------|
| `--junit <path>` | Write a JUnit XML report to `<path>`. |
| `--no-color` | Disable ANSI colors in terminal output. |
| `--help`, `-h` | Show usage help. |

### Examples

```bash
# Basic run
lua src/runner.lua example/spec_example.lua

# JUnit XML for CI
lua src/runner.lua --junit results.xml example/spec_example.lua

# Disable colors
lua src/runner.lua --no-color example/spec_example.lua
```

The runner exits with code `0` when all tests pass and `1` when any test fails.

## API reference

### `testkit.describe(name, fn)`

Defines a test suite. Suites can be nested.

```lua
testkit.describe("MyService", function()
    testkit.describe("validation", function()
        testkit.it("rejects bad input", function() end)
    end)
end)
```

### `testkit.it(name, fn)`

Defines a single test case.

### `testkit.beforeAll(fn)` / `testkit.afterAll(fn)`

Run once per `describe` block, before/after all of its tests and nested suites.

### `testkit.beforeEach(fn)` / `testkit.afterEach(fn)`

Run before/after each test in the current `describe` block and all nested blocks.

### `testkit.expect(value)`

Creates an assertion object for `value`. All assertions use Lua method syntax (`:`).

```lua
testkit.expect(42):equals(42)
testkit.expect({a = 1}):deepEquals({a = 1})
testkit.expect(nil):isNil()
testkit.expect("hello"):isType("string")
testkit.expect(function() error("oops") end):throws("oops")
```

#### Assertions

| Assertion | Description |
|-----------|-------------|
| `:equals(expected)` | Reference equality (`==`). |
| `:toEqual(expected)` | Alias for `:equals`. |
| `:toBe(expected)` | Alias for `:equals`. |
| `:deepEquals(expected)` | Deep table equality. |
| `:toDeepEqual(expected)` | Alias for `:deepEquals`. |
| `:isNil()` | Value is `nil`. |
| `:toBeNil()` | Alias for `:isNil`. |
| `:isType(typeName)` | `type(value) == typeName`. |
| `:toBeA(typeName)` | Alias for `:isType`. |
| `:throws(message?)` | Expects a function to error. If `message` is provided, the error must contain it. |
| `:toThrow(message?)` | Alias for `:throws`. |

#### Negation

Chain `:isNot()`, `:never()`, or `:toNot()` before the assertion:

```lua
testkit.expect(value):isNot():equals(5)
testkit.expect(value):never():isNil()
```

### `testkit.loadModule(path)`

Loads a `.lua` module with the Roblox mocks injected and a dedicated `script` instance. Use this to load the module you want to test.

```lua
local MyModule = testkit.loadModule("src/MyModule.lua")
```

The returned module can use `game`, `Instance`, `workspace`, `script`, and any mocked service just like it would inside Studio.

## Mocked Roblox APIs

`src/roblox_mock.lua` provides realistic table-based mocks for:

- `game` (DataModel) with `GetService`, `IsLoaded`, `PlaceId`, `JobId`, etc.
- `workspace`
- `script`
- `Instance` with `new`, `FindFirstChild`, `FindFirstChildOfClass`, `FindFirstChildWhichIsA`, `GetChildren`, `GetDescendants`, `Clone`, `Destroy`, `WaitForChild`, `GetAttribute`, `SetAttribute`, `IsA`, `IsDescendantOf`, `GetFullName`, and `Parent` hierarchy support.
- `Players`
- `ReplicatedStorage`
- `ServerScriptService`
- `ServerStorage`
- `Lighting`
- `RunService` (with `Heartbeat`, `RenderStepped`, `Stepped` events)
- `TweenService`
- `Debris`
- `CollectionService`
- `TextService`
- `HttpService` (with a simple JSON encoder/decoder)

The mock environment is installed into the global table (`_G`) by the runner, so any module loaded by the spec sees the same `game`, `workspace`, and `Instance` globals.

## Migration from Roblox TestService

If you are coming from Roblox `TestService` scripts, the migration is straightforward:

1. Move each `TestService` script into a `*.spec.lua` file next to the module it tests.
2. Replace `print("success")` / `error("fail")` style checks with `testkit.expect(...)`.
3. Load the module under test with `testkit.loadModule("path/to/Module.lua")`.
4. Run the spec with `lua src/runner.lua path/to/Module.spec.lua`.
5. Add the run command to your CI workflow.

Before:

```lua
-- Roblox TestService script
local Module = require(game.ReplicatedStorage.Module)
local result = Module.add(1, 2)
if result ~= 3 then
    error("add failed")
end
print("add passed")
```

After:

```lua
local testkit = require("testkit")
local Module = testkit.loadModule("src/Module.lua")

testkit.describe("Module", function()
    testkit.it("adds numbers", function()
        testkit.expect(Module.add(1, 2)):equals(3)
    end)
end)
```

## CI integration

Because the runner works with plain Lua 5.1, it fits into any CI pipeline. Example GitHub Actions workflow:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Lua
        run: sudo apt-get update && sudo apt-get install -y lua5.1
      - name: Run tests
        run: lua src/runner.lua example/spec_example.lua
```

For JUnit XML output that many CI systems can display:

```yaml
- name: Run tests
  run: lua src/runner.lua --junit test-results.xml example/spec_example.lua
- name: Upload results
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-results.xml
```

## License

MIT — see [LICENSE](LICENSE).
