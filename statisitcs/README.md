# Statistics about program generators

# Smart generator vs ordinary one

The smart generator build the two concurrent suffixes maintaining the correction
precondition-wise for all interleaving.

The ordinary generator use the same construction in the sequential prefix
and the two concurrent suffixes. This version does not throw away bad test
input.
