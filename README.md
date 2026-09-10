# C-Compiler

A compiler for a subset of C, built with **ANTLR 4** (C++ target). It takes a `.c` source
file and walks it all the way through the classic compiler pipeline — lexing, parsing,
symbol-table construction, semantic analysis, Intel 8086 assembly generation, and a
peephole optimization pass.

### 🎥 Demonstration video

**https://youtu.be/ZMYTYaUt3is?si=jt7fuTfNsdm0NyeG**

---

## Table of contents

- [What it does](#what-it-does)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Environment setup](#environment-setup)
- [Build and run](#build-and-run)
- [Reading the output](#reading-the-output)
- [The language it accepts](#the-language-it-accepts)
- [Errors it reports](#errors-it-reports)
- [Optimizations](#optimizations)
- [Where to make changes](#where-to-make-changes)
- [Troubleshooting](#troubleshooting)

---

## What it does

```
  input.c
     │
     ▼
┌──────────────────────┐
│  Lexer               │  C2105133Lexer.g4      →  output/lexerLog.txt
│  (tokenizing)        │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│  Parser              │  C2105133Parser.g4     →  output/parserLog.txt
│  + symbol table      │  2105133_SymbolTable.h
│  + semantic checks   │                        →  output/errorLog.txt
│  + code generation   │                        →  output/asmFile.asm
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│  Peephole optimizer  │                        →  output/optasmFile.asm
└──────────────────────┘
```

Everything happens in a single pass: the semantic actions embedded in the ANTLR grammar
build the symbol table, report errors, and emit 8086 assembly as the parse proceeds. The
optimizer then runs over the emitted assembly and writes a second, tightened file.

## Repository layout

```
C-Compiler/
├── src/
│   ├── C2105133Lexer.g4        ANTLR lexer grammar — tokens + lexer log
│   ├── C2105133Parser.g4       ANTLR parser grammar — grammar rules, semantic
│   │                           actions, symbol-table calls, 8086 codegen, optimizer
│   ├── Ctester.cpp             Driver: opens the files, wires up the lexer/parser
│   ├── 2105133_SymbolInfo.h    One symbol (name, type, array/function metadata)
│   ├── 2105133_ScopeTable.h    One hash-table scope, with sdbm / djb2 hashing
│   ├── 2105133_SymbolTable.h   Stack of scopes: enter/exit scope, insert, lookup
│   ├── library.txt             Hand-written 8086 routines (println, new_line, …)
│   │                           appended verbatim to the generated assembly
│   └── run-script.sh           Generate → compile → run, in one command
│
├── samples/
│   ├── test.c                  A valid program, good first thing to compile
│   ├── test_syntax_error.c     A program with a deliberate syntax error
│   └── reference/              input1–5.txt with the expected log1–5.txt and
│                               error1–5.txt, for checking your changes
│
└── README.md
```

Only source files are tracked. Everything ANTLR or `g++` generates (`C2105133Lexer.cpp`,
`*.o`, `Ctester.out`, `src/output/`, …) is listed in `.gitignore` and is recreated on
every build — never commit it.

## Prerequisites

A Linux environment. On Windows, use **WSL2** (Ubuntu) — the build script uses Unix paths
and `LD_LIBRARY_PATH`, so it will not work from PowerShell or CMD.

| Requirement | Why |
| --- | --- |
| Java 11 or newer | The ANTLR tool itself is a Java program |
| Python 3 + pip | Used to install `antlr4-tools`, which provides the `antlr4` command |
| ANTLR **4.13.2** | The version the grammars are written against |
| ANTLR C++ runtime 4.13.2 | Linked into the compiler binary |
| `g++` with C++17 | Builds the generated parser and the driver |
| CMake + make | Needed once, to build the C++ runtime |

## Environment setup

Run these once. Every step is copy-pasteable on Ubuntu / WSL2.

### 1. Base tools

```bash
sudo apt update
sudo apt install -y build-essential cmake pkg-config uuid-dev default-jdk python3-pip unzip wget
```

### 2. The ANTLR tool

`run-script.sh` calls `antlr4 -v 4.13.2`, which is the `antlr4-tools` launcher — it
downloads and pins the right ANTLR jar for you.

```bash
pip install antlr4-tools
```

Confirm it works (the first run downloads the jar, so give it a moment):

```bash
antlr4 -v 4.13.2
```

If the shell cannot find `antlr4`, add pip's script directory to your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 3. The ANTLR C++ runtime

The generated parser is C++, so it needs the ANTLR C++ runtime installed into
`/usr/local` — that is exactly where `run-script.sh` looks for it
(`-I/usr/local/include/antlr4-runtime` and `-L/usr/local/lib`).

```bash
cd /tmp
wget https://www.antlr.org/download/antlr4-cpp-runtime-4.13.2-source.zip
mkdir -p antlr4-cpp-runtime && cd antlr4-cpp-runtime
unzip ../antlr4-cpp-runtime-4.13.2-source.zip

mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)"
sudo make install
sudo ldconfig
```

Verify the two things the build script depends on now exist:

```bash
ls /usr/local/include/antlr4-runtime/antlr4-runtime.h
ls /usr/local/lib/libantlr4-runtime.so
```

Both must print a path. If they do, your environment is ready.

## Build and run

The build script must be run **from inside `src/`**, because the compiler resolves
`library.txt` and `output/` relative to the current directory.

```bash
cd src
bash run-script.sh ../samples/test.c
```

That single command does four things:

1. Runs ANTLR on `C2105133Lexer.g4` and `C2105133Parser.g4` to generate the C++ parser.
2. Compiles the generated parser plus `Ctester.cpp` with `g++ -std=c++17`.
3. Links against the ANTLR runtime to produce `Ctester.out`.
4. Runs `Ctester.out` on the file you passed, writing everything into `src/output/`.

Expect the first build to take a minute or two — `C2105133Parser.g4` is a large grammar.
On success you will see:

```
Parsing completed. Check the output files for details.
```

Try the other samples too:

```bash
bash run-script.sh ../samples/test_syntax_error.c
bash run-script.sh ../samples/reference/input3.txt
```

### Cleaning up

Generated files are all gitignored, so one command removes them:

```bash
git clean -Xdf
```

## Reading the output

Every run writes into `src/output/`:

| File | Contents |
| --- | --- |
| `lexerLog.txt` | Every token the lexer produced, with line numbers and lexemes |
| `parserLog.txt` | The grammar rule matched at each step, the symbol table printed at every scope exit, and a final error count |
| `errorLog.txt` | Syntax and semantic errors only — check this first |
| `asmFile.asm` | The generated Intel 8086 assembly |
| `optasmFile.asm` | The same assembly after the peephole optimizer |

To confirm your build is behaving, compile `samples/reference/input3.txt` and diff your
`parserLog.txt` against the expected `samples/reference/log3.txt`.

To actually execute the generated assembly, load `optasmFile.asm` into **emu8086**, or
assemble it with TASM/MASM under DOSBox.

## The language it accepts

**Types** — `int`, `float`, `void` (`void` only as a function return type).

**Declarations** — global and local variables, one-dimensional arrays (`int a[10];`),
function declarations, and function definitions with parameters.

**Statements** — assignment, `if`, `if`/`else`, `while`, `for`, `return`, and `println(x)`
for printing an integer.

**Expressions** — the full precedence chain: logical (`&&`, `||`), relational
(`<`, `<=`, `>`, `>=`, `==`, `!=`), additive (`+`, `-`), multiplicative (`*`, `/`, `%`),
unary (`-`, `!`), postfix increment and decrement (`++`, `--`), parenthesized
subexpressions, array subscripts, and function calls.

**Comments** — both `// line` and `/* block */`, skipped and logged by the lexer.

Example (`samples/test.c`):

```c
int w[10];
int main(){
	int i;
	int x[10];
	w[0] = -2;
	x[0] = w[0];
	i = x[0];
	println(i);

	if ((i > 0 && i < 10) || (i < 0 && i > -10))
		i = 100;
	else
		i = 200;
	println(i);

	return 0;
}
```

> **Note for contributors:** the lexer already defines tokens for `switch`, `case`,
> `break`, `default`, `foreach`, `forin`, `in`, `to`, `times`, `when`, `->` and `?`, but
> the parser does not use them yet. Wiring those into `C2105133Parser.g4` is the most
> natural place to start extending the language.

## Errors it reports

Error recovery is built into the grammar, so the compiler keeps going after an error and
reports as many as it can in a single run.

**Syntax errors** — unexpected tokens in a declaration list, a malformed parameter list,
and the usual missing-comma / missing-semicolon cases, each reported with the token that
was found and the one that was expected.

**Semantic errors**, reported with the offending line number:

- `Multiple declaration of x` — a variable, parameter, or function redeclared in the same scope
- `Undeclared variable x` / `Undeclared function f`
- `Variable type cannot be void`
- `Type Mismatch` — for example assigning a `float` expression to an `int`
- `x is an array` / `x not an array` — using a variable with the wrong kind of access
- `Expression inside third brackets not an integer` — a non-integer array subscript
- `Non-Integer operand on modulus operator` and `Modulus by Zero`
- `Void function used in expression`
- `Total number of arguments mismatch` — in a call, or against the earlier declaration
- `Return type mismatch with function declaration in function f`

## Optimizations

The peephole pass in `C2105133Parser.g4` rewrites the emitted assembly by:

- collapsing a redundant `MOV a, b` / `MOV b, a` pair into a single instruction,
- deleting a `PUSH r` immediately followed by `POP r`,
- deleting identity arithmetic — `ADD r, 0`, `SUB r, 0`, `MUL r, 1`, `IMUL r, 1`,
- deleting a `JMP L` that jumps to the label on the very next line,
- merging consecutive labels into one and retargeting every jump that pointed at the
  merged labels.

Diff `output/asmFile.asm` against `output/optasmFile.asm` to see the pass at work.

## Where to make changes

| To change… | Edit… |
| --- | --- |
| Tokens, keywords, comment handling, the lexer log | `src/C2105133Lexer.g4` |
| Grammar rules, semantic checks, error messages, 8086 codegen, the optimizer | `src/C2105133Parser.g4` |
| Scope handling, hashing (`sdbm` / `djb2`), bucket count | `src/2105133_ScopeTable.h`, `src/2105133_SymbolTable.h` |
| What a symbol stores | `src/2105133_SymbolInfo.h` |
| Output paths, the symbol table's size or hash function | `src/Ctester.cpp` |
| Hand-written assembly routines like `println` | `src/library.txt` |

After any change, just re-run `bash run-script.sh ../samples/test.c` — the script always
regenerates the parser from the grammars, so there is no separate build step to remember.

## Troubleshooting

**`antlr4: command not found`** — `antlr4-tools` is not installed, or `~/.local/bin` is not
on your `PATH`. See [step 2](#2-the-antlr-tool).

**`fatal error: antlr4-runtime.h: No such file or directory`** — the C++ runtime was not
installed into `/usr/local`. Redo [step 3](#3-the-antlr-c-runtime) and make sure
`sudo make install` succeeded.

**`error while loading shared libraries: libantlr4-runtime.so`** — run `sudo ldconfig`.
The script already sets `LD_LIBRARY_PATH=/usr/local/lib` for the run itself.

**`Error opening lexer log file: output/…`** — you ran the script from the repository root
instead of from `src/`. `cd src` first.

**Empty or stale output** — a previous build may have failed after generating only part of
the parser. Run `git clean -Xdf` from the repository root and build again.

## Acknowledgements

Built as a compiler course project. Code generation targets the Intel 8086 instruction
set. For background on the tooling, see the
[official ANTLR 4 documentation](https://github.com/antlr/antlr4/blob/master/doc/index.md)
and the [C++ target guide](https://github.com/antlr/antlr4/blob/master/doc/cpp-target.md).
