# Statistics about program generators

# Smart generator vs ordinary one

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

The ordinary generator use the same construction in the sequential prefix
and the two concurrent suffixes. This version does not throw away bad test
input.
