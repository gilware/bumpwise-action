# Bumpwise dependency upgrade check

A GitHub Action for Dependabot and Renovate pull requests in Java and Kotlin projects. It finds every dependency
version the pull request changes and lists the places in your code that each new version breaks, with file and line.

```
com.google.guava:guava 18.0 -> 33.8.0-jre: breaks 1 place in this project (2 breaking changes used).

| Where                               | Uses                                                    | What changed  |
| src/main/java/demo/Person.java:11   | uses com.google.common.base.Objects.ToStringHelper      | class removed |
| src/main/java/demo/Person.java:11   | calls com.google.common.base.Objects#toStringHelper(Object) | removed   |

23 other breaking changes do not affect this project.
```

The result goes to the job summary and, if you want, to a pull request comment that is updated on each push.

## Usage

```yaml
on: pull_request

jobs:
  dependencies:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write   # only for comment: true
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gilware/bumpwise-action@v1
        with:
          build: mvn -B -q compile
          comment: true
```

For Gradle, use `build: ./gradlew compileJava compileKotlin` (or the compile tasks your project has).

### Why the action builds the project itself

Bumpwise compares the classes compiled against the versions you use now with the new versions. On an upgrade pull
request the build files already name the new versions, and when an upgrade breaks your code, compiling with them
fails before anything can be checked. With `build`, the action puts the base branch's build files in place, runs
the command, puts the pull request's files back, and then checks. If you leave `build` empty, build the project
that way in an earlier step.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `build` | (empty) | Command that compiles the project, run with the base branch's build files. |
| `base` | the pull request's base branch | Git revision to compare the build files with. |
| `project` | `.` | Project folder. |
| `fail-on-break` | `true` | Fail the job when an upgrade breaks places in the project. |
| `comment` | `false` | Post or update a pull request comment. Needs `pull-requests: write`. |
| `version` / `sha256` | 1.1.3 and its SHA-256 | Bumpwise command line version. Set both to pin another one. |

Output `exit-code`: 0 safe for this project, 1 breaks places in it, 2 Bumpwise could not tell (the job does not fail
on 2).

## What it sees

Bumpwise reads the compiled classes: calls, field reads and writes, classes you create, extend or implement, methods
you override. Uses through reflection, and code that is not compiled, are not seen. Libraries come from Maven
Central and, for Google's groups (AndroidX, Compose, Firebase), Google Maven. The action downloads the Bumpwise
command line from gilware.com and checks its SHA-256 before running it.

The command line is free. More: https://gilware.com/bumpwise/cli/

Made by Gilware.
