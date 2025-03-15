# How to Install

## Installation

Navigate to your project directory. e.g., `cd my_awesome_project`

### Install the Nightly Version

Fetch cfp as zig package dependency by running:

```sh
zig fetch --save \
https://github.com/bitlaab-bolt/cfp/archive/refs/heads/main.zip
```

### Install a Release Version

Fetch cfp as zig package dependency by running:

```sh
zig fetch --save \
https://github.com/bitlaab-bolt/cfp/archive/refs/tags/"your-version".zip
```

Add cfp as external package module to your project by coping following code on your project.

```zig title="build.zig"
const cfp = b.dependency("cfp", .{});
exe.root_module.addImport("cfp", cfp.module("cfp"));
lib.root_module.addImport("cfp", cfp.module("cfp"));
```
