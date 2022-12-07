module WASMCompiler

using LLVM
using LLVM.Interop

using ExprTools: splitdef, combinedef
using TimerOutputs
using Logging
using UUIDs
using Libdl

include("runtime.jl")
include("target.jl")

end
