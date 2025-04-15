# How to Install

Navigate to your project directory. e.g., `cd my_awesome_project`

### Install the Nightly Version

Fetch **cfp** as external package dependency by running:

```sh
zig fetch --save \
https://github.com/bitlaab-bolt/cfp/archive/refs/heads/main.zip
```

### Install the Release Version

Fetch **cfp** as external package dependency by running:

```sh
zig fetch --save \
https://github.com/bitlaab-bolt/cfp/archive/refs/tags/v0.0.0.zip
```

Make sure to edit `v0.0.0` with the latest release version.

## Import Module

Now, import **cfp** as external package module to your project by coping following code:

```zig title="build.zig"
const cfp = b.dependency("cfp", .{});
exe.root_module.addImport("cfp", cfp.module("cfp"));
lib.root_module.addImport("cfp", cfp.module("cfp"));
```
