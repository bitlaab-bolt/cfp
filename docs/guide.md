# Developer Guide

If you are using previous release of Cfp for some reason, you can generate documentation for that release by following these steps:

- Install [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/getting-started/) on your platform.

- Download and extract `Source code (zip)` for your target release at [**Cfp Repo**](https://github.com/bitlaab-bolt/cfp)

- Now, `cd` into your release directory and run: `mkdocs serve`

## Generate Code Documentation

To generate Zig's API documentation, navigate to your project directory and run:

```sh
zig build-lib -femit-docs=docs/zig-docs src/root.zig
```

Now, clean up any unwanted generated files and make sure to link `zig-docs/index.html` to your `reference.md` file.
