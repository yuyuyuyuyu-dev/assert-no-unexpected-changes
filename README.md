# assert-no-unexpected-changes

This action asserts that your desktop app, CLI tool or anything else makes no unexpected changes.

## Why

I was about to post on social media that I had built a desktop app when a thought stopped me: if I say an AI built it, some people are going to worry that it will do something strange to their machine.
So I asked myself what "something strange" would actually be, and the first answer that came was files deleted or rewritten behind their back.
Nothing seemed to exist that catches that, and if a thing does not exist you may as well make it, so I wrote this action.

## What

Under the hood, this action uses `docker diff`.
First it writes a Dockerfile holding the preparation steps it was given as `inputs`, and builds an image from it.
Then it runs two containers from the image it built — one that does nothing but start, and one that goes on to run the command to be verified — and compares their diffs to detect any file or directory created, changed or deleted unexpectedly.

## How

```yaml
# Please replace ${latest-version} with the latest version number, such as `v1`.
- uses: actions/checkout@${latest-version}
- uses: yuyuyuyuyu-dev/assert-no-unexpected-changes@${latest-version}
  with:
    arrange: | # Run in `sh`.
      some-setup-commands
      for-example-install-the-dependencies
      build-the-thing
      or-anything-else
    act: | # Run in `sh`.
      some-commands-to-verify
      for-example-run-tests
      run-execution-directory
      or-anything-else
    allowlist: |
      /path/that/may/change
      /for/example/cache/*
    workdir: /path/to/workdir # Optional. Defaults to `/workdir`.
    image: some-image:a-tag # Optional. Defaults to Ubuntu.
```

## License

[MIT](LICENSE)
