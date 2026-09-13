# assert-no-unexpected-changes

This action asserts that your desktop app, CLI tool or anything else makes no unexpected changes.

**Table of Contents**

- [Why it was built](#why-it-was-built)
- [What it does](#what-it-does)
- [How to use](#how-to-use)
- [License](#license)

## Why it was built

I want people to be able to trust code an AI wrote, even if it stays a black box to them.

I was about to post on social media that I had built a desktop app when a thought stopped me: if I say an AI built it, some people are going to worry that it will do something strange to their machine.
So I asked myself what "something strange" would actually be, and the first answer that came to mind was files deleted or rewritten behind their back.
Nothing seemed to exist that would catch it, and if a thing does not exist, you may as well make it, so I wrote this action.

## What it does

Under the hood, this action uses `docker diff`.
First it writes a Dockerfile that copies your checkout into `workdir` and runs `arrange`, and builds an image from it.
Whatever `arrange` changes becomes part of the image and is not checked.
Then it runs two containers from the image it built — one that does nothing but start, and one that goes on to run `act` — and compares their diffs to detect any file or directory created, changed or deleted.
Changes under `workdir` or matched by `allowlist` are ignored.
If anything else is found, the step fails and lists each change in the log and the job summary, marked `A` for created, `C` for changed or `D` for deleted.
Docker containers in GitHub Actions work on Linux runners only, so the job has to run on one, and `arrange` and `act` have to work on Linux.

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
        run-execution-binary
        or-anything-else
      allowlist: | # Optional. Absolute paths that may change, one per line. `*` also matches `/`.
        /this/path/alone
        /everything/below/this/*
      workdir: /path/to/workdir # Optional. Defaults to `/workdir`. Changes under it are not checked.
      image: some-image:a-tag # Optional. Defaults to Ubuntu. Must run as root.
```

## License

[MIT](LICENSE)
