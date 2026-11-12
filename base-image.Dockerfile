# Nothing builds this file. It holds the default image, which the action reads
# from the `FROM` line below whenever the caller passes no `image`. The default
# is kept here rather than as the default of the `image` input in action.yml,
# because Renovate, which updates the dependencies of this repository, reads
# image references out of Dockerfiles but not out of input defaults.
#
# Ubuntu because every GitHub hosted Linux runner is Ubuntu, so a command that
# breaks here breaks in the caller's other jobs too.
FROM ubuntu:26.04
