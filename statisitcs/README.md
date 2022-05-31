# Statistics about program generators

## Smart generator vs ordinary one

The smart generator build the two concurrent suffixes maintaining the correction
precondition-wise for all interleaving. That means checking checking for two things
before adding a command at the end of a process:

- the commands preconditions will be respected whatever the interleaving of the previous ones
- whenever the command is run (at the end of the process it is added to) it won't break the preconditions of the remaining commands of the other process.

In order to add a new command, we need a general generator able to generate any command given in the `StmSpec`
module. We pick one and check whether it is a valid command precondition-wise in the concurrent setting.
If it is not, we try again. In order to avoid an infinite recursion, and also because checking
for precondition validity in a concurrent setting is costly (factorial in the number of commands), we limit
the number of retry (2 retries, so 3 attempts). When the number of attempts is exhausted, we stop
the generation of the concurrent suffixes, returning shorter list of commands rather than failing.

The ordinary generator use the same construction for the sequential prefix
and the two concurrent suffixes relying on a generator depending on only one state.
So this generator will generate test inputs that are not valid precondition-wise.
These test inputs will then be filtered out at the moment of the test.

## Comparison of speed generating a thousand of valid test inputs

In the `thousand.ml` program, we generate a thousand of programs that are valid precondition-wise
with respectively the smart generator and the ordinary one. In order to have one thousand valid
program with the ordinary generator we filter out the non valid one with the `QCheck.assume` function
and raise the `~max_gen` argument of `Test.make` to `3000` (more that a half of the generated programs
are thrown away.

But as the precondition validity check is done only once per test input (and is quadratic rather than factorial)
the generate-and-throw-away strategy still run faster than the smart one.

```bash
$ hyperfine "dune exec -- ./thousand.exe smart" "dune exec -- ./thousand.exe ordinary"
Benchmark 1: dune exec -- ./thousand.exe smart
  Time (mean ± σ):      3.980 s ±  0.144 s    [User: 3.941 s, System: 0.020 s]
  Range (min … max):    3.683 s …  4.195 s    10 runs

Benchmark 2: dune exec -- ./thousand.exe ordinary
  Time (mean ± σ):     217.4 ms ±  19.9 ms    [User: 194.1 ms, System: 14.9 ms]
  Range (min … max):   189.9 ms … 264.0 ms    13 runs

Summary
  'dune exec -- ./thousand.exe ordinary' ran
   18.30 ± 1.80 times faster than 'dune exec -- ./thousand.exe smart'
```
