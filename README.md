# assert-no-unexpected-changes

This action asserts that your desktop app, CLI tool or anything else makes no unexpected changes.

**Table of Contents**

- [Why it was built](#why-it-was-built)
- [What it does](#what-it-does)
- [How to use](#how-to-use)
- [License](#license)

## Why it was built

This GitHub Action was built to verify that code an AI wrote does nothing "strange", treating the code as a black box.

I was about to post on social media that I had built a desktop app when a thought stopped me: if I say an AI built it, some people are going to worry that it will do something strange to their machine.
So I asked myself what "something strange" would actually be, and the first answer that came to mind was files deleted or rewritten behind their back.
Nothing seemed to exist that would catch it, and if a thing does not exist, you may as well make it, so I wrote this action.

## What it does

This action prepares two Docker containers: one runs only the `arrange` phase, and the other runs both the `arrange` and `act` phases.
More precisely, it writes a Dockerfile that starts from `image`, copies your checkout into `workdir` with `COPY` and runs the `arrange` phase, and builds an image from it.
From that image it starts two containers, runs the `act` phase in only one of them, and runs `docker diff` on both.
Then it checks the difference between the two containers against `allowlist` to detect violations.
If there are any, the step fails with an error like this:

```text
Error: 2 change(s) outside the allowlist
A /unexpected
D /expected
```

`A` means created, `C` means changed and `D` means deleted.

## How to use

```yaml
# Please replace ${checkout-latest-version} and ${this-action-latest-version} with the latest version numbers, such as `v1`.
runs-on: ubuntu-latest # Must be a Linux runner.
steps:
  - uses: actions/checkout@${checkout-latest-version}
  - uses: yuyuyuyuyu-dev/assert-no-unexpected-changes@${this-action-latest-version}
    with:
      arrange: | # Optional. Run in `sh`. Its changes are not checked.
        some-setup-commands
        for-example-install-the-dependencies
        build-the-thing
        or-anything-else
      act: | # Run in `sh`. Its changes are checked.
        some-commands-to-verify
        for-example-run-tests
        ./the-built-executable
        or-anything-else
      allowlist: | # Optional. Absolute paths that may change, one per line. `*` also matches `/`.
        /this/path/alone
        /everything/below/this/*
      workdir: /path/to/workdir # Optional. Defaults to `/workdir`. Changes under it are not checked.
      image: some-image:a-tag # Optional. Defaults to Ubuntu. Must run as root.
```

## License

[MIT](LICENSE)
