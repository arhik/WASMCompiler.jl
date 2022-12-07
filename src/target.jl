using StaticTools
using GPUCompiler
using LLVM
using LLVM: Interop

include("pointers.jl")

export WasmCompilerTarget

module WasmRuntime
	signal_exception() = return
	malloc(sz) = C_NULL
	report_oom(sz) = return
	report_exception(ex) = return
	report_exception_name(ex) = return
	report_exception_frame(idx, func, file, line) = return
end

struct WasmCompilerParams <: GPUCompiler.AbstractCompilerParams end
struct WasmCompilerTarget <: GPUCompiler.AbstractCompilerTarget end

GPUCompiler.runtime_slug(job::GPUCompiler.CompilerJob{WasmCompilerTarget}) = "wasm32-unknown-wasi"

GPUCompiler.llvm_triple(target::WasmCompilerTarget) = "wasm32-unknown-wasi"
GPUCompiler.llvm_datalayout(target::WasmCompilerTarget) = "e-m:e-p:32:32:32-i64:32:32-n32-S128"

function GPUCompiler.llvm_machine(target::WasmCompilerTarget)
    triple = GPUCompiler.llvm_triple(target)

    t = LLVM.Target(triple=triple)

    tm = LLVM.TargetMachine(t, triple)
    asm_verbosity!(tm, true)
    return tm
end

GPUCompiler.runtime_module(::GPUCompiler.CompilerJob{<:Any, WasmCompilerParams}) = WasmRuntime

function GPUCompiler.process_module!(@nospecialize(job::GPUCompiler.CompilerJob{WasmCompilerTarget}), mod::LLVM.Module)
    ctx = context(mod)
    for f in functions(mod)
        # @info f
    end
end


function wasm_job(@nospecialize(func), @nospecialize(types); kernel::Bool=false, name=GPUCompiler.safe_name(repr(func)), kwargs...)
	source = GPUCompiler.FunctionSpec(func, Base.to_tuple_type(types), kernel, name)
	target = WasmCompilerTarget()
	params = WasmCompilerParams()
	job = GPUCompiler.CompilerJob(target, source, params)
	(job, kwargs)
end

@inline function typed_signature(@nospecialize(job::CompilerJob))
    u = Base.unwrap_unionall(job.source.tt)
    return Base.rewrap_unionall(Tuple{job.source.f, u.parameters...}, job.source.tt)
end
	
# obj, _ = GPUCompiler.codegen(:obj, job; strip=true, only_entry=false, validate=false)

"""

"""

function trackPointerInSignature(f::Function)
	
end


function generate_wasm(f, tt; wasi=false, path="./temp", name=GPUCompiler.safe_name(repr(f)),
		filename=string(name),
		cflags=`-nostartfiles -nostdlib -Wl,--export-all -Wl,--no-entry -Wl,--allow-undefineds`,
		kwargs...
	)
	
	mkpath(path)
	objPath = joinpath(path, "$(filename).o")
	llPath = joinpath(path, "$(filename).ll")
	execPath = joinpath(path, "$filename.wasm")
	htmlPath = joinpath(path, "$(filename).html")
	(job, kwargs) = wasm_job(f, tt; kernel=false, name=name, kwargs=kwargs)

	# mi, _ = GPUCompiler.emit_julia(job)
	#
	# llvm_ir , ir_meta  = GPUCompiler.emit_llvm(
		# job,
		# mi;
		# libraries=false,
		# deferred_codegen=false,
		# optimize=true,
		# only_entry=false,
		# ctx = JuliaContext()
	# )
	#
	
	mod, meta = GPUCompiler.JuliaContext() do context
		GPUCompiler.codegen(:llvm, job; strip=true, only_entry=false, validate=false, optimize=true, ctx=context)
	end
	
	ctx = LLVM.context(mod)
	i32 = LLVM.IntType(32; ctx)
	
	builder = LLVM.Builder(ctx)
	
	# Ptr{T} in julia are passed i64 arguments in LLVM codegen.
	# [ Info: Argument[i64 %0, i32 %1]
	# [ Info: Argument[{}* %0, i64 %1, i64 %2, i64 %3]
	# We need to convert arguments to i32 at all Ptr{T} usages
	# This whole for block is just that.
	# TODO move it to a function.
	# Quick fix for simple functions.
	# TODO will have to think of users perspective.
	for fn in LLVM.functions(mod)
		if !LLVM.isdeclaration(fn)
			fixBB(fn, mod)
		end
	end

	for fn in LLVM.functions(mod)
		if LLVM.isdeclaration(fn)
			fixPointers(fn, mod)
		end
	end
	
	for fn in LLVM.functions(mod)
		if !LLVM.isdeclaration(fn)
			fixBB(fn, mod)
		end
	end

# 
	@info "Final Module" mod

	GPUCompiler.optimize!(job, mod)
	
	LLVM.verify(mod)
	
	open(objPath, "w") do io
		write(io, mod)
	end
	
	if wasi==true
		# TODO
      	run(`wasm-ld -m wasm32 --export-all $objPath -o $(execPath)`)
	else
    	run(`wasm-ld -m wasm32 --no-entry --export-all --allow-undefined $objPath -o $(execPath)`)
    end
    
    run(`wasm2wat $execPath`)
end


function toWasm(str::String)
	return """
		function passStringToWasm(str) {
			const buf = new TextEncoder("utf-8").encode(str);
			const len = buf.length;
			const ptr = instance.exports.__wbindgen_malloc(len);
			let array = new Uint8Array(instance.exports.memory.buffer);
			array.set(buf, ptr);
			return [ptr, len];
		}
	"""
end


function fromWasm(ptr::Ptr{UInt8}, len::UInt8) # TODO types instead
	return """
		function getStringFromWasm(ptr, len) {
			const mem = new Uint8Array(instance.exports.memory.buffer);
			const slice = mem.slice(ptr, ptr + len);
			const ret = new TextDecode(utf-8).decode(slice);
			return ret;
		}
	"""
end


function render(filename)
	html_ = """
		<!DOCTYPE html>
		<script type="module">

		  async function init() {
		  	$(toWasm(""))
		  	$(fromWasm(Ptr{UInt8}(), 0 |> UInt8))
		    const { instance } = await WebAssembly.instantiateStreaming(
		      	fetch("$(filename).wasm"),
				{
					"env" : {
						"memset" : (...args) => { console.error("Not Implemented")},
						"malloc" : (...args) => { console.error("Not Implemented")},
						"realloc" : (...args) => { console.error("Not Implemented")},
						"free" : (...args) => { console.error("Not Implemented")},
						"memcpy" : (...args) => { console.error("Not Implemented")},
						"stbsp_sprintf" : (...args) => { console.error("Not Implemented")},
						"memcmp" : (...args) => { console.error("Not Implemented")},
						"write" : (...args) => { console.error("Not Implemented")},
						"toJSString" : (ptr, len) => {
							const strArray = instance.exports.memory.buffer.slice(ptr, ptr - len)
							const textDecoder = new TextDecoder("utf-8");
							var str = textDecoder.decode(strArray)
							console.log(str)
							return str
						},
						"console_log" : (...args) => {
							console.log(args)
						},
						"puts" : (ptr, len) => {
							let a = new Uint8Array(instance.exports.memory.buffer.slice(ptr, ptr+len))
							console.log(a)
						},
						"__multi3": (...args) => {
							console.log(args)
						},
						"getMemory": () => {
							let a = new Int32Array(instance.exports.memory.buffer)
							return a
						},
						"readGMemory": (ptr) => {
							let view = new Int32Array(ptr)
							console.log(view.slice(0, 5))
						},
						"ijl_apply_generic": (...args) => {
							console.log("jl_apply_generic not defined: ", args)
						},
						"printString" : (ptr, len) => {
							ptr = parseInt(ptr)
							console.log(ptr, len)
							let array = instance.exports.memory.buffer.slice(ptr, ptr-len)
							const decoder = new TextDecoder();
							const str = decoder.decode(array)
							console.log(str)
							return str
						},
						"jsAllocate" : (len) => {
							const ptr = new Uint8Array(len)
							return ptr
						},
						"jsDeallocate" : (ptr) => {
							ptr = undefined
						}
					}
				}
		    );
	        // const array = new Int32Array(instance.exports.memory.buffer, 0, 5)
  			// array.set([3, 15, 18, 4, 2])
		   	console.log(instance.exports.julia_$filename())
		    // console.log(instance.exports.julia_$filename(3))
		  }
		  init();
		</script>
	"""
end

using MacroTools

function wasmgen(expr)
	@capture(expr, function f_(x__) body__ end)
	# @info f x body
end

macro wasmgen(expr)
	wasmgen(expr)
end

# @wasmgen

"""
	declare void @toJSString(i32*, i32)

	define void @main(i64 %strPtr, i32 %strLen) #0 {
	entry:
	    %niptr = inttoptr i64 %strPtr to i32*
	    call i32 @toJSString(i8* %niptr, i32 %strLen)
	    ret void
	}

	attributes #0 = { alwaysinline nounwind ssp uwtable }
"""

# function toJSString(a, l)
	# Base.llvmcall(
		# (
			# """
			# declare void @toJSString(i32, i32) local_unnamed_addr
			# """,
			# "toJSString"
		# ),
		# Cvoid,
		# Tuple{Ptr{UInt8}, UInt32},
		# a, l
	# )
# end

function toJSString(a, l)
	ccall("extern toJSString", llvmcall, Cvoid, (Int32, Int32), a, l)
end

function jsAllocate(len)
	ccall("extern jsAllocate", llvmcall, Ptr{UInt8}, (UInt32,), len)
end

function jsDeallocate(aptr)
	ccall("extern jsDeallocate", llvmcall, Cvoid, (Ptr{UInt8},), aptr)
end

function printString(ptr::Ptr{UInt8}, len::UInt32)
	ccall("extern printString", llvmcall, Cvoid, (Ptr{UInt8}, UInt32), ptr, len)
end

function consoleLog(a)
	ccall("extern console.log", llvmcall, Cvoid, (Any,), a)
end

function getMemory()
	ccall("extern getMemory", llvmcall, Cvoid, ())
end

function readGMemory(p)
	ccall("extern readGMemory", llvmcall, Cvoid, (Any,), p)
end

# function getHeap()
	# ccall("extern getHeap", llvmcall, Cvoid, ())
# end

@inline function puts(a, l)
	toString(a, l)
end

function testingFunc(b)
	return b*b
end

@inline function length(s::StaticString)
	return Base.length(s)
end

function constMul(a)
	b = (a)*41.3f0
	# s = c"Hello"
	# l = length(s) |> UInt32
	# ptr_s = pointer(s)
	# toJSString(ptr_s, l)
	return b
end


function genWasm(f, args...; wasi=false)
	generate_wasm(f, args...; wasi=wasi)
	path = "./temp"
	htmlPath = joinpath(path, "$(nameof(f)).html")
	
	html_ = render(nameof(f))
	
	open(htmlPath, "w") do io
		write(io, html_)
	end
	
	run(`python -m http.server 8004`)
end

# Passing arrays to wasm

function addTwoInts(a::UInt32, b::UInt32)
    return a + b;
end

# function sumArrayInt32(ptr::Ptr{UInt32}, len::UInt32)
	# return unsafe_load(ptr, 3 |> UInt32)
# end

function sumArrayInt32(ptr::Ptr{UInt32}, len::UInt32)
	total::UInt32 = 0 # TODO we should capture these eventually in macros maybe
	for i in 1:len
		total+= unsafe_load(ptr, i |> UInt32)
	end
	return total
end

# Passing strings
function cconsoleLog(str::StaticString)
	ptr = pointer(str)
	len::UInt32 = Base.length(str)
	printString(ptr, len)
end

function readInt32Array(ptr::Ptr{UInt32}, len::UInt32)
	memory = getMemory()
	consoleLog(memory)
	return readGMemory(memory)
end

# function sumArrayInt32(ptr::Ptr{UInt32}, len::UInt32)
	# mem = getMemory()
	# # memptr = convert(Ptr{UInt32}, mem)
	# return mem
	# # array = unsafe_wrap(MallocArray{UInt32}, ptr, (len,))
	# # return sum(array)
# end

const gHeap = StackArray(zeros(UInt32, 1024))

const hello = "Hello World"

function getHeap()
	return gHeap
end

function printf()
	str = c"Hello343223t"
	alen::UInt32 = Base.length(str)
	aptr = jsAllocate(alen)
	for i in 1:alen
		unsafe_store!(aptr + i, str[i])
	end
	printString(aptr, alen)
	jsDeallocate(aptr)
end

# genWasm(addTwoInts, (UInt32, UInt32); wasi=false)
# genWasm(sumArrayInt32, (Ptr{UInt32}, UInt32); wasi=false)
# genWasm(cconsoleLog, (StaticString,); wasi=false)
# genWasm(readInt32Array, (Ptr{UInt32}, UInt32); wasi=false)
# genWasm(constMul, (UInt32,); wasi=false)

# genWasm(printf, (); wasi=false)

