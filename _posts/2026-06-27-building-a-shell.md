---
layout: post
title: "Building a Shell"
date: 2026-06-27
---

Original source: [Original post](<https://healeycodes.com/building-a-shell>)

-   [Andrew Healey](/)
-   [Articles](/articles)
-   [Projects](/projects)
-   [Notes](/notes)
-   [GitHub](https://github.com/healeycodes)
-   [Twitter](https://twitter.com/healeycodes)
-   [RSS](/feed.xml)

# Building a Shell

Mar 2026

The shell sits in front of a lot of my work, but I mostly use it for the outcome: running unix commands and scripts, creating branches and making commits. Unlike when I'm writing code, I'm rarely thinking about how the shell itself works under the hood.

So, to dig a bit deeper into shells, I'm going to build a toy one until I run out of time. I have a fresh pot of filter coffee, and I'm awake three hours before everyone else.

A quick look ahead to everything I'm able to support by the end:

./andsh

andsh$ cd /

andsh$ pwd

/

andsh$ echo $HOME

/Users/andrew

andsh$ nosuchcommand

nosuchcommand: No such file or directory

andsh$ echo $?

127

andsh$ printf abc\\n | tr a-z A-Z | rev

CBA

andsh$ ec<Tab> hello

andsh$ echo hello

hello

andsh$ <Up>

andsh$ echo hello

hello

andsh$ ^D

If you prefer reading C over prose, head straight to [healeycodes/andsh](https://github.com/healeycodes/andsh).

## REPL

A shell is an interactive program before it's a language implementation, and the user experience starts at the prompt. This first step is about building the interactive skeleton: print a prompt, read a line, keep a little state, and leave a clean place to plug execution logic into.

// repl.h

typedef struct {

    int last\_status;

    int running;

    int interactive;

} Shell;

We also need the classic read-eval-print loop:

// repl.c

int shell\_run(Shell \*shell) {

    char \*line \= NULL;

    size\_t capacity \= 0;

    if (install\_signal\_handlers() != 0) {

        return 1;

    }

    while (shell\->running) {

        int rc \= read\_line(&line, &capacity, shell);

        if (rc \== 0) {

            break;

        }

        if (rc < 0) {

            free(line);

            return 1;

        }

        eval\_line(shell, line);

    }

    free(line);

    return shell\->last\_status;

}

`read_line` returns three cases: got a line, hit EOF, or hit a real error.

`eval_line` starts tiny: blank lines do nothing, `exit` stops the shell in-process, and everything else gets treated as an external command.

// inside eval\_line

if (strcmp(argv\[0\], "exit") \== 0) {

    shell\->running \= 0;

    free\_argv(argv);

    return shell\->last\_status;

}

status \= execute\_external(shell, argv);

At the moment, we can run `ls` but we can't run `ls -l` yet. It's interpreted as a single command `"ls -l"`.

## From a Line to argv

Before we add env var expansion and pipes, let's start by splitting a line on spaces and tabs so we can run simple foreground commands like `echo hello world` or `ls -l`.

It will be intentionally incomplete. It still won't handle quotes or redirections, but it will peel off `|` as syntax so we can grow into supporting pipelines later. It's still useful because Unix process APIs want `argv` (argument vector, values passed down to a program when it starts).

First, we need a way to split a line:

// repl.c

static char \*\*tokenize\_line(const char \*line, int \*count\_out) {

    while (\*p != '\\0') {

        while (isspace((unsigned char) \*p)) {

            p++;

        }

        if (\*p \== '|') {

            push\_word(&words, &count, &capacity, dup\_range(p, 1));

            p++;

            continue;

        }

        // .. copy the next word up to whitespace or |

    }

    \*count\_out \= (int) count;

    return words;

}

Which we can call inside our fledgling `eval_line` function to get a stream of shell words before we group them into commands.

// inside eval\_line

if (line\_is\_blank(line)) {

    return 0;

}

words \= tokenize\_line(line, &word\_count);

if (word\_count \== 0) {

    free\_words(words);

    return 0;

}

## Running Commands

A shell can't replace itself with a command that it's launching (otherwise the shell would cease to exist after running that command) so it must create a child process to run the command, and wait for it to finish.

The parent shell stays alive and the child process becomes the command.

`execvp` is a convenient call from the `exec` family here. It searches `PATH` and replaces the current process with a new program, using the current process environment.

`waitpid` gives control back to the shell after the command exits.

// repl.c

pid \= fork();

if (pid \== 0) {

    execvp(argv\[0\], argv);

    perror(argv\[0\]);

    // 127: command not found, 126: found but not executable / cannot invoke

    \_exit(errno \== ENOENT ? 127 : 126);

}

// ..

while (waitpid(pid, &status, 0) < 0) {

    if (errno != EINTR) {

        perror("waitpid");

        shell\->last\_status \= 1;

        return shell\->last\_status;

    }

}

The child uses `_exit` to avoid running parent-inherited libc cleanup in the forked child (can lead to duplicated output and other unintended side effects).

One shell-y detail I wanted to keep was the interrupted wait path. Retrying on `EINTR` keeps the shell from losing track of a child process when the terminal sends an interrupt.

Now we can do real shell things:

./andsh

andsh$ echo hello world

hello world

andsh$ pwd

/Users/andrew/Documents/experiments/andsh

andsh$ ls -l

total 160

\-rw-r--r--  1 andrew  staff    194 14 Mar 08:10 Makefile

drwxr-xr-x  7 andrew  staff    224 14 Mar 14:24 src

andsh$ ^D

For the process/system call stuff, C is great for writing toy shells. The downsides are things like splitting a line (managing dynamic memory), and later, adding more shell syntax (string lifetimes).

## cd, or How to Get around

One of the core shell rules is that some commands can't run in a child process. For example, if the shell forks and a child calls `chdir` then only the child changes directories; when the child exits, the parent shell is still in the old directory.

This is why `cd` has to be a builtin.

// inside try\_builtin

if (strcmp(command\->argv\[0\], "cd") \== 0) {

    return run\_builtin\_cd(shell, command);

}

Something I learned for this post is that `HOME` is the conventional default target when running a lone `cd`.

static int run\_builtin\_cd(Shell \*shell, Command \*command) {

    const char \*target \= command\->argc \== 1 ? getenv("HOME") : command\->argv\[1\];

    if (chdir(target) != 0) {

        perror("cd");

        shell\->last\_status \= 1;

        return shell\->last\_status;

    }

    shell\->last\_status \= 0;

    return 0;

}

Because `run_builtin_cd` runs inside the shell process, the next prompt sees the new directory.

## Env Var Expansion

Before running a command, the shell rewrites parts of the input line. There are a few syntax rules and ordering details here, but for my toy shell I'm just adding env var expansion.

`echo $HOME` shouldn't print `$HOME`, it should print `/Users/andrew`.

I'm just hacking this in. Only whole-word `$NAME` expansion. No quotes, no `${NAME}`, and no splitting rules.

static char \*expand\_word(const Shell \*shell, const char \*word) {

    const char \*value;

    if (strcmp(word, "$?") \== 0) {

        char status\[32\];

        snprintf(status, sizeof(status), "%d", shell\->last\_status);

        return strdup(status);

    }

    if (word\[0\] != '$' || word\[1\] \== '\\0') {

        return strdup(word);

    }

    // .. look up NAME in the environment

    value \= getenv(word + 1);

    if (value \== NULL) {

        // Unset variables expand to the empty string in this toy shell.

        return strdup("");

    }

    return strdup(value);

}

Expansion happens after tokenization but before execution. And `|` is syntax, not data, so we don't try to expand it:

for (i \= 0; words\[i\] != NULL; i++) {

    char \*expanded;

    if (strcmp(words\[i\], "|") \== 0) {

        continue;

    }

    expanded \= expand\_word(shell, words\[i\]);

    free(words\[i\]);

    words\[i\] \= expanded;

}

We expand token-by-token, keeping it simple; and skipping writing a parser.

The special case for `$?` is also nice to leave in the code because it's one of those tiny shell details that makes the prompt feel less fake.

## Piping

A pipe (`|`) is a kernel buffer with one process writing bytes in and another reading bytes out.

`cmd1 | cmd2` connects the stdout of the left command to the stdin of the right command. For `N` commands, you need `N - 1` pipes.

The heavy lifting here will be done by `pipe()`, which creates a one-way channel for interprocess communication. `pipe()` fills the array `pipefd` with two file descriptors. `pipefd[0]` is the read end, and `pipefd[1]` is the write end. Data written to the write end is buffered by the kernel until it is read from the read end.

The core pipe loop runs once per command in the pipeline. Each iteration may create one new pipe for the next command. `prev_read` is the read end carried forward from the previous iteration.

for (i \= 0; i < pipeline\->count; i++) {

    int pipefd\[2\] \= {\-1, \-1};

    if (i + 1 < pipeline\->count) {

        pipe(pipefd);

    }

    pid \= fork();

    if (pid \== 0) {

        // .. hook this command up to prev\_read / pipefd

        execvp(pipeline\->commands\[i\].argv\[0\], pipeline\->commands\[i\].argv);

    }

    // .. parent closes what it doesn't need, then carries read end forward

}

E.g. for `printf abc | tr a-z A-Z | rev`:

-   Left command produces bytes
-   Middle command reads, transforms, writes
-   Right command reads the final stream

`dup2` lets normal programs work in a pipeline without knowing about the shell. Programs read from stdin and write to stdout. The shell creates a pipe and uses `dup2` to connect these streams.

Below, `dup2(prev_read, STDIN_FILENO);` makes the process read from the previous pipe instead of stdin, and `dup2(pipefd[1], STDOUT_FILENO);` makes its output go into the next pipe instead of the shell prompt. Because the program still reads from stdin and writes to stdout as usual, it works in the pipeline without any special logic.

if (pid \== 0) {

    if (prev\_read != \-1) {

        dup2(prev\_read, STDIN\_FILENO);

    }

    if (pipefd\[1\] != \-1) {

        dup2(pipefd\[1\], STDOUT\_FILENO);

    }

    if (prev\_read != \-1) {

        close(prev\_read);

    }

    if (pipefd\[0\] != \-1) {

        close(pipefd\[0\]);

        close(pipefd\[1\]);

    }

}

And now, this shell's demo is looking a little more complete:

./andsh

andsh$ cd /

andsh$ pwd

/

andsh$ echo $HOME

/Users/andrew

andsh$ nosuchcommand

nosuchcommand: No such file or directory

andsh$ echo $?

127

andsh$ printf abc | tr a-z A-Z | rev

CBA

andsh$ ^D

## Recap

To recap a bit, I'll step through what happens when `ls $HOME | grep foo` is entered.

It's tokenized into `["ls", "$HOME", "|", "grep", "foo"]`.

Then expanded into `["ls", "/Users/andrew", "|", "grep", "foo"]`.

The flat token list is separated into structured pipeline commands:

-   `["ls", "/Users/andrew"]`
-   `["grep", "foo"]`

The shell creates a pipe to connect the output of `ls` to the input of `grep`.

The child commands start via `fork`, and `execvp` swaps them into the target programs.

By the wonderful design of Unix: if `grep` reads faster than `ls` writes, it blocks waiting for more data; if `ls` writes faster than `grep` reads, the pipe buffer fills and `ls` temporarily blocks. This synchronization happens automatically through the pipe, while the shell simply waits for both child processes to finish.

The output of `grep` isn't connected to a pipe as it's the last command, and any results are displayed to the user.

## Polishing the REPL: History and Tab Completion

Even though our little REPL runs commands, expands env vars, and builds pipes, the interaction still feels rough. Left and right arrows do not magically work just because you're in a terminal. The terminal just sends escape sequences like `^[[D`.

At the moment, trying to move left and fix a typo ends up looking like this:

./andsh

andsh$ echo ac^\[\[Db

ac^\[\[Db

Up to now, `getline` has been reading bytes just fine. Now we need something to sit in the middle and give us line editing, history, and completion. One answer is the `readline` library.

The outcome of calling it, is a line to evaluate, and history that can be walked later:

// inside read\_line

if (shell\->interactive) {

    free(\*line);

    \*line \= readline("andsh$ "); // <--

    if (\*line \== NULL) {

        fputc('\\n', stdout);

        return 0;

    }

    if ((\*line)\[0\] != '\\0') {

        add\_history(\*line);

    }

    return 1;

}

There's also a little setup for tab completion and history:

// inside shell\_init

if (shell\->interactive) {

    rl\_readline\_name \= "andsh";

    rl\_catch\_signals \= 0;

    // Plug in tab completion

    rl\_attempted\_completion\_function \= shell\_completion;

    // We don't need special paste handling

    rl\_variable\_bind("enable-bracketed-paste", "off");

    // History support

    using\_history();

}

The API for tab completion involves providing a generator that can cycle through the different matching options.

static char \*completion\_generator(const char \*text, int state) {

    if (state \== 0) {

        // Initial setup \`text\` is e.g. \`ech\`

        if (build\_completion\_matches(text) != 0) {

            free\_completion\_matches();

            return NULL;

        }

    }

    if (g\_completion\_index \>= g\_completion\_count) {

        return NULL;

    }

    return strdup(g\_completion\_matches\[g\_completion\_index++\]);

}

`readline` calls the generator repeatedly until it returns `NULL`. When `state == 0`, we set up the generator by building all the completion matches. After that, the generator hands matches back one at a time (e.g. each time the user presses tab, or all at once for tab-tab-Y).

So, we need a function that takes `text` (partial text) and returns a list of matches. I've chosen to scan the current directory (`.`) for files, followed by all the `$PATH` directories; returning any files that start with the partial text.

static int build\_completion\_matches(const char \*text) {

    free\_completion\_matches();

    // Inside this function, we're calling \`readdir\`, \`starts\_with\`,

    // and \`add\_completion\_match\` for anything we consider a match.

    if (collect\_matches\_from\_dir(".", text, 0) != 0) {

        return \-1;

    }

    path \= getenv("PATH");

    // .. split PATH on ':' and scan each directory

}

Adding basic tab completion like this really makes me consider the performance implications of shells. I didn't know that some shells might make hundreds of system calls around each prompt to figure out things like completion options.

The final demo:

andsh$ unam<Tab>

andsh$ uname

andsh$ Makef<Tab>

andsh$ Makefile

andsh$ echo hello

hello

andsh$ <Up>

andsh$ echo hello

## What's Missing

A lot is missing. `andsh` is usable enough. It could handle maybe 50% of my shell use cases: launching programs, some git commands, and basic pipes into `grep`.

But it's very small and incomplete. No quoting is a big one. `echo "hello world"` is where some people would start when implementing a shell but ... I've written a [lot](https://healeycodes.com/compiling-lisp-to-bytecode-and-running-it) [of](https://healeycodes.com/a-custom-webassembly-compiler) [parsers](https://healeycodes.com/porting-boolrule-to-rust) on this blog already. There's no redirection, so `<`, `>`, and `>>` do not work. Builtins are also minimal, and I only really handle them as standalone commands.

Redirection would add more file descriptor plumbing to execution, and quoting would force the tokenizer to become a real shell lexer.

I think my biggest learnings were the low-level process APIs shells are using under the hood. I don't often work directly with calls like `execvp` and `dup2`.

Read the code at [healeycodes/andsh](https://github.com/healeycodes/andsh), and send me your terminal and shell projects pls.

* * *

Subscribe to be notified (somewhat irregularly) of my new posts.

[← A Fair, Cancelable Semaphore in Go](/a-fair-cancelable-semaphore-in-go)

[Building a Runtime with QuickJS →](/building-a-runtime-with-quickjs)

{"props":{"pageProps":{"id":"building-a-shell","source":"\\nThe shell sits in front of a lot of my work, but I mostly use it for the outcome: running unix commands and scripts, creating branches and making commits. Unlike when I'm writing code, I'm rarely thinking about how the shell itself works under the hood.\\n\\nSo, to dig a bit deeper into shells, I'm going to build a toy one until I run out of time. I have a fresh pot of filter coffee, and I'm awake three hours before everyone else.\\n\\nA quick look ahead to everything I'm able to support by the end:\\n\\n\`\`\`text\\n./andsh\\nandsh$ cd /\\nandsh$ pwd\\n/\\nandsh$ echo $HOME\\n/Users/andrew\\nandsh$ nosuchcommand\\nnosuchcommand: No such file or directory\\nandsh$ echo $?\\n127\\nandsh$ printf abc\\\\n | tr a-z A-Z | rev\\nCBA\\nandsh$ ec\\u003cTab\\u003e hello\\nandsh$ echo hello\\nhello\\nandsh$ \\u003cUp\\u003e\\nandsh$ echo hello\\nhello\\nandsh$ ^D\\n\`\`\`\\n\\nIf you prefer reading C over prose, head straight to \[healeycodes/andsh\](https://github.com/healeycodes/andsh).\\n\\n## REPL\\n\\nA shell is an interactive program before it's a language implementation, and the user experience starts at the prompt. This first step is about building the interactive skeleton: print a prompt, read a line, keep a little state, and leave a clean place to plug execution logic into.\\n\\n\`\`\`c\\n// repl.h\\n\\ntypedef struct {\\n int last\_status;\\n int running;\\n int interactive;\\n} Shell;\\n\`\`\`\\n\\nWe also need the classic read-eval-print loop:\\n\\n\`\`\`c\\n// repl.c\\n\\nint shell\_run(Shell \*shell) {\\n char \*line = NULL;\\n size\_t capacity = 0;\\n\\n if (install\_signal\_handlers() != 0) {\\n return 1;\\n }\\n\\n while (shell-\\u003erunning) {\\n int rc = read\_line(\\u0026line, \\u0026capacity, shell);\\n\\n if (rc == 0) {\\n break;\\n }\\n\\n if (rc \\u003c 0) {\\n free(line);\\n return 1;\\n }\\n\\n eval\_line(shell, line);\\n }\\n\\n free(line);\\n return shell-\\u003elast\_status;\\n}\\n\`\`\`\\n\\n\`read\_line\` returns three cases: got a line, hit EOF, or hit a real error.\\n\\n\`eval\_line\` starts tiny: blank lines do nothing, \`exit\` stops the shell in-process, and everything else gets treated as an external command.\\n\\n\`\`\`c\\n// inside eval\_line\\n\\nif (strcmp(argv\[0\], \\"exit\\") == 0) {\\n shell-\\u003erunning = 0;\\n free\_argv(argv);\\n return shell-\\u003elast\_status;\\n}\\n\\nstatus = execute\_external(shell, argv);\\n\`\`\`\\n\\nAt the moment, we can run \`ls\` but we can't run \`ls -l\` yet. It's interpreted as a single command \`\\"ls -l\\"\`.\\n\\n## From a Line to argv\\n\\nBefore we add env var expansion and pipes, let's start by splitting a line on spaces and tabs so we can run simple foreground commands like \`echo hello world\` or \`ls -l\`.\\n\\nIt will be intentionally incomplete. It still won't handle quotes or redirections, but it will peel off \`|\` as syntax so we can grow into supporting pipelines later. It's still useful because Unix process APIs want \`argv\` (argument vector, values passed down to a program when it starts).\\n\\nFirst, we need a way to split a line:\\n\\n\`\`\`c\\n// repl.c\\n\\nstatic char \*\*tokenize\_line(const char \*line, int \*count\_out) {\\n while (\*p != '\\\\0') {\\n while (isspace((unsigned char) \*p)) {\\n p++;\\n }\\n\\n if (\*p == '|') {\\n push\_word(\\u0026words, \\u0026count, \\u0026capacity, dup\_range(p, 1));\\n p++;\\n continue;\\n }\\n\\n // .. copy the next word up to whitespace or |\\n }\\n\\n \*count\_out = (int) count;\\n return words;\\n}\\n\`\`\`\\n\\nWhich we can call inside our fledgling \`eval\_line\` function to get a stream of shell words before we group them into commands.\\n\\n\`\`\`c\\n// inside eval\_line\\n\\nif (line\_is\_blank(line)) {\\n return 0;\\n}\\n\\nwords = tokenize\_line(line, \\u0026word\_count);\\nif (word\_count == 0) {\\n free\_words(words);\\n return 0;\\n}\\n\`\`\`\\n\\n## Running Commands\\n\\nA shell can't replace itself with a command that it's launching (otherwise the shell would cease to exist after running that command) so it must create a child process to run the command, and wait for it to finish.\\n\\nThe parent shell stays alive and the child process becomes the command.\\n\\n\`execvp\` is a convenient call from the \`exec\` family here. It searches \`PATH\` and replaces the current process with a new program, using the current process environment.\\n\\n\`waitpid\` gives control back to the shell after the command exits.\\n\\n\`\`\`c\\n// repl.c\\n\\npid = fork();\\nif (pid == 0) {\\n execvp(argv\[0\], argv);\\n perror(argv\[0\]);\\n\\n // 127: command not found, 126: found but not executable / cannot invoke\\n \_exit(errno == ENOENT ? 127 : 126);\\n}\\n\\n// ..\\n\\nwhile (waitpid(pid, \\u0026status, 0) \\u003c 0) {\\n if (errno != EINTR) {\\n perror(\\"waitpid\\");\\n shell-\\u003elast\_status = 1;\\n return shell-\\u003elast\_status;\\n }\\n}\\n\`\`\`\\n\\nThe child uses \`\_exit\` to avoid running parent-inherited libc cleanup in the forked child (can lead to duplicated output and other unintended side effects).\\n\\nOne shell-y detail I wanted to keep was the interrupted wait path. Retrying on \`EINTR\` keeps the shell from losing track of a child process when the terminal sends an interrupt.\\n\\nNow we can do real shell things:\\n\\n\`\`\`text\\n./andsh\\nandsh$ echo hello world\\nhello world\\nandsh$ pwd\\n/Users/andrew/Documents/experiments/andsh\\nandsh$ ls -l\\ntotal 160\\n-rw-r--r-- 1 andrew staff 194 14 Mar 08:10 Makefile\\ndrwxr-xr-x 7 andrew staff 224 14 Mar 14:24 src\\nandsh$ ^D\\n\`\`\`\\n\\nFor the process/system call stuff, C is great for writing toy shells. The downsides are things like splitting a line (managing dynamic memory), and later, adding more shell syntax (string lifetimes).\\n\\n## cd, or How to Get around\\n\\nOne of the core shell rules is that some commands can't run in a child process. For example, if the shell forks and a child calls \`chdir\` then only the child changes directories; when the child exits, the parent shell is still in the old directory.\\n\\nThis is why \`cd\` has to be a builtin.\\n\\n\`\`\`c\\n// inside try\_builtin\\n\\nif (strcmp(command-\\u003eargv\[0\], \\"cd\\") == 0) {\\n return run\_builtin\_cd(shell, command);\\n}\\n\`\`\`\\n\\nSomething I learned for this post is that \`HOME\` is the conventional default target when running a lone \`cd\`.\\n\\n\`\`\`c\\nstatic int run\_builtin\_cd(Shell \*shell, Command \*command) {\\n const char \*target = command-\\u003eargc == 1 ? getenv(\\"HOME\\") : command-\\u003eargv\[1\];\\n\\n if (chdir(target) != 0) {\\n perror(\\"cd\\");\\n shell-\\u003elast\_status = 1;\\n return shell-\\u003elast\_status;\\n }\\n\\n shell-\\u003elast\_status = 0;\\n return 0;\\n}\\n\`\`\`\\n\\nBecause \`run\_builtin\_cd\` runs inside the shell process, the next prompt sees the new directory.\\n\\n## Env Var Expansion\\n\\nBefore running a command, the shell rewrites parts of the input line. There are a few syntax rules and ordering details here, but for my toy shell I'm just adding env var expansion.\\n\\n\`echo $HOME\` shouldn't print \`$HOME\`, it should print \`/Users/andrew\`.\\n\\nI'm just hacking this in. Only whole-word \`$NAME\` expansion. No quotes, no \`${NAME}\`, and no splitting rules.\\n\\n\`\`\`c\\nstatic char \*expand\_word(const Shell \*shell, const char \*word) {\\n const char \*value;\\n\\n if (strcmp(word, \\"$?\\") == 0) {\\n char status\[32\];\\n snprintf(status, sizeof(status), \\"%d\\", shell-\\u003elast\_status);\\n return strdup(status);\\n }\\n\\n if (word\[0\] != '$' || word\[1\] == '\\\\0') {\\n return strdup(word);\\n }\\n\\n // .. look up NAME in the environment\\n value = getenv(word + 1);\\n if (value == NULL) {\\n\\n // Unset variables expand to the empty string in this toy shell.\\n return strdup(\\"\\");\\n }\\n\\n return strdup(value);\\n}\\n\`\`\`\\n\\nExpansion happens after tokenization but before execution. And \`|\` is syntax, not data, so we don't try to expand it:\\n\\n\`\`\`c\\nfor (i = 0; words\[i\] != NULL; i++) {\\n char \*expanded;\\n\\n if (strcmp(words\[i\], \\"|\\") == 0) {\\n continue;\\n }\\n\\n expanded = expand\_word(shell, words\[i\]);\\n free(words\[i\]);\\n words\[i\] = expanded;\\n}\\n\`\`\`\\n\\nWe expand token-by-token, keeping it simple; and skipping writing a parser.\\n\\nThe special case for \`$?\` is also nice to leave in the code because it's one of those tiny shell details that makes the prompt feel less fake.\\n\\n## Piping\\n\\nA pipe (\`|\`) is a kernel buffer with one process writing bytes in and another reading bytes out.\\n\\n\`cmd1 | cmd2\` connects the stdout of the left command to the stdin of the right command. For \`N\` commands, you need \`N - 1\` pipes.\\n\\nThe heavy lifting here will be done by \`pipe()\`, which creates a one-way channel for interprocess communication. \`pipe()\` fills the array \`pipefd\` with two file descriptors. \`pipefd\[0\]\` is the read end, and \`pipefd\[1\]\` is the write end. Data written to the write end is buffered by the kernel until it is read from the read end.\\n\\nThe core pipe loop runs once per command in the pipeline. Each iteration may create one new pipe for the next command. \`prev\_read\` is the read end carried forward from the previous iteration.\\n\\n\`\`\`c\\nfor (i = 0; i \\u003c pipeline-\\u003ecount; i++) {\\n int pipefd\[2\] = {-1, -1};\\n\\n if (i + 1 \\u003c pipeline-\\u003ecount) {\\n pipe(pipefd);\\n }\\n\\n pid = fork();\\n if (pid == 0) {\\n\\n // .. hook this command up to prev\_read / pipefd\\n execvp(pipeline-\\u003ecommands\[i\].argv\[0\], pipeline-\\u003ecommands\[i\].argv);\\n }\\n\\n // .. parent closes what it doesn't need, then carries read end forward\\n}\\n\`\`\`\\n\\nE.g. for \`printf abc | tr a-z A-Z | rev\`:\\n\\n- Left command produces bytes\\n- Middle command reads, transforms, writes\\n- Right command reads the final stream\\n\\n\`dup2\` lets normal programs work in a pipeline without knowing about the shell. Programs read from stdin and write to stdout. The shell creates a pipe and uses \`dup2\` to connect these streams.\\n\\nBelow, \`dup2(prev\_read, STDIN\_FILENO);\` makes the process read from the previous pipe instead of stdin, and \`dup2(pipefd\[1\], STDOUT\_FILENO);\` makes its output go into the next pipe instead of the shell prompt. Because the program still reads from stdin and writes to stdout as usual, it works in the pipeline without any special logic.\\n\\n\`\`\`c\\nif (pid == 0) {\\n if (prev\_read != -1) {\\n dup2(prev\_read, STDIN\_FILENO);\\n }\\n\\n if (pipefd\[1\] != -1) {\\n dup2(pipefd\[1\], STDOUT\_FILENO);\\n }\\n\\n if (prev\_read != -1) {\\n close(prev\_read);\\n }\\n\\n if (pipefd\[0\] != -1) {\\n close(pipefd\[0\]);\\n close(pipefd\[1\]);\\n }\\n}\\n\`\`\`\\n\\nAnd now, this shell's demo is looking a little more complete:\\n\\n\`\`\`text\\n./andsh\\nandsh$ cd /\\nandsh$ pwd\\n/\\nandsh$ echo $HOME\\n/Users/andrew\\nandsh$ nosuchcommand\\nnosuchcommand: No such file or directory\\nandsh$ echo $?\\n127\\nandsh$ printf abc | tr a-z A-Z | rev\\nCBA\\nandsh$ ^D\\n\`\`\`\\n\\n## Recap\\n\\nTo recap a bit, I'll step through what happens when \`ls $HOME | grep foo\` is entered.\\n\\nIt's tokenized into \`\[\\"ls\\", \\"$HOME\\", \\"|\\", \\"grep\\", \\"foo\\"\]\`.\\n\\nThen expanded into \`\[\\"ls\\", \\"/Users/andrew\\", \\"|\\", \\"grep\\", \\"foo\\"\]\`.\\n\\nThe flat token list is separated into structured pipeline commands:\\n- \`\[\\"ls\\", \\"/Users/andrew\\"\]\`\\n- \`\[\\"grep\\", \\"foo\\"\]\`\\n\\nThe shell creates a pipe to connect the output of \`ls\` to the input of \`grep\`.\\n\\nThe child commands start via \`fork\`, and \`execvp\` swaps them into the target programs.\\n\\nBy the wonderful design of Unix: if \`grep\` reads faster than \`ls\` writes, it blocks waiting for more data; if \`ls\` writes faster than \`grep\` reads, the pipe buffer fills and \`ls\` temporarily blocks. This synchronization happens automatically through the pipe, while the shell simply waits for both child processes to finish.\\n\\nThe output of \`grep\` isn't connected to a pipe as it's the last command, and any results are displayed to the user.\\n\\n## Polishing the REPL: History and Tab Completion\\n\\nEven though our little REPL runs commands, expands env vars, and builds pipes, the interaction still feels rough. Left and right arrows do not magically work just because you're in a terminal. The terminal just sends escape sequences like \`^\[\[D\`.\\n\\nAt the moment, trying to move left and fix a typo ends up looking like this:\\n\\n\`\`\`text\\n./andsh\\nandsh$ echo ac^\[\[Db\\nac^\[\[Db\\n\`\`\`\\n\\nUp to now, \`getline\` has been reading bytes just fine. Now we need something to sit in the middle and give us line editing, history, and completion. One answer is the \`readline\` library.\\n\\nThe outcome of calling it, is a line to evaluate, and history that can be walked later:\\n\\n\`\`\`c\\n// inside read\_line\\n\\nif (shell-\\u003einteractive) {\\n free(\*line);\\n \*line = readline(\\"andsh$ \\"); // \\u003c--\\n if (\*line == NULL) {\\n fputc('\\\\n', stdout);\\n return 0;\\n }\\n\\n if ((\*line)\[0\] != '\\\\0') {\\n add\_history(\*line);\\n }\\n\\n return 1;\\n}\\n\`\`\`\\n\\nThere's also a little setup for tab completion and history:\\n\\n\`\`\`c\\n// inside shell\_init\\n\\nif (shell-\\u003einteractive) {\\n rl\_readline\_name = \\"andsh\\";\\n\\n rl\_catch\_signals = 0;\\n\\n // Plug in tab completion\\n rl\_attempted\_completion\_function = shell\_completion;\\n\\n // We don't need special paste handling\\n rl\_variable\_bind(\\"enable-bracketed-paste\\", \\"off\\");\\n \\n // History support\\n using\_history();\\n}\\n\`\`\`\\n\\nThe API for tab completion involves providing a generator that can cycle through the different matching options.\\n\\n\`\`\`c\\nstatic char \*completion\_generator(const char \*text, int state) {\\n if (state == 0) {\\n\\n // Initial setup \`text\` is e.g. \`ech\`\\n if (build\_completion\_matches(text) != 0) {\\n free\_completion\_matches();\\n return NULL;\\n }\\n }\\n\\n if (g\_completion\_index \\u003e= g\_completion\_count) {\\n return NULL;\\n }\\n\\n return strdup(g\_completion\_matches\[g\_completion\_index++\]);\\n}\\n\`\`\`\\n\\n\`readline\` calls the generator repeatedly until it returns \`NULL\`. When \`state == 0\`, we set up the generator by building all the completion matches. After that, the generator hands matches back one at a time (e.g. each time the user presses tab, or all at once for tab-tab-Y).\\n\\nSo, we need a function that takes \`text\` (partial text) and returns a list of matches. I've chosen to scan the current directory (\`.\`) for files, followed by all the \`$PATH\` directories; returning any files that start with the partial text.\\n\\n\`\`\`c\\nstatic int build\_completion\_matches(const char \*text) {\\n free\_completion\_matches();\\n\\n // Inside this function, we're calling \`readdir\`, \`starts\_with\`,\\n // and \`add\_completion\_match\` for anything we consider a match.\\n if (collect\_matches\_from\_dir(\\".\\", text, 0) != 0) {\\n return -1;\\n }\\n\\n path = getenv(\\"PATH\\");\\n // .. split PATH on ':' and scan each directory\\n}\\n\`\`\`\\n\\nAdding basic tab completion like this really makes me consider the performance implications of shells. I didn't know that some shells might make hundreds of system calls around each prompt to figure out things like completion options.\\n\\nThe final demo:\\n\\n\`\`\`text\\nandsh$ unam\\u003cTab\\u003e\\nandsh$ uname\\n\\nandsh$ Makef\\u003cTab\\u003e\\nandsh$ Makefile\\n\\nandsh$ echo hello\\nhello\\nandsh$ \\u003cUp\\u003e\\nandsh$ echo hello\\n\`\`\`\\n\\n## What's Missing\\n\\nA lot is missing. \`andsh\` is usable enough. It could handle maybe 50% of my shell use cases: launching programs, some git commands, and basic pipes into \`grep\`.\\n\\nBut it's very small and incomplete. No quoting is a big one. \`echo \\"hello world\\"\` is where some people would start when implementing a shell but ... I've written a \[lot\](https://healeycodes.com/compiling-lisp-to-bytecode-and-running-it) \[of\](https://healeycodes.com/a-custom-webassembly-compiler) \[parsers\](https://healeycodes.com/porting-boolrule-to-rust) on this blog already. There's no redirection, so \`\\u003c\`, \`\\u003e\`, and \`\\u003e\\u003e\` do not work. Builtins are also minimal, and I only really handle them as standalone commands.\\n\\nRedirection would add more file descriptor plumbing to execution, and quoting would force the tokenizer to become a real shell lexer.\\n\\nI think my biggest learnings were the low-level process APIs shells are using under the hood. I don't often work directly with calls like \`execvp\` and \`dup2\`.\\n\\nRead the code at \[healeycodes/andsh\](https://github.com/healeycodes/andsh), and send me your terminal and shell projects pls.\\n","imageMetadata":{},"videoMetadata":{},"content":"\\nThe shell sits in front of a lot of my work, but I mostly use it for the outcome: running unix commands and scripts, creating branches and making commits. Unlike when I'm writing code, I'm rarely thinking about how the shell itself works under the hood.\\n\\nSo, to dig a bit deeper into shells, I'm going to build a toy one until I run out of time. I have a fresh pot of filter coffee, and I'm awake three hours before everyone else.\\n\\nA quick look ahead to everything I'm able to support by the end:\\n\\n\`\`\`text\\n./andsh\\nandsh$ cd /\\nandsh$ pwd\\n/\\nandsh$ echo $HOME\\n/Users/andrew\\nandsh$ nosuchcommand\\nnosuchcommand: No such file or directory\\nandsh$ echo $?\\n127\\nandsh$ printf abc\\\\n | tr a-z A-Z | rev\\nCBA\\nandsh$ ec\\u003cTab\\u003e hello\\nandsh$ echo hello\\nhello\\nandsh$ \\u003cUp\\u003e\\nandsh$ echo hello\\nhello\\nandsh$ ^D\\n\`\`\`\\n\\nIf you prefer reading C over prose, head straight to \[healeycodes/andsh\](https://github.com/healeycodes/andsh).\\n\\n## REPL\\n\\nA shell is an interactive program before it's a language implementation, and the user experience starts at the prompt. This first step is about building the interactive skeleton: print a prompt, read a line, keep a little state, and leave a clean place to plug execution logic into.\\n\\n\`\`\`c\\n// repl.h\\n\\ntypedef struct {\\n int last\_status;\\n int running;\\n int interactive;\\n} Shell;\\n\`\`\`\\n\\nWe also need the classic read-eval-print loop:\\n\\n\`\`\`c\\n// repl.c\\n\\nint shell\_run(Shell \*shell) {\\n char \*line = NULL;\\n size\_t capacity = 0;\\n\\n if (install\_signal\_handlers() != 0) {\\n return 1;\\n }\\n\\n while (shell-\\u003erunning) {\\n int rc = read\_line(\\u0026line, \\u0026capacity, shell);\\n\\n if (rc == 0) {\\n break;\\n }\\n\\n if (rc \\u003c 0) {\\n free(line);\\n return 1;\\n }\\n\\n eval\_line(shell, line);\\n }\\n\\n free(line);\\n return shell-\\u003elast\_status;\\n}\\n\`\`\`\\n\\n\`read\_line\` returns three cases: got a line, hit EOF, or hit a real error.\\n\\n\`eval\_line\` starts tiny: blank lines do nothing, \`exit\` stops the shell in-process, and everything else gets treated as an external command.\\n\\n\`\`\`c\\n// inside eval\_line\\n\\nif (strcmp(argv\[0\], \\"exit\\") == 0) {\\n shell-\\u003erunning = 0;\\n free\_argv(argv);\\n return shell-\\u003elast\_status;\\n}\\n\\nstatus = execute\_external(shell, argv);\\n\`\`\`\\n\\nAt the moment, we can run \`ls\` but we can't run \`ls -l\` yet. It's interpreted as a single command \`\\"ls -l\\"\`.\\n\\n## From a Line to argv\\n\\nBefore we add env var expansion and pipes, let's start by splitting a line on spaces and tabs so we can run simple foreground commands like \`echo hello world\` or \`ls -l\`.\\n\\nIt will be intentionally incomplete. It still won't handle quotes or redirections, but it will peel off \`|\` as syntax so we can grow into supporting pipelines later. It's still useful because Unix process APIs want \`argv\` (argument vector, values passed down to a program when it starts).\\n\\nFirst, we need a way to split a line:\\n\\n\`\`\`c\\n// repl.c\\n\\nstatic char \*\*tokenize\_line(const char \*line, int \*count\_out) {\\n while (\*p != '\\\\0') {\\n while (isspace((unsigned char) \*p)) {\\n p++;\\n }\\n\\n if (\*p == '|') {\\n push\_word(\\u0026words, \\u0026count, \\u0026capacity, dup\_range(p, 1));\\n p++;\\n continue;\\n }\\n\\n // .. copy the next word up to whitespace or |\\n }\\n\\n \*count\_out = (int) count;\\n return words;\\n}\\n\`\`\`\\n\\nWhich we can call inside our fledgling \`eval\_line\` function to get a stream of shell words before we group them into commands.\\n\\n\`\`\`c\\n// inside eval\_line\\n\\nif (line\_is\_blank(line)) {\\n return 0;\\n}\\n\\nwords = tokenize\_line(line, \\u0026word\_count);\\nif (word\_count == 0) {\\n free\_words(words);\\n return 0;\\n}\\n\`\`\`\\n\\n## Running Commands\\n\\nA shell can't replace itself with a command that it's launching (otherwise the shell would cease to exist after running that command) so it must create a child process to run the command, and wait for it to finish.\\n\\nThe parent shell stays alive and the child process becomes the command.\\n\\n\`execvp\` is a convenient call from the \`exec\` family here. It searches \`PATH\` and replaces the current process with a new program, using the current process environment.\\n\\n\`waitpid\` gives control back to the shell after the command exits.\\n\\n\`\`\`c\\n// repl.c\\n\\npid = fork();\\nif (pid == 0) {\\n execvp(argv\[0\], argv);\\n perror(argv\[0\]);\\n\\n // 127: command not found, 126: found but not executable / cannot invoke\\n \_exit(errno == ENOENT ? 127 : 126);\\n}\\n\\n// ..\\n\\nwhile (waitpid(pid, \\u0026status, 0) \\u003c 0) {\\n if (errno != EINTR) {\\n perror(\\"waitpid\\");\\n shell-\\u003elast\_status = 1;\\n return shell-\\u003elast\_status;\\n }\\n}\\n\`\`\`\\n\\nThe child uses \`\_exit\` to avoid running parent-inherited libc cleanup in the forked child (can lead to duplicated output and other unintended side effects).\\n\\nOne shell-y detail I wanted to keep was the interrupted wait path. Retrying on \`EINTR\` keeps the shell from losing track of a child process when the terminal sends an interrupt.\\n\\nNow we can do real shell things:\\n\\n\`\`\`text\\n./andsh\\nandsh$ echo hello world\\nhello world\\nandsh$ pwd\\n/Users/andrew/Documents/experiments/andsh\\nandsh$ ls -l\\ntotal 160\\n-rw-r--r-- 1 andrew staff 194 14 Mar 08:10 Makefile\\ndrwxr-xr-x 7 andrew staff 224 14 Mar 14:24 src\\nandsh$ ^D\\n\`\`\`\\n\\nFor the process/system call stuff, C is great for writing toy shells. The downsides are things like splitting a line (managing dynamic memory), and later, adding more shell syntax (string lifetimes).\\n\\n## cd, or How to Get around\\n\\nOne of the core shell rules is that some commands can't run in a child process. For example, if the shell forks and a child calls \`chdir\` then only the child changes directories; when the child exits, the parent shell is still in the old directory.\\n\\nThis is why \`cd\` has to be a builtin.\\n\\n\`\`\`c\\n// inside try\_builtin\\n\\nif (strcmp(command-\\u003eargv\[0\], \\"cd\\") == 0) {\\n return run\_builtin\_cd(shell, command);\\n}\\n\`\`\`\\n\\nSomething I learned for this post is that \`HOME\` is the conventional default target when running a lone \`cd\`.\\n\\n\`\`\`c\\nstatic int run\_builtin\_cd(Shell \*shell, Command \*command) {\\n const char \*target = command-\\u003eargc == 1 ? getenv(\\"HOME\\") : command-\\u003eargv\[1\];\\n\\n if (chdir(target) != 0) {\\n perror(\\"cd\\");\\n shell-\\u003elast\_status = 1;\\n return shell-\\u003elast\_status;\\n }\\n\\n shell-\\u003elast\_status = 0;\\n return 0;\\n}\\n\`\`\`\\n\\nBecause \`run\_builtin\_cd\` runs inside the shell process, the next prompt sees the new directory.\\n\\n## Env Var Expansion\\n\\nBefore running a command, the shell rewrites parts of the input line. There are a few syntax rules and ordering details here, but for my toy shell I'm just adding env var expansion.\\n\\n\`echo $HOME\` shouldn't print \`$HOME\`, it should print \`/Users/andrew\`.\\n\\nI'm just hacking this in. Only whole-word \`$NAME\` expansion. No quotes, no \`${NAME}\`, and no splitting rules.\\n\\n\`\`\`c\\nstatic char \*expand\_word(const Shell \*shell, const char \*word) {\\n const char \*value;\\n\\n if (strcmp(word, \\"$?\\") == 0) {\\n char status\[32\];\\n snprintf(status, sizeof(status), \\"%d\\", shell-\\u003elast\_status);\\n return strdup(status);\\n }\\n\\n if (word\[0\] != '$' || word\[1\] == '\\\\0') {\\n return strdup(word);\\n }\\n\\n // .. look up NAME in the environment\\n value = getenv(word + 1);\\n if (value == NULL) {\\n\\n // Unset variables expand to the empty string in this toy shell.\\n return strdup(\\"\\");\\n }\\n\\n return strdup(value);\\n}\\n\`\`\`\\n\\nExpansion happens after tokenization but before execution. And \`|\` is syntax, not data, so we don't try to expand it:\\n\\n\`\`\`c\\nfor (i = 0; words\[i\] != NULL; i++) {\\n char \*expanded;\\n\\n if (strcmp(words\[i\], \\"|\\") == 0) {\\n continue;\\n }\\n\\n expanded = expand\_word(shell, words\[i\]);\\n free(words\[i\]);\\n words\[i\] = expanded;\\n}\\n\`\`\`\\n\\nWe expand token-by-token, keeping it simple; and skipping writing a parser.\\n\\nThe special case for \`$?\` is also nice to leave in the code because it's one of those tiny shell details that makes the prompt feel less fake.\\n\\n## Piping\\n\\nA pipe (\`|\`) is a kernel buffer with one process writing bytes in and another reading bytes out.\\n\\n\`cmd1 | cmd2\` connects the stdout of the left command to the stdin of the right command. For \`N\` commands, you need \`N - 1\` pipes.\\n\\nThe heavy lifting here will be done by \`pipe()\`, which creates a one-way channel for interprocess communication. \`pipe()\` fills the array \`pipefd\` with two file descriptors. \`pipefd\[0\]\` is the read end, and \`pipefd\[1\]\` is the write end. Data written to the write end is buffered by the kernel until it is read from the read end.\\n\\nThe core pipe loop runs once per command in the pipeline. Each iteration may create one new pipe for the next command. \`prev\_read\` is the read end carried forward from the previous iteration.\\n\\n\`\`\`c\\nfor (i = 0; i \\u003c pipeline-\\u003ecount; i++) {\\n int pipefd\[2\] = {-1, -1};\\n\\n if (i + 1 \\u003c pipeline-\\u003ecount) {\\n pipe(pipefd);\\n }\\n\\n pid = fork();\\n if (pid == 0) {\\n\\n // .. hook this command up to prev\_read / pipefd\\n execvp(pipeline-\\u003ecommands\[i\].argv\[0\], pipeline-\\u003ecommands\[i\].argv);\\n }\\n\\n // .. parent closes what it doesn't need, then carries read end forward\\n}\\n\`\`\`\\n\\nE.g. for \`printf abc | tr a-z A-Z | rev\`:\\n\\n- Left command produces bytes\\n- Middle command reads, transforms, writes\\n- Right command reads the final stream\\n\\n\`dup2\` lets normal programs work in a pipeline without knowing about the shell. Programs read from stdin and write to stdout. The shell creates a pipe and uses \`dup2\` to connect these streams.\\n\\nBelow, \`dup2(prev\_read, STDIN\_FILENO);\` makes the process read from the previous pipe instead of stdin, and \`dup2(pipefd\[1\], STDOUT\_FILENO);\` makes its output go into the next pipe instead of the shell prompt. Because the program still reads from stdin and writes to stdout as usual, it works in the pipeline without any special logic.\\n\\n\`\`\`c\\nif (pid == 0) {\\n if (prev\_read != -1) {\\n dup2(prev\_read, STDIN\_FILENO);\\n }\\n\\n if (pipefd\[1\] != -1) {\\n dup2(pipefd\[1\], STDOUT\_FILENO);\\n }\\n\\n if (prev\_read != -1) {\\n close(prev\_read);\\n }\\n\\n if (pipefd\[0\] != -1) {\\n close(pipefd\[0\]);\\n close(pipefd\[1\]);\\n }\\n}\\n\`\`\`\\n\\nAnd now, this shell's demo is looking a little more complete:\\n\\n\`\`\`text\\n./andsh\\nandsh$ cd /\\nandsh$ pwd\\n/\\nandsh$ echo $HOME\\n/Users/andrew\\nandsh$ nosuchcommand\\nnosuchcommand: No such file or directory\\nandsh$ echo $?\\n127\\nandsh$ printf abc | tr a-z A-Z | rev\\nCBA\\nandsh$ ^D\\n\`\`\`\\n\\n## Recap\\n\\nTo recap a bit, I'll step through what happens when \`ls $HOME | grep foo\` is entered.\\n\\nIt's tokenized into \`\[\\"ls\\", \\"$HOME\\", \\"|\\", \\"grep\\", \\"foo\\"\]\`.\\n\\nThen expanded into \`\[\\"ls\\", \\"/Users/andrew\\", \\"|\\", \\"grep\\", \\"foo\\"\]\`.\\n\\nThe flat token list is separated into structured pipeline commands:\\n- \`\[\\"ls\\", \\"/Users/andrew\\"\]\`\\n- \`\[\\"grep\\", \\"foo\\"\]\`\\n\\nThe shell creates a pipe to connect the output of \`ls\` to the input of \`grep\`.\\n\\nThe child commands start via \`fork\`, and \`execvp\` swaps them into the target programs.\\n\\nBy the wonderful design of Unix: if \`grep\` reads faster than \`ls\` writes, it blocks waiting for more data; if \`ls\` writes faster than \`grep\` reads, the pipe buffer fills and \`ls\` temporarily blocks. This synchronization happens automatically through the pipe, while the shell simply waits for both child processes to finish.\\n\\nThe output of \`grep\` isn't connected to a pipe as it's the last command, and any results are displayed to the user.\\n\\n## Polishing the REPL: History and Tab Completion\\n\\nEven though our little REPL runs commands, expands env vars, and builds pipes, the interaction still feels rough. Left and right arrows do not magically work just because you're in a terminal. The terminal just sends escape sequences like \`^\[\[D\`.\\n\\nAt the moment, trying to move left and fix a typo ends up looking like this:\\n\\n\`\`\`text\\n./andsh\\nandsh$ echo ac^\[\[Db\\nac^\[\[Db\\n\`\`\`\\n\\nUp to now, \`getline\` has been reading bytes just fine. Now we need something to sit in the middle and give us line editing, history, and completion. One answer is the \`readline\` library.\\n\\nThe outcome of calling it, is a line to evaluate, and history that can be walked later:\\n\\n\`\`\`c\\n// inside read\_line\\n\\nif (shell-\\u003einteractive) {\\n free(\*line);\\n \*line = readline(\\"andsh$ \\"); // \\u003c--\\n if (\*line == NULL) {\\n fputc('\\\\n', stdout);\\n return 0;\\n }\\n\\n if ((\*line)\[0\] != '\\\\0') {\\n add\_history(\*line);\\n }\\n\\n return 1;\\n}\\n\`\`\`\\n\\nThere's also a little setup for tab completion and history:\\n\\n\`\`\`c\\n// inside shell\_init\\n\\nif (shell-\\u003einteractive) {\\n rl\_readline\_name = \\"andsh\\";\\n\\n rl\_catch\_signals = 0;\\n\\n // Plug in tab completion\\n rl\_attempted\_completion\_function = shell\_completion;\\n\\n // We don't need special paste handling\\n rl\_variable\_bind(\\"enable-bracketed-paste\\", \\"off\\");\\n \\n // History support\\n using\_history();\\n}\\n\`\`\`\\n\\nThe API for tab completion involves providing a generator that can cycle through the different matching options.\\n\\n\`\`\`c\\nstatic char \*completion\_generator(const char \*text, int state) {\\n if (state == 0) {\\n\\n // Initial setup \`text\` is e.g. \`ech\`\\n if (build\_completion\_matches(text) != 0) {\\n free\_completion\_matches();\\n return NULL;\\n }\\n }\\n\\n if (g\_completion\_index \\u003e= g\_completion\_count) {\\n return NULL;\\n }\\n\\n return strdup(g\_completion\_matches\[g\_completion\_index++\]);\\n}\\n\`\`\`\\n\\n\`readline\` calls the generator repeatedly until it returns \`NULL\`. When \`state == 0\`, we set up the generator by building all the completion matches. After that, the generator hands matches back one at a time (e.g. each time the user presses tab, or all at once for tab-tab-Y).\\n\\nSo, we need a function that takes \`text\` (partial text) and returns a list of matches. I've chosen to scan the current directory (\`.\`) for files, followed by all the \`$PATH\` directories; returning any files that start with the partial text.\\n\\n\`\`\`c\\nstatic int build\_completion\_matches(const char \*text) {\\n free\_completion\_matches();\\n\\n // Inside this function, we're calling \`readdir\`, \`starts\_with\`,\\n // and \`add\_completion\_match\` for anything we consider a match.\\n if (collect\_matches\_from\_dir(\\".\\", text, 0) != 0) {\\n return -1;\\n }\\n\\n path = getenv(\\"PATH\\");\\n // .. split PATH on ':' and scan each directory\\n}\\n\`\`\`\\n\\nAdding basic tab completion like this really makes me consider the performance implications of shells. I didn't know that some shells might make hundreds of system calls around each prompt to figure out things like completion options.\\n\\nThe final demo:\\n\\n\`\`\`text\\nandsh$ unam\\u003cTab\\u003e\\nandsh$ uname\\n\\nandsh$ Makef\\u003cTab\\u003e\\nandsh$ Makefile\\n\\nandsh$ echo hello\\nhello\\nandsh$ \\u003cUp\\u003e\\nandsh$ echo hello\\n\`\`\`\\n\\n## What's Missing\\n\\nA lot is missing. \`andsh\` is usable enough. It could handle maybe 50% of my shell use cases: launching programs, some git commands, and basic pipes into \`grep\`.\\n\\nBut it's very small and incomplete. No quoting is a big one. \`echo \\"hello world\\"\` is where some people would start when implementing a shell but ... I've written a \[lot\](https://healeycodes.com/compiling-lisp-to-bytecode-and-running-it) \[of\](https://healeycodes.com/a-custom-webassembly-compiler) \[parsers\](https://healeycodes.com/porting-boolrule-to-rust) on this blog already. There's no redirection, so \`\\u003c\`, \`\\u003e\`, and \`\\u003e\\u003e\` do not work. Builtins are also minimal, and I only really handle them as standalone commands.\\n\\nRedirection would add more file descriptor plumbing to execution, and quoting would force the tokenizer to become a real shell lexer.\\n\\nI think my biggest learnings were the low-level process APIs shells are using under the hood. I don't often work directly with calls like \`execvp\` and \`dup2\`.\\n\\nRead the code at \[healeycodes/andsh\](https://github.com/healeycodes/andsh), and send me your terminal and shell projects pls.\\n","title":"Building a Shell","description":"I built a tiny shell in C to learn what fork, execvp, and dup2 are doing under the hood.","date":"2026-03-16","tags":\["c"\],"outdated":false,"prevPost":{"id":"a-fair-cancelable-semaphore-in-go","content":"\\nThey say that you don't fully understand something unless you can build it from scratch. To wit, my challenge to the more technical readers of this blog is: can you build a semaphore from scratch in your favorite programming language? Bonus points for also handling context cancellation.\\n\\nI attempted this in Go and it was about 5x harder than I thought it would be. Largely due to concurrency/locking bugs – I assume you'll have an easier time in, say, JavaScript.\\n\\nA brief reminder: semaphores are tools used in programming to limit how many tasks can run at the same time by controlling access to shared resources.\\n\\nHere's a quick example of their use-case. Your operating system has limits on the amount of file descriptors that can be open but you didn't know this when you wrote the following program:\\n\\n\`\`\`go\\ng, ctx := errgroup.WithContext(context.Background())\\n\\nfor \_, path := range files {\\n g.Go(func(p string) error {\\n f, err := os.Open(p)\\n if err != nil {\\n return err\\n }\\n defer f.Close()\\n\\n return processFile(f)\\n }(path))\\n}\\n\\nif err := g.Wait(); err != nil {\\n return err\\n}\\n\`\`\`\\n\\nWhen there's a large amount of files, you hit an error like:\\n\\n\`\`\`text\\npanic: open /my/file: too many open files!\\n\`\`\`\\n\\n## Channels\\n\\nIn Go, channels are a built-in concurrency primitive for communicating between goroutines. Which is exactly what we need to do here: the goroutine that's finished using the resource needs to tell one of the goroutines that's waiting that it can start using it.\\n\\n\`\`\`go\\ng, ctx := errgroup.WithContext(context.Background())\\n\\n// Initialize buffered channel with 10 empty structs\\nsema := make(chan struct{}, 10) \\n\\nfor \_, path := range files {\\n g.Go(func(p string) error {\\n\\n // Acquire a semaphore slot (blocks if the buffer is full)\\n sema \\u003c- struct{}{}\\n defer func() {\\n \\u003c-sema // Release the semaphore slot\\n }()\\n\\n f, err := os.Open(p)\\n if err != nil {\\n return err\\n }\\n defer f.Close()\\n\\n return processFile(f)\\n }(path))\\n}\\n\`\`\`\\n\\nThis works great as a simple limiter but it's missing two features that I often need in the semaphores I use:\\n\\n- First In First Out (FIFO) ordering. Requests are served in arrival order, which makes behavior easier to reason about and debug.\\n- Context cancellation. Waiting or in-progress operations can be aborted when they're no longer needed, preventing wasted work and resource leaks.\\n\\nWhy is the above snippet \_not\_ FIFO? Multiple goroutines sending to the channel compete with each other. The scheduler decides which send proceeds first, so ordering isn't guaranteed. There's no explicit queue.\\n\\nJust using a \`chan\` isn't going to cut it.\\n\\n## Adding a Queue\\n\\nGo has a doubly linked list in the standard library that we can use as the queue. This queue will contain the channels that are used to wake up the blocked call to acquire the semaphore.\\n\\nTrying to acquire a semaphore has one of two immediate outcomes:\\n- The fast path: there's an available permit and the call returns right away.\\n- The slow path: there's no permits, and we enqueue a channel and wait.\\n\\n\`\`\`text\\nWhen there are no available permits, G2 blocks on the Acquire() call\\nuntil an earlier goroutine, G1, calls Release().\\n\\nTime →\\n────────────────────────────────────────\\n\\nG2: Acquire() ──── blocks ─────▶ resumes\\n ▲\\nG1: Release() ───────┘\\n\`\`\`\\n\\nWe need four bits of state:\\n- The maximum number of permits\\n- The available number of permits\\n- A queue structure that stores channels\\n- A lock to protect access to all the above\\n\\n\`\`\`go\\nimport (\\n \\"container/list\\"\\n \\"sync\\"\\n)\\n\\ntype Semaphore struct {\\n mu sync.Mutex\\n free int64 // available permits\\n max int64 // maximum permits\\n waiters list.List // queue of chan struct{}, closed to wake\\n}\\n\\n// NewSemaphore creates a semaphore with n permits.\\nfunc NewSemaphore(n int64) \*Semaphore {\\n return \\u0026Semaphore{\\n free: n,\\n max: n,\\n }\\n}\\n\\n// Acquire blocks until a permit is available, then takes it.\\nfunc (s \*Semaphore) Acquire() {\\n s.mu.Lock()\\n\\n // Fast path: permit available\\n if s.free \\u003e 0 {\\n s.free--\\n s.mu.Unlock()\\n return\\n }\\n\\n // Slow path: enqueue ourselves and wait\\n waiter := make(chan struct{})\\n s.waiters.PushBack(waiter)\\n s.mu.Unlock()\\n\\n \\u003c-waiter // blocks until Release closes the channel\\n}\\n\\n// Release returns a permit. Panics if over-released.\\nfunc (s \*Semaphore) Release() {\\n s.mu.Lock()\\n\\n if s.free+1 \\u003e s.max {\\n s.mu.Unlock()\\n panic(\\"semaphore: released more than acquired\\")\\n }\\n s.free++\\n\\n // Wake the first waiter if any\\n if front := s.waiters.Front(); front != nil {\\n s.waiters.Remove(front)\\n s.free-- // reserve permit for waiter\\n s.mu.Unlock()\\n close(front.Value.(chan struct{})) // wake waiter (non-blocking)\\n return\\n }\\n\\n s.mu.Unlock()\\n}\\n\`\`\`\\n\\nI'm pretty happy with this. The only way I think I could use less LOC is by removing the panic on calling \`Release()\` too many times (then we don't need to track \`max\`).\\n\\nThe code would be easier to read if the \`Acquire()\` call reserved its own permit in all cases but I couldn't figure out a way to do this while keeping the FIFO constraint. Some semaphores do allow permit stealing behavior (sometimes called \\"barging\\") to increase throughput at the cost of fairness.\\n\\n## Context Cancellation\\n\\nGood programs don't keep doing work after it no longer matters. Adding context cancellation lets a blocked operation stop waiting when the surrounding task is canceled or times out, which prevents wasted effort and makes systems easier to reason about and shut down cleanly.\\n\\nInside \`Acquire()\`, when waiting on the signal from a \`Release()\` call via the channel, we need to race the context being cancelled.\\n\\nWhen the context is cancelled, there are two possible outcomes:\\n- The \`Acquire()\` call is still queued and it needs to clean its state up (by removing itself from the queue), and then return a context error.\\n- The \`Acquire()\` call has already been granted a permit and owns it, and so it needs to release that permit before returning a context error.\\n\\nIn order to tell these cases apart, we need a new bit of data: a \`granted\` flag that tracks whether a permit has been granted. Which I've wrapped inside this \`waiter\` struct with the existing channel:\\n\\n\`\`\`go\\ntype waiter struct {\\n ch chan struct{}\\n granted bool\\n}\\n\`\`\`\\n\\n\`Acquire()\` checks \`granted\` under the lock on cancellation. If we were granted a permit but are canceling anyway, we must release it:\\n\\n\`\`\`go\\nfunc (s \*Semaphore) Acquire(ctx context.Context) error {\\n s.mu.Lock()\\n\\n // Fast path\\n if s.free \\u003e 0 {\\n s.free--\\n s.mu.Unlock()\\n return nil\\n }\\n\\n w := \\u0026waiter{ch: make(chan struct{})}\\n elem := s.waiters.PushBack(w)\\n s.mu.Unlock()\\n\\n // Race the release signal and the context\\n select {\\n case \\u003c-w.ch:\\n return nil\\n\\n case \\u003c-ctx.Done():\\n s.mu.Lock()\\n\\n if w.granted {\\n // Permit was reserved for us, but we're canceling\\n // Must release the permit we own\\n s.mu.Unlock()\\n s.Release()\\n return ctx.Err()\\n }\\n\\n // Not yet granted, remove from queue\\n s.waiters.Remove(elem)\\n s.mu.Unlock()\\n return ctx.Err()\\n }\\n}\\n\`\`\`\\n\\nAnd \`Release()\` sets \`granted = true\` under the lock before waking the waiter:\\n\\n\`\`\`go\\nfunc (s \*Semaphore) Release() {\\n s.mu.Lock()\\n\\n if s.free+1 \\u003e s.max {\\n s.mu.Unlock()\\n panic(\\"semaphore: released more than acquired\\")\\n }\\n s.free++\\n\\n // Wake the first waiter if any\\n if front := s.waiters.Front(); front != nil {\\n w := front.Value.(\*waiter)\\n s.waiters.Remove(front)\\n s.free-- // reserve permit for waiter\\n w.granted = true // mark granted under the lock\\n s.mu.Unlock()\\n close(w.ch) // wake waiter\\n return\\n }\\n\\n s.mu.Unlock()\\n}\\n\`\`\`\\n\\nTo put it all together, here's the semaphore being used in my original example at the top:\\n\\n\`\`\`go\\ng, ctx := errgroup.WithContext(context.Background())\\nsema := NewSemaphore(10)\\n\\nfor \_, path := range files {\\n g.Go(func(p string) error {\\n err := sema.Acquire(ctx) // acquire a permit (and wait if needed)\\n if err != nil {\\n return err\\n }\\n defer sema.Release() // release the permit when we return\\n\\n f, err := os.Open(p)\\n if err != nil {\\n return err\\n }\\n defer f.Close()\\n\\n return processFile(f)\\n }(path))\\n}\\n\\nif err := g.Wait(); err != nil {\\n return err\\n}\\n\`\`\`\\n\\nIn the end, a semaphore is \\"just\\" a counter plus a way to park goroutines until the counter says they can proceed. The surprising part is everything around that core: what order you unblock waiters in, what happens when work becomes irrelevant, and what invariants you need to keep to avoid deadlocks and leaks.\\n\\nA plain buffered channel is a good-enough concurrency limiter but it doesn't give you FIFO semantics when many goroutines contend at once, and it doesn't naturally compose with cancellation.\\n\\n## Bugs I Ran Into\\n\\nWhile iterating on this semaphore, I ran into two particularly tricky bugs.\\n\\nThe first was a deadlock caused by \`Release()\` sending a message on an unbuffered channel without a listener:\\n\\n1. \`Release()\` removes the waiter from the queue and is about to send the wake-up message\\n2. The waiter's \`select\` chooses \`ctx.Done()\` first and returns without receiving\\n3. \`Release()\` blocks forever on the send because nobody is receiving anymore!\\n\\nI fixed this by closing the channel in \`Release()\` instead of sending an empty struct.\\n\\nThe second was a permit leak caused by trying to detect \\"was I granted a permit?\\" by checking whether the channel was closed. There was a race between \`Release()\` reserving the permit and the waiter observing that fact:\\n\\n1. \`Release()\` reserves a permit for a waiter (\`s.free--\`)\\n2. The waiter's context is cancelled, the waiter re-locks\\n3. The waiter tries to infer \\"granted\\" from the channel state, gets the wrong answer\\n4. The waiter returns \`ctx.Err()\` without releasing the permit that was reserved for it\\n\\nThat permit is gone forever. I fixed this with the \`granted\` flag — it's set under the lock, so the waiter can reliably check whether it owns a permit.\\n\\nAfter I had everything working, I looked up the source code of the semaphore I would typically use, \[x/sync/semaphore\](https://pkg.go.dev/golang.org/x/sync/semaphore) from Go's extended library. I found that it uses the same patterns: closing the channel to avoid the deadlock, and keeping all waiter state under the mutex to avoid the permit leak. The channel is just the notification mechanism, and the mutex-protected state is the source of truth.\\n","title":"A Fair, Cancelable Semaphore in Go","description":"Building a fair, cancelable semaphore in Go and the subtle concurrency issues involved.","date":"2025-12-21","tags":\["go"\],"outdated":false},"nextPost":{"id":"building-a-runtime-with-quickjs","content":"\\nA JavaScript engine (e.g. V8, JavaScriptCore) executes JavaScript code. It doesn't know about things like files, HTTP requests, or timers.\\n\\nOn the other hand, a JavaScript runtime (e.g. Node.js, Bun) is a more complete environment where JavaScript runs. It contains a JavaScript engine, extra APIs, an event loop and task queues, and platform-specific features.\\n\\nThat's what I'm hacking on today: a \[tiny runtime\](https://github.com/healeycodes/andjs) with \`console.log\`, \`process.uptime()\`, \`setTimeout\` and \`clearTimeout\`, \`fs.readFileSync\` and \`fs.readFile\`, as well as an event loop and worker pool for file I/O. Built on top of QuickJS.\\n\\nHere's an example program it can run:\\n\\n\`\`\`js\\nconst startedAt = process.uptime();\\nconsole.log(\\"runtime booted\\");\\n\\nsetTimeout(async () =\\u003e { // Timers\\n console.log(\\"uptime:\\", process.uptime() - startedAt);\\n\\n // Sync I/O\\n console.log(\\"sync bytes:\\", fs.readFileSync(\\"Makefile\\", \\"utf8\\").length);\\n\\n // Async I/O\\n console.log(\\"async bytes:\\", (await fs.readFile(\\"Makefile\\", \\"utf8\\")).length);\\n}, 100);\\n\`\`\`\\n\\n## Booting QuickJS from a Custom Executable\\n\\nQuickJS actually ships with a small shell/runtime built around \`qjs.c\` and a basic standard library, but I'm not going to re-use any of it. We'll start from scratch.\\n\\nSo, to begin with, we need to boot QuickJS from a custom executable. The smallest useful embedder involves creating an instance of the engine (\`JSRuntime\`), an execution environment (\`JSContext\`), and a way to read a code file, evaluate it, and print any exceptions.\\n\\n\`\`\`c\\nint main(int argc, char \*\*argv)\\n{\\n JSRuntime \*rt = JS\_NewRuntime();\\n JSContext \*ctx = JS\_NewContext(rt);\\n int exit\_code;\\n\\n // ... install globals later\\n\\n exit\_code = run\_file(ctx, argv\[1\]);\\n\\n // ... then run the event loop until timers / async work complete\\n\\n JS\_FreeContext(ctx);\\n JS\_FreeRuntime(rt);\\n return exit\_code;\\n}\\n\`\`\`\\n\\nQuickJS runs JavaScript but we, the host, decide what the global environment looks like; what the input is, and how the outputs are returned to the user.\\n\\n\`\`\`c\\nstatic int run\_file(JSContext \*ctx, const char \*path)\\n{\\n SourceFile source = {0};\\n JSValue result;\\n int exit\_code = 1;\\n\\n if (read\_file(path, \\u0026source, NULL, 0) != 0) {\\n return 1;\\n }\\n\\n // QuickJS runs the program, and returns a JSValue\\n result = JS\_Eval(ctx,\\n (const char \*)source.bytes,\\n source.len,\\n path,\\n JS\_EVAL\_TYPE\_GLOBAL);\\n\\n // Report errors\\n if (JS\_IsException(result)) {\\n dump\_exception(ctx);\\n } else {\\n exit\_code = 0;\\n }\\n\\n // Host-created JSValues must be freed!\\n JS\_FreeValue(ctx, result);\\n free\_source\_file(\\u0026source);\\n return exit\_code;\\n}\\n\`\`\`\\n\\nWe can run something already:\\n\\n\`\`\`bash\\n$ ./andjs example-uncaught-throw.js\\nError: test exception\\n at \\u003ceval\\u003e (example-throw.js:1:16)\\n\`\`\`\\n\\n## Adding console.log\\n\\nOur first problem is that we can't see anything happening unless an error is thrown. Let's solve this by adding a fan-favorite, \`console.log\`.\\n\\nA host function receives JavaScript arguments and can stringify them by calling QuickJS functions (i.e. \`JS\_ToString\`).\\n\\nThe \`console.log\` function that we're adding will be connected by attaching a \`console\` object to the global object with a \`log\` function inside, which is wired up to the following C function.\\n\\n\`\`\`c\\nstatic JSValue js\_console\_log(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n for (int i = 0; i \\u003c argc; i++) {\\n JSValue string\_value;\\n const char \*text;\\n\\n if (i \\u003e 0) {\\n fputc(' ', stdout);\\n }\\n\\n // Note: not Node.js-accurate formatting\\n string\_value = JS\_ToString(ctx, argv\[i\]);\\n text = JS\_ToCString(ctx, string\_value);\\n fputs(text, stdout);\\n\\n JS\_FreeCString(ctx, text);\\n JS\_FreeValue(ctx, string\_value);\\n }\\n\\n fputc('\\\\n', stdout);\\n return JS\_UNDEFINED;\\n}\\n\`\`\`\\n\\nBefore QuickJS runs any JavaScript code, we need to first set up the global object.\\n\\n\`\`\`c\\nstatic int install\_console(JSContext \*ctx)\\n{\\n JSValue global\_obj = JS\_GetGlobalObject(ctx);\\n JSValue console\_obj = JS\_NewObject(ctx);\\n JSValue log\_fn = JS\_NewCFunction(ctx, js\_console\_log, \\"log\\", 1);\\n\\n JS\_SetPropertyStr(ctx, console\_obj, \\"log\\", log\_fn);\\n JS\_SetPropertyStr(ctx, global\_obj, \\"console\\", console\_obj);\\n\\n // ... free temporary handles\\n return 0;\\n}\\n\`\`\`\\n\\nWith that configured, let's take a look at our first runtime side-effect:\\n\\n\`\`\`bash\\n# console.log(\\"sum:\\", 1 + 2, \\"ok\\");\\n$ ./andjs example-log.js\\nsum: 3 ok\\n\`\`\`\\n\\n## Adding process.uptime()\\n\\nThe first piece of real runtime state we're going to store is the process start time. I've chosen a pretty simple Node.js API to add here, one I don't think I've ever called directly; \`process.uptime()\`, the number of seconds the process has been running.\\n\\nThis means we're tracking something outside of the engine, rather than \`console.log\` where we only registered a pure function on the engine's global object.\\n\\n\`\`\`c\\ntypedef struct {\\n double start\_time; // Used by process.uptime()\\n int next\_timer\_id; // (We'll add more timers\\n Timer \*timers; // in the next section.)\\n // ...\\n} RuntimeState;\\n\`\`\`\\n\\nQuickJS provides a sensible place to store host state via \`JS\_SetRuntimeOpaque(...)\`, which allows us to associate our own data with the QuickJS runtime abstraction. It stores a user-defined pointer (e.g. we define its type and manage its lifetime). Some QuickJS callbacks receive a \`JSRuntime\`, which lets us access this state directly, avoiding an extra lookup.\\n\\n\`\`\`c\\n// Declaring, then storing, our custom runtime state for later\\nRuntimeState \*state;\\n\\n// ..\\n\\nstate = calloc(1, sizeof(\*state));\\nnow\_monotonic(\\u0026state-\\u003estart\_time);\\nJS\_SetRuntimeOpaque(rt, state);\\n\`\`\`\\n\\nAn interesting aside here is how we track uptime (as opposed to wallclock time). A monotonic clock moves forward and isn't affected by wallclock adjustments like NTP or the user changing the system time. Wallclock time has none of these properties and it's feasible that, if it powered \`process.uptime()\`, then sometimes this function would return a negative number!\\n\\n\`\`\`c\\nstatic JSValue js\_process\_uptime(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n double now;\\n\\n // ... argument handling\\n now\_monotonic(\\u0026now);\\n\\n // Return the difference between now and start\\n return JS\_NewFloat64(ctx, now - state-\\u003estart\_time);\\n}\\n\`\`\`\\n\\nNotably, process uptime is not script execution start, so you'll never see a zero.\\n\\n\`\`\`bash\\n# const u = process.uptime();\\n# console.log(u);\\n$ ./andjs example-process-uptime.js\\n0.0003500021994113922\\n\`\`\`\\n\\n## Adding setTimeout and clearTimeout\\n\\nWe're getting closer to one of the reasons I wanted to build this project, and write this post, which is that I wanted to build an event loop from scratch.\\n\\nThe event loop is the scheduler behind JavaScript. First, sync code runs. Then, async work like timers, events, and promises start triggering callbacks, running more sync code (and the cycle continues). The event loop schedules all this work.\\n\\nEven though we don't have an event loop just yet, we can still queue up work for it to handle. Essentially, that's all a timer is: some queued work.\\n\\n\`\`\`c\\ntypedef struct Timer Timer;\\n\\nstruct Timer {\\n int id; // Timeout ID used in JavaScript\\n double deadline; // Monotonic expire time\\n JSValue callback; // Reference to the JavaScript callback function\\n Timer \*next;\\n};\\n\`\`\`\\n\\nI chose a sorted linked list to store all the scheduled timers because it's fast enough and requires very little code to implement, compared to alternative solutions like a priority queue.\\n\\nTimers are sorted because, when it's time to run one, and there are multiple that are past their deadline, we only need to read the first item to get started.\\n\\n\`\`\`c\\nstatic void insert\_timer(RuntimeState \*state, Timer \*timer)\\n{\\n Timer \*\*slot = \\u0026state-\\u003etimers;\\n\\n // Find the earliest place in the LL to place it\\n while (\*slot \\u0026\\u0026 (\*slot)-\\u003edeadline \\u003c= timer-\\u003edeadline) {\\n slot = \\u0026(\*slot)-\\u003enext;\\n }\\n\\n timer-\\u003enext = \*slot;\\n \*slot = timer;\\n}\\n\`\`\`\\n\\nOf course, the downside is that inserting takes O(n) time ... but isn't the code lovely and terse? Albeit CPU cache unfriendly.\\n\\nTo set a timer, we need: the time it should run, and a reference to its callback so that, later, we can get QuickJS to execute the callback at the correct time.\\n\\n\`\`\`c\\nstatic JSValue js\_set\_timeout(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n Timer \*timer = calloc(1, sizeof(\*timer));\\n double now;\\n int64\_t delay\_ms = 0;\\n\\n // ... validate fn and ms\\n\\n now\_monotonic(\\u0026now);\\n\\n timer-\\u003eid = state-\\u003enext\_timer\_id++;\\n timer-\\u003edeadline = now + (double)delay\_ms / 1000.0;\\n timer-\\u003ecallback = JS\_DupValue(ctx, argv\[0\]);\\n\\n insert\_timer(state, timer);\\n return JS\_NewInt32(ctx, timer-\\u003eid);\\n}\\n\`\`\`\\n\\nThe callback lifetime is host-managed via \`JS\_DupValue(...)\` and \`JS\_FreeValue(...)\`. In QuickJS, values (\`JSValue\`) are reference-counted. So when we call \_dup\_, we're saying \\"hey, I have another reference to this value\\". And when we call \_free\_, we're releasing one of those references.\\n\\nI didn't have too much trouble managing shared data between the runtime and the engine once I understood the APIs (which did not take as long as I would've thought); this shows the care that QuickJS was built with.\\n\\nClearing a timer is simpler. We delete it, free memory, and return \`undefined\`.\\n\\n\`\`\`c\\nstatic JSValue js\_clear\_timeout(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n int32\_t id;\\n Timer \*\*slot = \\u0026state-\\u003etimers;\\n\\n // ... convert argv\[0\] to id\\n\\n while (\*slot) {\\n if ((\*slot)-\\u003eid == id) {\\n Timer \*timer = \*slot;\\n \*slot = timer-\\u003enext;\\n JS\_FreeValue(ctx, timer-\\u003ecallback);\\n free(timer);\\n break;\\n }\\n slot = \\u0026(\*slot)-\\u003enext;\\n }\\n\\n return JS\_UNDEFINED;\\n}\\n\`\`\`\\n\\nThese two functions, \`js\_set\_timeout\` and \`js\_clear\_timeout\`, are set on the global object like \`console\`. As we step into the more heady runtime internals, I’ll be able to show fewer code snippets without spamming you, but the wiring is mostly the same.\\n\\nAt this point, we're able to schedule as many timers as our heap will allow; but they stay waiting until the next section.\\n\\n## Adding the Event Loop\\n\\nThe host, not QuickJS, decides when callbacks (e.g. timers) run.\\n\\n\`\`\`js\\nsetTimeout(() =\\u003e {\\n console.log('A'); // inside timer callback\\n\\n // schedules a QuickJS job (here, a promise continuation / microtask)\\n Promise.resolve().then(() =\\u003e console.log('A+'));\\n}, 0);\\n\\nsetTimeout(() =\\u003e {\\n console.log('B'); // inside timer callback (runs later)\\n}, 5);\\n\\nconsole.log('sync'); // runs before any timer callbacks\\n\`\`\`\\n\\nRunning expired timers involves finding them, and then triggering JavaScript execution with \`JS\_Call(...)\`.\\n\\nImportantly, after we trigger a callback, we need to drain pending QuickJS jobs so that promise continuations run before the next timer or I/O callback. In this case, those pending jobs are promise reaction jobs, often thought of as microtasks.\\n\\n\`\`\`c\\nstatic int run\_expired\_timers(JSContext \*ctx)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n double now;\\n\\n now\_monotonic(\\u0026now);\\n\\n while (state-\\u003etimers \\u0026\\u0026 state-\\u003etimers-\\u003edeadline \\u003c= now) {\\n JSValue result;\\n Timer \*timer = state-\\u003etimers;\\n\\n state-\\u003etimers = timer-\\u003enext;\\n result = JS\_Call(ctx, timer-\\u003ecallback, JS\_UNDEFINED, 0, NULL);\\n\\n // ... free timer, report exception\\n\\n drain\_pending\_jobs(JS\_GetRuntime(ctx));\\n now\_monotonic(\\u0026now);\\n }\\n\\n return 0;\\n}\\n\`\`\`\\n\\nSince I've planned ahead, and I know where we're going (async I/O!), the event loop shape here is already trending towards supporting different types of callbacks.\\n\\nEach step inside the event loop like \`run\_expired\_timers\` and \`run\_completed\_file\_jobs\` drains pending QuickJS jobs after every callback. This gives the ordering I want here: promise continuations queued by a callback run before the next timer or I/O callback.\\n\\n\`\`\`c\\nstatic int run\_event\_loop(JSContext \*ctx)\\n{\\n JSRuntime \*rt = JS\_GetRuntime(ctx);\\n RuntimeState \*state = JS\_GetRuntimeOpaque(rt);\\n\\n while (state-\\u003etimers || runtime\_has\_async\_work(state) || JS\_IsJobPending(rt)) {\\n struct timeval timeout;\\n struct timeval \*timeout\_ptr;\\n\\n run\_expired\_timers(ctx);\\n run\_completed\_file\_jobs(ctx); // No-op for now; coming soon in next section\\n drain\_pending\_jobs(rt);\\n\\n if (!state-\\u003etimers \\u0026\\u0026 !runtime\_has\_async\_work(state) \\u0026\\u0026 !JS\_IsJobPending(rt)) {\\n break;\\n }\\n\\n // Find the earliest timer\\n compute\_wait\_timeout(state, \\u0026timeout, \\u0026timeout\_ptr);\\n\\n // Sleep until I/O completes or the next timer expires\\n wait\_for\_events(state, timeout\_ptr);\\n }\\n\\n return 0;\\n}\\n\`\`\`\\n\\nOur runtime needs a way to sleep until something happens without burning CPU; and be able to wake up promptly. For these wake-up events, I've chosen a kernel pipe (regular readers will remember these pipes from last week's \[Building a Shell\](https://healeycodes.com/building-a-shell)).\\n\\nThe workers, running on separate threads, will use this wakeup pipe to report when they've completed a task. The event loop, over in the runtime's main thread, uses \`select()\` to monitor the wakeup pipe's file descriptor until it's ready for reading. Additionally, the earliest timer is set as \`select()\`'s timeout so that the event loop can stop waiting on the wakeup pipe and go and handle timer callbacks.\\n\\n\`\`\`c\\nstatic int wait\_for\_events(RuntimeState \*state, struct timeval \*timeout\_ptr)\\n{\\n fd\_set read\_fds;\\n\\n FD\_ZERO(\\u0026read\_fds);\\n FD\_SET(state-\\u003ewakeup\_pipe\[0\], \\u0026read\_fds);\\n\\n // Wait for data to be written to the wakeup pipe until the timeout\\n select(state-\\u003ewakeup\_pipe\[0\] + 1, \\u0026read\_fds, NULL, NULL, timeout\_ptr);\\n\\n if (FD\_ISSET(state-\\u003ewakeup\_pipe\[0\], \\u0026read\_fds)) {\\n clear\_wakeup\_pipe(state);\\n }\\n\\n return 0;\\n}\\n\`\`\`\\n\\nThe wakeup pipe will not deliver the completed work e.g. the contents of a file that's been read. It will only deliver a single byte (literally \`1\`) to signal that some work has been done. The async file jobs are stored in a linked list that contains the promise's \`resolve\` and \`reject\` functions (as \`JSValue\`s), along with the bytes that have been read. But more on that when we get to async I/O.\\n\\nFirst we need to handle plain old sync I/O.\\n\\n## Adding fs.readFileSync\\n\\nSync file I/O is easy to implement because the main thread can just block. For the API, although Node.js-like, I've kept it quite narrow; just \`path\` and only \`utf8\`.\\n\\nThe host reads a file and either returns a JavaScript string or throws an error.\\n\\n\`\`\`c\\nstatic JSValue js\_fs\_read\_file\_sync(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n SourceFile source = {0};\\n const char \*path;\\n const char \*encoding;\\n char error\_buf\[512\] = {0};\\n\\n // ... convert args to C strings\\n // ... reject anything except \\"utf8\\"\\n\\n // Simple read util, reads file bytes into \`source\`\\n if (read\_file(path, \\u0026source, error\_buf, sizeof(error\_buf)) != 0) {\\n return JS\_ThrowInternalError(ctx, \\"%s\\", error\_buf);\\n }\\n\\n return JS\_NewStringLen(ctx, (const char \*)source.bytes, source.len);\\n}\\n\`\`\`\\n\\nHere we use QuickJS's \`JS\_NewStringLen\` to create a new \`JSValue\` for QuickJS to copy into its managed memory and eventually garbage collect. Unlike \`JS\_NewString\`, which expects a null-terminated C string, \`JS\_NewStringLen\` is better when you have a buffer with a known length and want to avoid a call to \`strlen\`.\\n\\n## Adding fs.readFile with a Worker Pool\\n\\nWhen \`fs.readFile\` is called, the resolution (or rejection) of the created promise becomes the responsibility of the runtime.\\n\\nThe promise object is created in the host and passed back to the engine. The host keeps references to the promise's \`resolve\` and \`reject\` functions, so when the task is complete it can call one of them and then let QuickJS run the follow-up promise jobs.\\n\\nIn order to support parallel I/O, I went with a threaded worker pool. These workers never run JavaScript. They get a task like \\"read file at $path\\" and go and get those bytes. There's a pending job queue (with path names) and a completed job queue (with file bytes or errors). The workers take a job from the pending queue, do it, and then put the result in the complete queue.\\n\\nWorkers write \`1\` to the wakeup pipe to signal the main thread (where \`select()\` is monitoring) so that it can call \`resolve\` or \`reject\` with the result.\\n\\nAsync file jobs are stored in a linked list, with references to the \`resolve\` and \`reject\` functions. We're also adding some new runtime state: a mutex (since the main thread and workers will be reading and writing shared memory), and a \`pthread\_cond\_t\` so the main thread can signal workers to check the pending queue.\\n\\n\`\`\`c\\ntypedef struct AsyncFileJob AsyncFileJob;\\n\\nstruct AsyncFileJob {\\n char \*path;\\n JSValue resolve; // JavaScript function reference\\n JSValue reject; // JavaScript function reference\\n uint8\_t \*bytes; // Maybe file content\\n size\_t len;\\n char \*error\_message; // Maybe error\\n AsyncFileJob \*next;\\n};\\n\\ntypedef struct {\\n // ...\\n pthread\_mutex\_t mutex;\\n pthread\_cond\_t worker\_cond; // For waking up worker\\n int wakeup\_pipe\[2\]; // Worker uses to signal main thread\\n size\_t active\_file\_jobs; // The count, so runtime can exit\\n\\n AsyncFileJob \*pending\_jobs\_head;\\n AsyncFileJob \*pending\_jobs\_tail;\\n AsyncFileJob \*completed\_jobs\_head;\\n AsyncFileJob \*completed\_jobs\_tail;\\n\\n pthread\_t workers\[WORKER\_COUNT\];\\n} RuntimeState;\\n\`\`\`\\n\\nThis is all the runtime state we'll need to add in order to implement the features I listed at the start. The rest of the work is driving these queues. First, the C function that \`readFile\` calls into when a program wants to read some file content async.\\n\\nA promise is created and returned, a pending job is queued up, and the worker is signalled.\\n\\n\`\`\`c\\nstatic JSValue js\_fs\_read\_file(JSContext \*ctx, JSValueConst this\_val,\\n int argc, JSValueConst \*argv)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n JSValue promise;\\n JSValue resolving\_funcs\[2\];\\n AsyncFileJob \*job;\\n\\n // ... validate (path, \\"utf8\\")\\n\\n promise = JS\_NewPromiseCapability(ctx, resolving\_funcs);\\n\\n job = calloc(1, sizeof(\*job));\\n job-\\u003epath = strdup(path);\\n job-\\u003eresolve = resolving\_funcs\[0\];\\n job-\\u003ereject = resolving\_funcs\[1\];\\n\\n pthread\_mutex\_lock(\\u0026state-\\u003emutex);\\n state-\\u003eactive\_file\_jobs++; // Track active jobs so the runtime can exit when it's zero\\n enqueue\_async\_file\_job(\\u0026state-\\u003epending\_jobs\_head, \\u0026state-\\u003epending\_jobs\_tail, job);\\n pthread\_cond\_signal(\\u0026state-\\u003eworker\_cond); // Signal worker\\n pthread\_mutex\_unlock(\\u0026state-\\u003emutex);\\n\\n return promise;\\n}\\n\`\`\`\\n\\nOver in the worker, it waits for the \\"new job signal\\" with \`pthread\_cond\_wait\` (with some checks to see if it should tear itself down). It then dequeues the pending job, reads a file, and writes the result to the complete job queue.\\n\\nAs mentioned earlier, the worker doesn't know anything about JavaScript. It just runs a little bit of C code.\\n\\n\`\`\`c\\nstatic void \*worker\_main(void \*opaque)\\n{\\n RuntimeState \*state = opaque;\\n\\n for (;;) {\\n AsyncFileJob \*job;\\n SourceFile source = {0};\\n char error\_buf\[512\] = {0};\\n\\n pthread\_mutex\_lock(\\u0026state-\\u003emutex);\\n while (!state-\\u003epending\_jobs\_head \\u0026\\u0026 !state-\\u003estop\_workers) {\\n\\n // Wait for signal\\n pthread\_cond\_wait(\\u0026state-\\u003eworker\_cond, \\u0026state-\\u003emutex);\\n }\\n\\n if (state-\\u003estop\_workers \\u0026\\u0026 !state-\\u003epending\_jobs\_head) {\\n pthread\_mutex\_unlock(\\u0026state-\\u003emutex);\\n break;\\n }\\n\\n job = dequeue\_async\_file\_job(\\u0026state-\\u003epending\_jobs\_head, \\u0026state-\\u003epending\_jobs\_tail);\\n pthread\_mutex\_unlock(\\u0026state-\\u003emutex);\\n\\n if (!job) {\\n continue;\\n }\\n\\n // Workers only move C data around.\\n if (read\_file(job-\\u003epath, \\u0026source, error\_buf, sizeof(error\_buf)) == 0) {\\n job-\\u003ebytes = source.bytes;\\n job-\\u003elen = source.len;\\n } else {\\n job-\\u003eerror\_message = strdup(error\_buf);\\n }\\n\\n pthread\_mutex\_lock(\\u0026state-\\u003emutex);\\n enqueue\_async\_file\_job(\\u0026state-\\u003ecompleted\_jobs\_head, \\u0026state-\\u003ecompleted\_jobs\_tail, job);\\n pthread\_mutex\_unlock(\\u0026state-\\u003emutex);\\n\\n signal\_event\_loop(state); // Writes 1 to wakeup pipe\\n }\\n}\\n\`\`\`\\n\\nIn the runtime's main thread, after the event loop has received an event, it's time to handle the completed file jobs. We start by locking and consuming the completed jobs, and then calling the stored \`resolve\` or \`reject\` functions causing the promise to become fulfilled or rejected. This schedules follow-up QuickJS jobs but doesn't start them just yet.\\n\\nThose pending QuickJS jobs are executed with \`drain\_pending\_jobs\` which calls \`JS\_ExecutePendingJob\` on each.\\n\\n\\n\`\`\`c\\nstatic int run\_completed\_file\_jobs(JSContext \*ctx)\\n{\\n RuntimeState \*state = JS\_GetRuntimeOpaque(JS\_GetRuntime(ctx));\\n AsyncFileJob \*jobs;\\n\\n pthread\_mutex\_lock(\\u0026state-\\u003emutex);\\n jobs = state-\\u003ecompleted\_jobs\_head;\\n state-\\u003ecompleted\_jobs\_head = NULL;\\n state-\\u003ecompleted\_jobs\_tail = NULL;\\n pthread\_mutex\_unlock(\\u0026state-\\u003emutex);\\n\\n while (jobs) {\\n AsyncFileJob \*job = jobs;\\n JSValue arg;\\n JSValue result;\\n\\n jobs = jobs-\\u003enext;\\n\\n if (job-\\u003eerror\_message) {\\n arg = new\_error\_value(ctx, job-\\u003eerror\_message);\\n result = JS\_Call(ctx, job-\\u003ereject, JS\_UNDEFINED, 1, (JSValueConst \*)\\u0026arg);\\n } else {\\n arg = JS\_NewStringLen(ctx, (const char \*)job-\\u003ebytes, job-\\u003elen);\\n result = JS\_Call(ctx, job-\\u003eresolve, JS\_UNDEFINED, 1, (JSValueConst \*)\\u0026arg);\\n }\\n\\n JS\_FreeValue(ctx, arg);\\n JS\_FreeValue(ctx, result);\\n\\n // Important: this is what lets await continue.\\n drain\_pending\_jobs(JS\_GetRuntime(ctx));\\n\\n // ... free the completion record\\n }\\n\\n return 0;\\n}\\n\`\`\`\\n\\nEverything has been building up to the fairly terse \`run\_event\_loop\`, where all the async work is waited on.\\n\\nOn receiving an event, the event loop runs expired timers, delivers file job results into the engine, drains pending QuickJS jobs, and then exits or starts waiting for more events.\\n\\n\`\`\`c\\nstatic int run\_event\_loop(JSContext \*ctx)\\n{\\n JSRuntime \*rt = JS\_GetRuntime(ctx);\\n RuntimeState \*state = JS\_GetRuntimeOpaque(rt);\\n\\n while (state-\\u003etimers || runtime\_has\_async\_work(state) || JS\_IsJobPending(rt)) {\\n struct timeval timeout;\\n struct timeval \*timeout\_ptr;\\n\\n run\_expired\_timers(ctx);\\n run\_completed\_file\_jobs(ctx);\\n drain\_pending\_jobs(rt);\\n\\n if (!state-\\u003etimers \\u0026\\u0026 !runtime\_has\_async\_work(state) \\u0026\\u0026 !JS\_IsJobPending(rt)) {\\n break;\\n }\\n\\n compute\_wait\_timeout(state, \\u0026timeout, \\u0026timeout\_ptr);\\n wait\_for\_events(state, timeout\_ptr);\\n }\\n\\n return 0;\\n}\\n\`\`\`\\n\\nAs async work continues to be created, the core of the event loop continues to run and loop!\\n\\nNote: I haven't verified how semantically close my runtime is to Node.js's priority of I/O vs timers.\\n\\nFor fun, I benchmarked my runtime against Node.js \`v24.14.0\` on an Apple M1 Pro. The benchmark is reading ten 1MB files using \`Promise.all\`.\\n\\nOverall time (includes startup):\\n- \`node\` 27.7 ms ± 0.4 ms\\n- \`andjs\` 7.2 ms ± 0.3 ms\\n\\nFile-read portion:\\n- \`node\` 3.828 ms\\n- \`andjs\` 4.620 ms\\n\\nIt's no surprise that QuickJS, and a barebones runtime, has a faster startup. That's one of QuickJS's value propositions as an engine. To get comparatively close on the file-read portion is quite nice.\\n\\nAlthough, not much is being measured. There isn't really much overhead you can put on top of ten small file-read tasks. But measuring things is fun nonetheless!\\n\\nGrab the runtime source code at \[healeycodes/andjs\](https://github.com/healeycodes/andjs).\\n","title":"Building a Runtime with QuickJS","description":"Building a tiny JavaScript runtime on top of QuickJS with timers, file I/O, and an event loop.","date":"2026-03-26","tags":\["c"\],"outdated":false}},"\_\_N\_SSG":true},"page":"/\[id\]","query":{"id":"building-a-shell"},"buildId":"555cphs4xcO6kBmxtItHJ","isFallback":false,"gsp":true,"scriptLoader":\[\]}
